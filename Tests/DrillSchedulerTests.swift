import Foundation
import Testing
@testable import MorseTrainer

@Suite("Programador adaptativo")
struct DrillSchedulerTests {

    private func scheduler(_ alphabet: [Character] = ["E", "T", "A"],
                           new: [Character] = []) -> DrillScheduler {
        DrillScheduler(alphabet: alphabet, newCharacters: new)
    }

    @Test("Un carácter fallado pesa más que uno acertado")
    func failureRaisesWeight() {
        var sut = scheduler()
        for _ in 0..<5 { sut.record(shown: "E", answered: "E", responseTime: 1) }
        for _ in 0..<5 { sut.record(shown: "T", answered: "E", responseTime: 1) }
        #expect(sut.weight(for: "T") > sut.weight(for: "E"))
    }

    @Test("La confusión arrastra a las dos letras del par")
    func confusionPullsBothSides() {
        var clean = scheduler(["S", "H", "O"])
        var confused = scheduler(["S", "H", "O"])
        // Misma precisión en ambos, pero en uno los fallos son S↔H.
        for _ in 0..<4 {
            clean.record(shown: "S", answered: "O", responseTime: 1)
            confused.record(shown: "S", answered: "H", responseTime: 1)
        }
        // La H no ha fallado nunca por sí misma en ninguno de los dos.
        #expect(confused.weight(for: "H") > clean.weight(for: "H"))
    }

    @Test("Un carácter dominado casi desaparece de la cola")
    func masteredCharacterFades() {
        var sut = scheduler()
        for _ in 0..<10 { sut.record(shown: "E", answered: "E", responseTime: 1) }
        // Sigue presente: el repaso de fondo evita el olvido.
        #expect(sut.weight(for: "E") > 0)
        #expect(sut.weight(for: "E") < sut.weight(for: "A"))
    }

    @Test("El carácter recién introducido recibe empuje")
    func noveltyBoost() {
        let withNovelty = scheduler(["E", "T", "A"], new: ["A"])
        let without = scheduler(["E", "T", "A"])
        #expect(withNovelty.weight(for: "A") > without.weight(for: "A"))
    }

    @Test("Lo que acaba de salir se penaliza")
    func recencyPenalty() {
        var sut = scheduler()
        let before = sut.weight(for: "E")
        sut.record(shown: "E", answered: "E", responseTime: 1)
        // Tras acertarlo su peso baja por dos vías, pero la recencia debe
        // dejarlo por debajo de un carácter con el mismo historial y sin salir.
        #expect(sut.weight(for: "E") < before)
    }

    @Test("El muestreo solo devuelve caracteres del alfabeto activo")
    func samplingStaysInAlphabet() {
        let sut = scheduler(["E", "T", "A", "N"])
        let allowed: Set<Character> = ["E", "T", "A", "N"]
        for _ in 0..<200 { #expect(allowed.contains(sut.nextCharacter())) }
    }

    @Test("El muestreo cubre todo el alfabeto a la larga")
    func samplingIsNotDegenerate() {
        let sut = scheduler(["E", "T", "A", "N"])
        var seen: Set<Character> = []
        for _ in 0..<500 { seen.insert(sut.nextCharacter()) }
        #expect(seen.count == 4)
    }

    // MARK: Dominio

    private var rule: MasteryRule {
        MasteryRule(rollingWindow: 10, requiredAccuracy: 0.9,
                    minCorrectPerNewCharacter: 3, medianResponseTime: 5)
    }

    @Test("No se domina sin llenar la ventana móvil")
    func masteryNeedsFullWindow() {
        var sut = scheduler(["E", "T"], new: ["E"])
        for _ in 0..<5 { sut.record(shown: "E", answered: "E", responseTime: 1) }
        #expect(!sut.hasMastered(rule, rollingResults: Array(repeating: true, count: 5)))
    }

    @Test("No se domina por debajo de la precisión exigida")
    func masteryNeedsAccuracy() {
        var sut = scheduler(["E", "T"], new: ["E"])
        for _ in 0..<5 { sut.record(shown: "E", answered: "E", responseTime: 1) }
        let results = Array(repeating: true, count: 8) + [false, false]  // 80 %
        #expect(!sut.hasMastered(rule, rollingResults: results))
    }

    @Test("Se domina con ventana llena, precisión y aciertos del carácter nuevo")
    func masterySucceeds() {
        var sut = scheduler(["E", "T"], new: ["E"])
        for _ in 0..<3 { sut.record(shown: "E", answered: "E", responseTime: 1) }
        #expect(sut.hasMastered(rule, rollingResults: Array(repeating: true, count: 10)))
    }

    /// Regresión: sembrar el historial desde disco NO debe aprobar el requisito
    /// de aciertos del carácter nuevo. Antes de separar `sessionCorrect` del
    /// acumulado, este test pasaba en verde sin haber respondido nada.
    @Test("El historial sembrado no aprueba el nivel por el jugador")
    func seededHistoryDoesNotGrantMastery() {
        var seeded = CharacterStat(character: "E")
        seeded.attempts = 12
        seeded.correct = 12

        var sut = DrillScheduler(alphabet: ["E", "T"],
                                 newCharacters: ["E"],
                                 seededStats: ["E": seeded])

        // Ventana llena y perfecta, pero ni una sola respuesta de E hoy.
        #expect(!sut.hasMastered(rule, rollingResults: Array(repeating: true, count: 10)))

        // Con los aciertos de hoy, sí.
        for _ in 0..<3 { sut.record(shown: "E", answered: "E", responseTime: 1) }
        #expect(sut.hasMastered(rule, rollingResults: Array(repeating: true, count: 10)))
    }

    @Test("La siembra sí influye en el peso inicial")
    func seedingAffectsWeights() {
        var weak = CharacterStat(character: "T")
        weak.attempts = 10
        weak.correct = 3

        let sut = DrillScheduler(alphabet: ["E", "T"],
                                 seededStats: ["T": weak])
        #expect(sut.weight(for: "T") > sut.weight(for: "E"))
    }

    @Test("Las confusiones sembradas se conservan")
    func seededConfusionsSurvive() {
        let pair = ConfusionPair(shown: "S", answered: "H")
        let sut = DrillScheduler(alphabet: ["S", "H"], seededConfusions: [pair: 2])
        #expect(sut.confusions[pair] == 2)
        #expect(sut.topConfusions().first?.0 == pair)
    }

    @Test("Los pares confundidos se ordenan por frecuencia")
    func topConfusionsAreRanked() {
        var sut = scheduler(["E", "T", "A"])
        for _ in 0..<3 { sut.record(shown: "E", answered: "T", responseTime: 1) }
        sut.record(shown: "A", answered: "T", responseTime: 1)
        let top = sut.topConfusions()
        #expect(top.first?.0 == ConfusionPair(shown: "E", answered: "T"))
        #expect(top.first?.1 == 3)
    }

    @Test("Una respuesta vacía cuenta como fallo pero no crea par de confusión")
    func nilAnswerIsAFailureWithoutPair() {
        var sut = scheduler()
        sut.record(shown: "E", answered: nil, responseTime: 1)
        #expect(sut.stats["E"]?.attempts == 1)
        #expect(sut.stats["E"]?.correct == 0)
        #expect(sut.confusions.isEmpty)
    }
}
