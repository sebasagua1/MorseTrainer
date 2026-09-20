import Foundation
import SwiftData

// MARK: - Store

@MainActor
final class PersistenceStore {

    let container: ModelContainer
    /// `true` si el almacén de disco falló y se está trabajando en memoria.
    /// La partida de hoy funciona, pero no sobrevivirá al cierre de la app.
    private(set) var isEphemeral = false

    private var context: ModelContext { container.mainContext }

    // MARK: Conversión historial → prior de sesión
    //
    // El historial no se siembra tal cual. Un carácter con 200 intentos al 95 %
    // tendría una precisión imposible de mover dentro de una sesión: si hoy el
    // jugador empieza a fallarlo, el programador tardaría semanas en notarlo.
    // Se siembra una versión *encogida* que conserva la precisión pero no el
    // volumen, así la historia informa la cola inicial sin congelarla.
    private let historyWeight = 0.5
    private let maxSeededAttempts = 12
    private let maxSeededConfusion = 3

    init(inMemory: Bool = false) {
        // El esquema se deriva de la versión, no de una lista suelta de modelos:
        // así el contenedor y el plan de migración no pueden desincronizarse.
        let schema = Schema(versionedSchema: MorseSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema,
                                           migrationPlan: MorseMigrationPlan.self,
                                           configurations: configuration)
            isEphemeral = inMemory
        } catch {
            // Aquí cae tanto un almacén corrupto como una migración fallida. En
            // ambos casos se degrada a memoria y **no se borra el archivo**: los
            // datos del jugador siguen en disco, recuperables con una corrección
            // posterior. Borrarlo para «arreglar» el arranque sería destruir lo
            // único que permite salvarlos.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: fallback)
            isEphemeral = true
        }
    }

    // MARK: Perfil

    @discardableResult
    func profile() -> PlayerProfile {
        let descriptor = FetchDescriptor<PlayerProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        if let existing = try? context.fetch(descriptor).first { return existing }
        let profile = PlayerProfile()
        context.insert(profile)
        save()
        return profile
    }

    private func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }

    // MARK: Siembra del programador

    /// Prior para una lección: qué sabe el motor sobre este jugador **antes**
    /// de que empiece a responder.
    func seed(for alphabet: [Character]) -> (stats: [Character: CharacterStat],
                                             confusions: [ConfusionPair: Int]) {
        let profile = profile()
        let allowed = Set(alphabet)

        var stats: [Character: CharacterStat] = [:]
        for record in profile.letters {
            guard let character = record.character, allowed.contains(character),
                  record.attempts > 0 else { continue }

            let attempts = min(maxSeededAttempts, Int((Double(record.attempts) * historyWeight).rounded()))
            guard attempts > 0 else { continue }
            let correct = Int((record.accuracy * Double(attempts)).rounded())

            var stat = CharacterStat(character: character)
            stat.attempts = attempts
            stat.correct = min(correct, attempts)
            stat.medianResponseTime = record.medianResponseTime
            // Sin penalización de recencia: la sesión empieza limpia.
            stat.lastSeenIndex = -999
            stats[character] = stat
        }

        var confusions: [ConfusionPair: Int] = [:]
        for record in profile.confusions {
            guard let shown = record.shown.first, let answered = record.answered.first,
                  allowed.contains(shown), allowed.contains(answered) else { continue }
            let count = min(maxSeededConfusion, Int((Double(record.count) * historyWeight).rounded()))
            guard count > 0 else { continue }
            confusions[ConfusionPair(shown: shown, answered: answered)] = count
        }

        return (stats, confusions)
    }

    // MARK: Fusión al terminar una lección

    /// Funde el resultado de la lección con el histórico. `stats` y `confusions`
    /// vienen del `DrillScheduler`, que ya incluye lo sembrado, así que se resta
    /// el prior para no contar dos veces lo que ya estaba en disco.
    func merge(summary: LessonSummary,
               stats: [Character: CharacterStat],
               confusions: [ConfusionPair: Int],
               seededStats: [Character: CharacterStat],
               seededConfusions: [ConfusionPair: Int]) {
        let profile = profile()
        var lettersBySymbol = Dictionary(uniqueKeysWithValues: profile.letters.map { ($0.symbol, $0) })

        for (character, stat) in stats {
            let seeded = seededStats[character]
            let newAttempts = stat.attempts - (seeded?.attempts ?? 0)
            let newCorrect = stat.correct - (seeded?.correct ?? 0)
            guard newAttempts > 0 else { continue }

            let symbol = String(character)
            let record = lettersBySymbol[symbol] ?? {
                let fresh = LetterRecord(symbol: symbol)
                fresh.profile = profile
                context.insert(fresh)
                lettersBySymbol[symbol] = fresh
                return fresh
            }()

            record.attempts += newAttempts
            record.correct += max(0, newCorrect)
            record.lastPracticed = .now
            if stat.medianResponseTime > 0 {
                record.medianResponseTime = record.medianResponseTime == 0
                    ? stat.medianResponseTime
                    : record.medianResponseTime * 0.7 + stat.medianResponseTime * 0.3
            }
        }

        var confusionsByKey = Dictionary(
            uniqueKeysWithValues: profile.confusions.map { ($0.shown + $0.answered, $0) }
        )
        for (pair, count) in confusions {
            let delta = count - (seededConfusions[pair] ?? 0)
            guard delta > 0 else { continue }
            let key = "\(pair.shown)\(pair.answered)"
            let record = confusionsByKey[key] ?? {
                let fresh = ConfusionRecord(shown: String(pair.shown), answered: String(pair.answered))
                fresh.profile = profile
                context.insert(fresh)
                confusionsByKey[key] = fresh
                return fresh
            }()
            record.count += delta
            record.lastSeen = .now
        }

        let session = SessionRecord(levelID: summary.levelID)
        session.accuracy = summary.accuracy
        session.copperEarned = summary.copperEarned
        session.mastered = summary.mastered
        session.medianResponseTime = summary.medianResponseTime.isFinite ? summary.medianResponseTime : 0
        session.profile = profile
        context.insert(session)

        profile.copper += summary.copperEarned
        profile.totalDrills += stats.values.reduce(0) { $0 + $1.attempts }
        if summary.mastered {
            profile.highestUnlockedLevel = max(profile.highestUnlockedLevel, summary.levelID + 1)
        }
        save()
    }

    // MARK: Racha diaria

    /// Registra que hoy se ha jugado y devuelve la racha resultante.
    /// Se compara por *día natural*, no por 24 h: jugar a las 23:50 y a las
    /// 00:10 son dos días de racha, que es lo que el jugador espera ver.
    @discardableResult
    func registerPlay(on date: Date = .now, calendar: Calendar = .current) -> Int {
        let profile = profile()
        let today = calendar.startOfDay(for: date)

        guard let last = profile.lastPlayedDay else {
            profile.streakDays = 1
            profile.lastPlayedDay = today
            save()
            return 1
        }

        let lastDay = calendar.startOfDay(for: last)
        if lastDay == today { return profile.streakDays }

        let days = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        profile.streakDays = days == 1 ? profile.streakDays + 1 : 1
        profile.lastPlayedDay = today
        save()
        return profile.streakDays
    }

    // MARK: Consultas para la UI

    var copper: Int { profile().copper }
    var streakDays: Int { profile().streakDays }
    var highestUnlockedLevel: Int { profile().highestUnlockedLevel }

    func spend(copper amount: Int) -> Bool {
        let profile = profile()
        guard profile.copper >= amount else { return false }
        profile.copper -= amount
        save()
        return true
    }

    /// Letras con peor precisión histórica, para la pantalla de perfil.
    func weakestLetters(limit: Int = 5) -> [LetterRecord] {
        profile().letters
            .filter { $0.attempts >= 5 }
            .sorted { $0.accuracy < $1.accuracy }
            .prefix(limit)
            .map { $0 }
    }
}
