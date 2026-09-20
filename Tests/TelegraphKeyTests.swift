import Foundation
import Testing
@testable import MorseTrainer

/// Doble de pruebas: el manipulador real arranca Core Haptics y AVAudioEngine.
@MainActor
final class SilentFeedback: TelegraphFeedbackProviding {
    private(set) var downs = 0
    private(set) var ups = 0
    func keyDown() { downs += 1 }
    func dahArmed() {}
    func keyUp() { ups += 1 }
}

@Suite("Manipulador telegráfico", .serialized)
@MainActor
struct TelegraphKeyTests {

    private func key(for level: Level) -> TelegraphKeyViewModel {
        TelegraphKeyViewModel(timing: level.timing, feedback: SilentFeedback())
    }

    private var oLevel: Level {
        LevelPlan.levels.first { $0.newCharacters.contains("O") }!
    }

    // MARK: Punto y raya

    @Test("Un toque corto es punto y uno largo es raya")
    func shortIsDitLongIsDah() async throws {
        let sut = key(for: LevelPlan.levels[0])
        var symbols: [MorseSymbol] = []
        sut.onSymbol = { symbols.append($0) }

        sut.keyDown()
        try await Task.sleep(for: .milliseconds(60))
        sut.keyUp()

        sut.keyDown()
        try await Task.sleep(for: .milliseconds(400))
        sut.keyUp()

        #expect(symbols == [.dit, .dah])
    }

    // MARK: Bug del nivel de la O

    /// Regresión: el hueco de cierre era de 654 ms en el nivel de la O. Teclear
    /// tres rayas dudando entre ellas —lo normal al aprender la letra— cerraba
    /// el carácter a mitad y lo contaba como T. El jugador perdía un corazón
    /// por haberlo hecho bien.
    @Test("La O se puede teclear con vacilación entre rayas")
    func canKeyOWithHesitation() async throws {
        let sut = key(for: oLevel)
        var decoded: [Character?] = []
        sut.onCharacter = { _, character in decoded.append(character) }

        for _ in 0..<3 {
            sut.keyDown()
            try await Task.sleep(for: .milliseconds(320))   // raya
            sut.keyUp()
            try await Task.sleep(for: .milliseconds(700))   // duda humana
        }
        try await Task.sleep(for: .seconds(1.4))            // deja que cierre

        #expect(decoded == ["O"], "Se decodificó \(decoded) en vez de O")
    }

    @Test("El margen de cierre es generoso en todos los niveles")
    func letterGapIsForgivingEverywhere() {
        for level in LevelPlan.levels {
            let sut = key(for: level)
            #expect(sut.letterGap >= 0.9,
                    "Nivel \(level.id): margen de \(Int(sut.letterGap * 1000)) ms")
        }
    }

    @Test("Una pausa larga sí cierra el carácter")
    func longPauseStillCommits() async throws {
        let sut = key(for: LevelPlan.levels[0])
        var decoded: [Character?] = []
        sut.onCharacter = { _, character in decoded.append(character) }

        sut.keyDown()
        try await Task.sleep(for: .milliseconds(60))
        sut.keyUp()
        try await Task.sleep(for: .seconds(2.0))

        #expect(decoded == ["E"])
    }

    @Test("Teclear de nuevo cancela el cierre pendiente")
    func keyingAgainCancelsCommit() async throws {
        let sut = key(for: LevelPlan.levels[0])
        var decoded: [Character?] = []
        sut.onCharacter = { _, character in decoded.append(character) }

        sut.keyDown(); try await Task.sleep(for: .milliseconds(60)); sut.keyUp()
        try await Task.sleep(for: .milliseconds(300))
        #expect(decoded.isEmpty, "Cerró antes de tiempo")

        sut.keyDown(); try await Task.sleep(for: .milliseconds(60)); sut.keyUp()
        try await Task.sleep(for: .seconds(1.6))
        #expect(decoded == ["I"])
    }

    @Test("flush cierra el carácter al instante")
    func flushCommitsImmediately() async throws {
        let sut = key(for: LevelPlan.levels[0])
        var decoded: [Character?] = []
        sut.onCharacter = { _, character in decoded.append(character) }

        sut.keyDown(); try await Task.sleep(for: .milliseconds(400)); sut.keyUp()
        sut.flush()
        #expect(decoded == ["T"])
    }

    @Test("reset descarta lo tecleado sin emitir carácter")
    func resetDiscardsBuffer() async throws {
        let sut = key(for: LevelPlan.levels[0])
        var decoded: [Character?] = []
        sut.onCharacter = { _, character in decoded.append(character) }

        sut.keyDown(); try await Task.sleep(for: .milliseconds(60)); sut.keyUp()
        sut.reset()
        try await Task.sleep(for: .seconds(1.4))
        #expect(decoded.isEmpty)
        #expect(sut.buffer.isEmpty)
    }
}

@Suite("Retroalimentación visual")
struct CarrierIndicatorTests {

    /// Regresión: el destello se animaba en 80 ms, pero el hueco entre los
    /// elementos de un carácter son 60 ms a 20 WPM y 48 ms a 25. La animación
    /// no llegaba a apagarse, así que las tres rayas de la O se veían como un
    /// único destello largo, idéntico a una T. Quien juega en silencio o con la
    /// linterna no podía distinguirlas.
    @Test("El destello no dura más que el hueco más corto entre elementos")
    func flashFitsInsideTightestGap() {
        let tightest = LevelPlan.levels.map(\.timing.intraCharacterGap).min()!
        #expect(CarrierIndicator.flashDuration < tightest,
                "destello \(CarrierIndicator.flashDuration * 1000) ms vs hueco \(tightest * 1000) ms")
    }
}
