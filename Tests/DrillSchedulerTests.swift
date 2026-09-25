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

    /// Regresión: el empuje al carácter nuevo dependía de los intentos
    /// *históricos*. Al reintentar un nivel el nuevo llegaba sembrado, perdía
    /// el empuje, el resto del alfabeto (con sus confusiones acumuladas) se
    /// llevaba el sorteo y el requisito de aciertos no se cumplía nunca.
    @Test("Un jugador que acierta todo aprueba aunque reintente con historial cargado")
    func newCharacterGetsEnoughExposureOnRetry() {
        let alphabet = Array("ETANIMSOURCDKGWHBLPJ")
        let newCharacter: Character = "J"
        var stats: [Character: CharacterStat] = [:]
        for character in alphabet {
            var stat = CharacterStat(character: character)
            stat.attempts = 12
            stat.correct = 12
            stats[character] = stat
        }
        // Confusiones saturadas en todo el alfabeto viejo: el peor caso.
        var confusions: [ConfusionPair: Int] = [:]
        for (shown, answered) in zip(alphabet, alphabet.dropFirst()) where shown != newCharacter {
            confusions[ConfusionPair(shown: shown, answered: answered)] = 3
        }
        let rule = MasteryRule(rollingWindow: 24, requiredAccuracy: 0.9,
                               minCorrectPerNewCharacter: 6, medianResponseTime: 2)
        let slots = 26

        for _ in 0..<200 {
            var sut = DrillScheduler(alphabet: alphabet, newCharacters: [newCharacter],
                                     newCharacterTarget: rule.minCorrectPerNewCharacter,
                                     seededStats: stats, seededConfusions: confusions)
            for item in 0..<slots {
                let character = sut.nextCharacter(slotsLeft: slots - item)
                sut.record(shown: character, answered: character, responseTime: 1)
            }
            #expect(sut.shortfall(for: rule, rollingResults: Array(repeating: true, count: slots)) == nil)
        }
    }

    @Test("Sin margen para el sorteo, sale el carácter nuevo")
    func newCharacterIsForcedWhenSlotsRunOut() {
        let sut = DrillScheduler(alphabet: ["E", "T", "A"], newCharacters: ["A"],
                                 newCharacterTarget: 2)
        for _ in 0..<50 { #expect(sut.nextCharacter(slotsLeft: 2) == "A") }
    }

    @Test("El carácter nuevo no acapara el sorteo cuando ya cumplió")
    func newCharacterFadesAfterTarget() {
        var sut = DrillScheduler(alphabet: ["E", "T", "A"], newCharacters: ["A"],
                                 newCharacterTarget: 2)
        let before = sut.weight(for: "A")
        for _ in 0..<2 { sut.record(shown: "A", answered: "A", responseTime: 1) }
        #expect(!sut.needsExposure("A"))
        #expect(sut.weight(for: "A") < before)
    }

    @Test("El resumen dice qué faltó para aprobar")
    func shortfallExplainsFailure() {
        var sut = scheduler(["E", "T"], new: ["E"])
        sut.record(shown: "E", answered: "E", responseTime: 1)
        let perfect = Array(repeating: true, count: 10)
        #expect(sut.shortfall(for: rule, rollingResults: perfect)
                == .newCharacter("E", correct: 1, required: 3))

        let sloppy = Array(repeating: true, count: 8) + [false, false]
        guard case .accuracy(let achieved, _, _) = sut.shortfall(for: rule, rollingResults: sloppy) else {
            Issue.record("se esperaba falta de precisión"); return
        }
        #expect(abs(achieved - 0.8) < 0.001)
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
