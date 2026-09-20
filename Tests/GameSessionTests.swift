import Foundation
import Testing
@testable import MorseTrainer

@Suite("Modos de juego")
struct GameSessionTests {

    private var alphabet: [Character] { Array("ETANIMSO") }

    @Test("Un nivel de campaña es una sesión con límite, corazones y progreso")
    func levelSessionShape() {
        let level = LevelPlan.levels[6]
        let session = GameSession.level(level)
        #expect(session.mode == .level)
        #expect(session.level?.id == level.id)
        #expect(session.itemLimit == level.drillCount)
        #expect(session.hearts == level.hearts)
        #expect(session.persists)
        #expect(!session.isEndless)
        #expect(!session.speedRamp)
    }

    @Test("La práctica libre no termina ni castiga")
    func practiceShape() {
        let session = GameSession.practice(alphabet: alphabet, timing: .comfortable)
        #expect(session.hearts == nil)
        #expect(session.itemLimit == nil)
        #expect(session.timeLimit == nil)
        #expect(session.isEndless)
        // Sigue alimentando al motor adaptativo: si no, practicar no serviría
        // de nada para la campaña y sería un modo de relleno.
        #expect(session.persists)
    }

    @Test("La contrarreloj dura un minuto y no tiene corazones")
    func timeAttackShape() {
        let session = GameSession.timeAttack(alphabet: alphabet, timing: .comfortable)
        #expect(session.timeLimit == 60)
        #expect(session.hearts == nil)
        #expect(!session.isEndless)
        // Casi todo recepción: tecleando no da tiempo a suficientes letras.
        #expect(session.mix.receptionShare > 0.8)
    }

    @Test("La supervivencia tiene corazones, no acaba y acelera")
    func survivalShape() {
        let session = GameSession.survival(alphabet: alphabet, timing: .comfortable)
        #expect(session.hearts == 3)
        #expect(session.isEndless)
        #expect(session.speedRamp)
    }

    @Test("Ningún modo libre enseña caracteres nuevos")
    func freeModesTeachNothing() {
        for session in [GameSession.practice(alphabet: alphabet, timing: .comfortable),
                        .timeAttack(alphabet: alphabet, timing: .comfortable),
                        .survival(alphabet: alphabet, timing: .comfortable)] {
            #expect(session.newCharacters.isEmpty)
            #expect(session.level == nil)
        }
    }

    // MARK: Rampa de velocidad

    @Test("La rampa sube la velocidad efectiva sin pasar de la de carácter")
    func rampKeepsFarnsworthValid() {
        let session = GameSession.survival(alphabet: alphabet,
                                           timing: FarnsworthTiming(characterWPM: 20, effectiveWPM: 10))
        var timing = session.timing
        for _ in 0..<40 {
            timing = session.ramped(from: timing)
            #expect(timing.effectiveWPM <= timing.characterWPM)
            // Los silencios no pueden encogerse por debajo del mínimo legal.
            #expect(timing.interCharacterGap >= 3 * timing.ditDuration - 1e-9)
            #expect(timing.interWordGap >= 7 * timing.ditDuration - 1e-9)
        }
    }

    @Test("La rampa siempre acelera")
    func rampIsMonotonic() {
        let session = GameSession.survival(alphabet: alphabet, timing: .level1)
        var timing = session.timing
        for _ in 0..<10 {
            let next = session.ramped(from: timing)
            #expect(next.effectiveWPM > timing.effectiveWPM)
            timing = next
        }
    }

    @Test("La rampa tiene techo: no acelera hasta el infinito")
    func rampIsCapped() {
        let session = GameSession.survival(alphabet: alphabet, timing: .comfortable)
        var timing = session.timing
        for _ in 0..<200 { timing = session.ramped(from: timing) }
        #expect(timing.effectiveWPM <= 40)
        #expect(timing.characterWPM <= 40)
    }

    // MARK: Alfabeto y velocidad de arranque

    @Test("Los modos libres usan el alfabeto ya desbloqueado")
    func unlockedAlphabetMatchesLevel() {
        #expect(GameSession.unlockedAlphabet(upTo: 1) == LevelPlan.levels[0].activeAlphabet)
        #expect(GameSession.unlockedAlphabet(upTo: 7) == LevelPlan.levels[6].activeAlphabet)
    }

    @Test("Un nivel fuera de rango no rompe el alfabeto ni la velocidad")
    func outOfRangeLevelIsClamped() {
        let last = LevelPlan.levels.count
        #expect(GameSession.unlockedAlphabet(upTo: 9999) == LevelPlan.levels[last - 1].activeAlphabet)
        #expect(GameSession.unlockedAlphabet(upTo: -5) == LevelPlan.levels[0].activeAlphabet)
        #expect(GameSession.startingTiming(forUnlockedLevel: 9999).characterWPM > 0)
    }
}

@Suite("Ajustes")
@MainActor
struct GameSettingsTests {

    private func settings() -> GameSettings {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return GameSettings(defaults: suite)
    }

    @Test("Por defecto suenan audio y háptica, la linterna no")
    func defaults() {
        let sut = settings()
        #expect(sut.audioEnabled)
        #expect(sut.hapticsEnabled)
        #expect(!sut.torchEnabled)
        #expect(sut.toneFrequency == 600)
    }

    @Test("Los canales reflejan los interruptores")
    func channelsFollowToggles() {
        let sut = settings()
        #expect(sut.channels.contains(.audio))
        #expect(sut.channels.contains(.haptics))
        #expect(!sut.channels.contains(.torch))

        sut.audioEnabled = false
        sut.torchEnabled = true
        #expect(!sut.channels.contains(.audio))
        #expect(sut.channels.contains(.torch))
    }

    /// Un ajuste no debería poder dejar la app en un estado del que no se sale
    /// jugando. La interfaz avisa; el modelo lo hace comprobable.
    @Test("Apagarlo todo se detecta como estado sin salida")
    func noChannelsIsDetectable() {
        let sut = settings()
        sut.audioEnabled = false
        sut.hapticsEnabled = false
        sut.torchEnabled = false
        #expect(!sut.hasAnyChannel)
    }

    @Test("Las preferencias sobreviven a recrear el objeto")
    func settingsPersist() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let first = GameSettings(defaults: suite)
        first.toneFrequency = 800
        first.hapticsEnabled = false

        let second = GameSettings(defaults: suite)
        #expect(second.toneFrequency == 800)
        #expect(!second.hapticsEnabled)
    }

    @Test("Todas las frecuencias ofrecidas son audibles y distintas")
    func toneChoicesAreSane() {
        #expect(GameSettings.toneChoices.allSatisfy { $0 >= 300 && $0 <= 1200 })
        #expect(Set(GameSettings.toneChoices).count == GameSettings.toneChoices.count)
        #expect(GameSettings.toneChoices.contains(600))
    }
}
