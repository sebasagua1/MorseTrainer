import Foundation
import SwiftData

// MARK: - Modelos persistidos

@Model
final class PlayerProfile {
    var highestUnlockedLevel: Int = 1
    var copper: Int = 0
    var streakDays: Int = 0
    /// Último día jugado, normalizado a medianoche local.
    var lastPlayedDay: Date?
    var totalDrills: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \LetterRecord.profile)
    var letters: [LetterRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \ConfusionRecord.profile)
    var confusions: [ConfusionRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionRecord.profile)
    var sessions: [SessionRecord] = []

    init() {}
}

/// Historial de por vida de un carácter. `symbol` es `String` y no `Character`
/// porque SwiftData solo persiste tipos `Codable`, y `Character` no lo es.
@Model
final class LetterRecord {
    var symbol: String = ""
    var attempts: Int = 0
    var correct: Int = 0
    var medianResponseTime: Double = 0
    var lastPracticed: Date = Date()
    var profile: PlayerProfile?

    init(symbol: String) { self.symbol = symbol }

    var character: Character? { symbol.first }
    var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
}

@Model
final class ConfusionRecord {
    var shown: String = ""
    var answered: String = ""
    var count: Int = 0
    var lastSeen: Date = Date()
    var profile: PlayerProfile?

    init(shown: String, answered: String) {
        self.shown = shown
        self.answered = answered
    }
}

@Model
final class SessionRecord {
    var levelID: Int = 0
    var date: Date = Date()
    var accuracy: Double = 0
    var copperEarned: Int = 0
    var mastered: Bool = false
    var medianResponseTime: Double = 0
    var profile: PlayerProfile?

    init(levelID: Int) { self.levelID = levelID }
}

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
        let schema = Schema([PlayerProfile.self, LetterRecord.self,
                             ConfusionRecord.self, SessionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
            isEphemeral = inMemory
        } catch {
            // Un almacén corrupto no debe dejar la app inservible: se degrada a
            // memoria y el jugador puede seguir practicando esta sesión.
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
