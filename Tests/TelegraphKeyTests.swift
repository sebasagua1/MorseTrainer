import Foundation
import Testing
@testable import MorseTrainer

/// Doble de pruebas: el manipulador real arranca Core Haptics y AVAudioEngine.
@MainActor
final class SilentFeedback: TelegraphFeedbackProviding {
    var isAudioEnabled = true
    var isHapticsEnabled = true
    var toneFrequency: Double = 600
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

    /// Manipulador con reloj simulado: la duración de cada pulsación se fija
    /// exactamente, sin depender de lo puntual que sea `Task.sleep`.
    private func fakeClockKey(for level: Level,
                              gap: TimeInterval) -> (TelegraphKeyViewModel, Clock) {
        let clock = Clock()
        let sut = TelegraphKeyViewModel(timing: level.timing, feedback: SilentFeedback())
        sut.now = { clock.value }
        sut.letterGapOverride = gap
        return (sut, clock)
    }

    final class Clock {
        var value: CFTimeInterval = 0
        func advance(_ seconds: TimeInterval) { value += seconds }
    }

    /// Pulsa durante `duration` de tiempo *simulado*, sin gastar tiempo real.
    private func press(_ sut: TelegraphKeyViewModel, _ clock: Clock, for duration: TimeInterval) {
        sut.keyDown()
        clock.advance(duration)
        sut.keyUp()
    }

    private var oLevel: Level {
        LevelPlan.levels.first { $0.newCharacters.contains("O") }!
    }

    // MARK: Punto y raya

    @Test("Un toque corto es punto y uno largo es raya")
    func shortIsDitLongIsDah() {
        let (sut, clock) = fakeClockKey(for: LevelPlan.levels[0], gap: 5)
        var symbols: [MorseSymbol] = []
        sut.onSymbol = { symbols.append($0) }

        press(sut, clock, for: 0.06)
        press(sut, clock, for: 0.40)

        #expect(symbols == [.dit, .dah])
    }

    @Test("El umbral punto/raya cae donde dice estar")
    func thresholdBoundary() {
        let level = LevelPlan.levels[0]
        let (sut, clock) = fakeClockKey(for: level, gap: 5)
        let threshold = sut.ditDahThreshold
        var symbols: [MorseSymbol] = []
        sut.onSymbol = { symbols.append($0) }

        press(sut, clock, for: threshold - 0.01)
        press(sut, clock, for: threshold + 0.01)

        #expect(symbols == [.dit, .dah])
    }

    // MARK: Bug del nivel de la O

    /// Regresión: el hueco de cierre era de 654 ms en el nivel de la O. Teclear
    /// tres rayas dudando entre ellas —lo normal al aprender la letra— cerraba
    /// el carácter a mitad y lo contaba como T. El jugador perdía un corazón
    /// por haberlo hecho bien.
    @Test("La O se puede teclear con vacilación entre rayas")
    func canKeyOWithHesitation() async throws {
        // Margen de cierre amplio y pausas reales cortas: así la prueba mide la
        // lógica —que una pausa menor que el margen no cierra el carácter— sin
        // que un runner lento la vuelva inestable. Que el margen real sea de
        // verdad generoso lo comprueba `letterGapIsForgivingEverywhere`.
        let (sut, clock) = fakeClockKey(for: oLevel, gap: 1.2)
        var decoded: [Character?] = []
        sut.onCharacter = { _, character in decoded.append(character) }

        for _ in 0..<3 {
            press(sut, clock, for: 0.32)                    // raya
            try await Task.sleep(for: .milliseconds(150))   // duda
        }
        #expect(decoded.isEmpty, "Cerró el carácter a mitad")

        try await Task.sleep(for: .seconds(1.8))            // deja que cierre
        #expect(decoded == ["O"], "Se decodificó \(decoded) en vez de O")
    }

    /// El margen que de verdad usa el juego tiene que dejar pasar la duda de
    /// quien acaba de aprender una letra de tres elementos. Antes eran 654 ms
    /// en el nivel de la O y una pausa de 700 la partía en tres T.
    @Test("Una duda de 700 ms cabe dentro del margen real")
    func realGapAbsorbsHumanHesitation() {
        let sut = key(for: oLevel)
        #expect(sut.letterGap > 0.7)
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
        sut.letterGapOverride = 0.3
        var decoded: [Character?] = []
        sut.onCharacter = { _, character in decoded.append(character) }

        sut.keyDown()
        sut.keyUp()
        try await Task.sleep(for: .seconds(1.6))

        #expect(decoded == ["E"])
    }

    @Test("Teclear de nuevo cancela el cierre pendiente")
    func keyingAgainCancelsCommit() async throws {
        let (sut, clock) = fakeClockKey(for: LevelPlan.levels[0], gap: 1.2)
        var decoded: [Character?] = []
        sut.onCharacter = { _, character in decoded.append(character) }

        press(sut, clock, for: 0.05)
        try await Task.sleep(for: .milliseconds(200))
        #expect(decoded.isEmpty, "Cerró antes de tiempo")

        press(sut, clock, for: 0.05)
        try await Task.sleep(for: .seconds(1.8))
        #expect(decoded == ["I"])
    }

    @Test("flush cierra el carácter al instante")
    func flushCommitsImmediately() async throws {
        let sut = key(for: LevelPlan.levels[0])
        var decoded: [Character?] = []
        sut.onCharacter = { _, character in decoded.append(character) }

        let clock = Clock()
        sut.now = { clock.value }
        press(sut, clock, for: 0.40)
        sut.flush()
        #expect(decoded == ["T"])
    }

    @Test("reset descarta lo tecleado sin emitir carácter")
    func resetDiscardsBuffer() async throws {
        let sut = key(for: LevelPlan.levels[0])
        var decoded: [Character?] = []
        sut.onCharacter = { _, character in decoded.append(character) }

        sut.keyDown(); sut.keyUp()
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
