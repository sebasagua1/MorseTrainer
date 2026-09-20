import Foundation
import Testing
@testable import MorseTrainer

@Suite("Persistencia", .serialized)
@MainActor
struct PersistenceStoreTests {

    private func makeStore() -> PersistenceStore {
        PersistenceStore(inMemory: true)
    }

    private func summary(levelID: Int = 1, mastered: Bool = false, copper: Int = 0,
                         mode: GameSession.Mode = .level) -> LessonSummary {
        LessonSummary(mode: mode, levelID: levelID, itemsCorrect: 1, itemsTotal: 1,
                      topEffectiveWPM: 10, accuracy: 1, heartsRemaining: 3,
                      copperEarned: copper, mastered: mastered,
                      medianResponseTime: 1, weakSpots: [])
    }

    private func record(_ store: PersistenceStore, symbol: Character) -> LetterRecord? {
        store.profile().letters.first { $0.symbol == String(symbol) }
    }

    // MARK: Perfil

    @Test("Un almacén nuevo empieza con el nivel 1 y sin cobre")
    func freshProfile() {
        let store = makeStore()
        #expect(store.highestUnlockedLevel == 1)
        #expect(store.copper == 0)
        #expect(store.streakDays == 0)
    }

    @Test("El perfil es único: dos lecturas devuelven el mismo")
    func profileIsSingleton() {
        let store = makeStore()
        let first = store.profile()
        first.copper = 7
        #expect(store.profile().copper == 7)
    }

    // MARK: Fusión

    @Test("La primera fusión escribe los intentos tal cual")
    func firstMergeWritesAttempts() {
        let store = makeStore()
        var scheduler = DrillScheduler(alphabet: ["E", "T"], newCharacters: ["E"])
        for index in 0..<10 {
            scheduler.record(shown: "E", answered: index < 8 ? "E" : "T", responseTime: 1)
        }
        store.merge(summary: summary(), stats: scheduler.stats,
                    confusions: scheduler.confusions,
                    seededStats: [:], seededConfusions: [:])

        #expect(record(store, symbol: "E")?.attempts == 10)
        #expect(record(store, symbol: "E")?.correct == 8)
    }

    /// Regresión: el programador acumula *sobre* lo sembrado, así que fusionar
    /// sin restar el prior volvía a sumar el historial en cada lección.
    @Test("Una lección sembrada y sin responder no altera el histórico")
    func mergeDoesNotDoubleCountSeededHistory() {
        let store = makeStore()
        var first = DrillScheduler(alphabet: ["E", "T"], newCharacters: ["E"])
        for _ in 0..<10 { first.record(shown: "E", answered: "E", responseTime: 1) }
        store.merge(summary: summary(), stats: first.stats, confusions: first.confusions,
                    seededStats: [:], seededConfusions: [:])
        let baseline = record(store, symbol: "E")?.attempts

        // Segunda lección: se siembra y se cierra sin responder nada.
        let seed = store.seed(for: ["E", "T"])
        let second = DrillScheduler(alphabet: ["E", "T"], newCharacters: ["E"],
                                    seededStats: seed.stats, seededConfusions: seed.confusions)
        store.merge(summary: summary(), stats: second.stats, confusions: second.confusions,
                    seededStats: seed.stats, seededConfusions: seed.confusions)

        #expect(record(store, symbol: "E")?.attempts == baseline)
    }

    @Test("Lo respondido tras sembrar sí se suma")
    func mergeAddsOnlyNewWork() {
        let store = makeStore()
        var first = DrillScheduler(alphabet: ["E", "T"])
        for _ in 0..<10 { first.record(shown: "E", answered: "E", responseTime: 1) }
        store.merge(summary: summary(), stats: first.stats, confusions: first.confusions,
                    seededStats: [:], seededConfusions: [:])

        let seed = store.seed(for: ["E", "T"])
        var second = DrillScheduler(alphabet: ["E", "T"],
                                    seededStats: seed.stats, seededConfusions: seed.confusions)
        for _ in 0..<4 { second.record(shown: "E", answered: "E", responseTime: 1) }
        store.merge(summary: summary(), stats: second.stats, confusions: second.confusions,
                    seededStats: seed.stats, seededConfusions: seed.confusions)

        #expect(record(store, symbol: "E")?.attempts == 14)
    }

    @Test("Las confusiones se acumulan sin duplicar el prior")
    func confusionsMergeWithoutDuplication() {
        let store = makeStore()
        let pair = ConfusionPair(shown: "S", answered: "H")
        var first = DrillScheduler(alphabet: ["S", "H"])
        for _ in 0..<4 { first.record(shown: "S", answered: "H", responseTime: 1) }
        store.merge(summary: summary(), stats: first.stats, confusions: first.confusions,
                    seededStats: [:], seededConfusions: [:])
        let stored = store.profile().confusions.first { $0.shown == "S" && $0.answered == "H" }
        #expect(stored?.count == 4)

        let seed = store.seed(for: ["S", "H"])
        #expect(seed.confusions[pair] != nil)
        let second = DrillScheduler(alphabet: ["S", "H"],
                                    seededStats: seed.stats, seededConfusions: seed.confusions)
        store.merge(summary: summary(), stats: second.stats, confusions: second.confusions,
                    seededStats: seed.stats, seededConfusions: seed.confusions)
        #expect(stored?.count == 4)
    }

    @Test("Superar un nivel desbloquea el siguiente y suma cobre")
    func masteryUnlocksAndPays() {
        let store = makeStore()
        store.merge(summary: summary(levelID: 3, mastered: true, copper: 55),
                    stats: [:], confusions: [:], seededStats: [:], seededConfusions: [:])
        #expect(store.highestUnlockedLevel == 4)
        #expect(store.copper == 55)
    }

    @Test("Fallar un nivel paga lo ganado pero no desbloquea")
    func failurePaysButDoesNotUnlock() {
        let store = makeStore()
        store.merge(summary: summary(levelID: 1, mastered: false, copper: 12),
                    stats: [:], confusions: [:], seededStats: [:], seededConfusions: [:])
        #expect(store.highestUnlockedLevel == 1)
        #expect(store.copper == 12)
    }

    @Test("Rejugar un nivel ya superado no retrocede el desbloqueo")
    func replayDoesNotRegress() {
        let store = makeStore()
        store.merge(summary: summary(levelID: 5, mastered: true),
                    stats: [:], confusions: [:], seededStats: [:], seededConfusions: [:])
        store.merge(summary: summary(levelID: 2, mastered: true),
                    stats: [:], confusions: [:], seededStats: [:], seededConfusions: [:])
        #expect(store.highestUnlockedLevel == 6)
    }

    // MARK: Siembra

    @Test("La siembra conserva la precisión pero recorta el volumen")
    func seedShrinksHistory() {
        let store = makeStore()
        var scheduler = DrillScheduler(alphabet: ["E"])
        for _ in 0..<40 { scheduler.record(shown: "E", answered: "E", responseTime: 1) }
        store.merge(summary: summary(), stats: scheduler.stats, confusions: [:],
                    seededStats: [:], seededConfusions: [:])

        let seeded = store.seed(for: ["E"]).stats["E"]
        #expect(seeded != nil)
        #expect(seeded!.attempts <= 12)          // tope, no los 40 reales
        #expect(seeded!.attempts < 40)
        #expect(seeded!.accuracy == 1.0)         // la precisión sobrevive
    }

    @Test("La siembra no arrastra penalización de recencia")
    func seedHasNoRecency() {
        let store = makeStore()
        var scheduler = DrillScheduler(alphabet: ["E"])
        for _ in 0..<10 { scheduler.record(shown: "E", answered: "E", responseTime: 1) }
        store.merge(summary: summary(), stats: scheduler.stats, confusions: [:],
                    seededStats: [:], seededConfusions: [:])
        #expect(store.seed(for: ["E"]).stats["E"]!.lastSeenIndex < 0)
    }

    @Test("La siembra solo devuelve caracteres del alfabeto pedido")
    func seedFiltersByAlphabet() {
        let store = makeStore()
        var scheduler = DrillScheduler(alphabet: ["E", "Z"])
        for _ in 0..<6 {
            scheduler.record(shown: "E", answered: "E", responseTime: 1)
            scheduler.record(shown: "Z", answered: "Z", responseTime: 1)
        }
        store.merge(summary: summary(), stats: scheduler.stats, confusions: [:],
                    seededStats: [:], seededConfusions: [:])

        let seed = store.seed(for: ["E"])
        #expect(seed.stats["E"] != nil)
        #expect(seed.stats["Z"] == nil)
    }

    // MARK: Racha

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    @Test("La primera partida arranca la racha en 1")
    func streakStartsAtOne() {
        let store = makeStore()
        #expect(store.registerPlay(on: date(1), calendar: calendar) == 1)
    }

    @Test("Jugar dos veces el mismo día no sube la racha")
    func sameDayDoesNotIncrement() {
        let store = makeStore()
        store.registerPlay(on: date(1, hour: 9), calendar: calendar)
        #expect(store.registerPlay(on: date(1, hour: 22), calendar: calendar) == 1)
    }

    @Test("Días consecutivos suman")
    func consecutiveDaysIncrement() {
        let store = makeStore()
        store.registerPlay(on: date(1), calendar: calendar)
        store.registerPlay(on: date(2), calendar: calendar)
        #expect(store.registerPlay(on: date(3), calendar: calendar) == 3)
    }

    @Test("Saltarse un día reinicia la racha")
    func gapResetsStreak() {
        let store = makeStore()
        store.registerPlay(on: date(1), calendar: calendar)
        store.registerPlay(on: date(2), calendar: calendar)
        #expect(store.registerPlay(on: date(4), calendar: calendar) == 1)
    }

    /// La racha se mide por día natural, no por 24 h: jugar a las 23:50 y a las
    /// 00:10 son dos días, que es lo que el jugador espera ver.
    @Test("Dos partidas separadas por 20 minutos cruzando medianoche cuentan como dos días")
    func midnightCrossingCountsAsTwoDays() {
        let store = makeStore()
        store.registerPlay(on: date(1, hour: 23), calendar: calendar)
        #expect(store.registerPlay(on: date(2, hour: 0), calendar: calendar) == 2)
    }

    // MARK: Cartera

    @Test("No se puede gastar más cobre del que hay")
    func cannotOverspend() {
        let store = makeStore()
        store.merge(summary: summary(copper: 30), stats: [:], confusions: [:],
                    seededStats: [:], seededConfusions: [:])
        #expect(store.spend(copper: 50) == false)
        #expect(store.copper == 30)
        #expect(store.spend(copper: 30) == true)
        #expect(store.copper == 0)
    }

    @Test("Un modo libre suma cobre y estadísticas pero no desbloquea nada")
    func freeModesDoNotUnlock() {
        let store = makeStore()
        var scheduler = DrillScheduler(alphabet: ["E", "T"])
        for _ in 0..<8 { scheduler.record(shown: "E", answered: "E", responseTime: 1) }
        store.merge(summary: summary(levelID: 0, mastered: false, copper: 14, mode: .timeAttack),
                    stats: scheduler.stats, confusions: [:],
                    seededStats: [:], seededConfusions: [:])

        #expect(store.copper == 14)
        #expect(store.highestUnlockedLevel == 1)
        #expect(record(store, symbol: "E")?.attempts == 8)
    }

    @Test("Las letras flojas se ordenan por precisión y exigen muestra mínima")
    func weakestLettersRanking() {
        let store = makeStore()
        var scheduler = DrillScheduler(alphabet: ["E", "T", "A"])
        for index in 0..<10 {
            scheduler.record(shown: "E", answered: "E", responseTime: 1)
            scheduler.record(shown: "T", answered: index < 3 ? "T" : "E", responseTime: 1)
        }
        scheduler.record(shown: "A", answered: "E", responseTime: 1)   // 1 intento: poca muestra
        store.merge(summary: summary(), stats: scheduler.stats, confusions: scheduler.confusions,
                    seededStats: [:], seededConfusions: [:])

        let weakest = store.weakestLetters()
        #expect(weakest.first?.symbol == "T")
        #expect(!weakest.contains { $0.symbol == "A" })   // menos de 5 intentos
    }
}
