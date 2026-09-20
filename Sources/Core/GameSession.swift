import Foundation

/// Descripción de una partida. El bucle de juego es el mismo para todos los
/// modos —presentar, juzgar, avanzar—; lo que cambia es qué la termina, si hay
/// corazones, si la velocidad sube y si el resultado cuenta para el progreso.
///
/// Un nivel de la campaña es una sesión más, no un caso especial: así el motor
/// adaptativo y la persistencia funcionan igual en todos los modos sin ramas.
struct GameSession: Identifiable {

    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case level
        case practice
        case timeAttack
        case survival

        var id: String { rawValue }

        var title: String {
            switch self {
            case .level:      return "Campaña"
            case .practice:   return "Práctica libre"
            case .timeAttack: return "Contrarreloj"
            case .survival:   return "Supervivencia"
            }
        }

        var tagline: String {
            switch self {
            case .level:      return "Aprende letras nuevas una a una"
            case .practice:   return "Sin corazones ni prisa. Repasa lo que quieras"
            case .timeAttack: return "60 segundos. Tantas letras como puedas"
            case .survival:   return "La velocidad sube. Aguanta lo que puedas"
            }
        }

        var symbol: String {
            switch self {
            case .level:      return "map"
            case .practice:   return "infinity"
            case .timeAttack: return "timer"
            case .survival:   return "flame"
            }
        }

        /// Modos que se juegan sobre el alfabeto ya desbloqueado, sin enseñar
        /// nada nuevo. Son los que aparecen en el menú aparte de la campaña.
        static var freeModes: [Mode] { [.practice, .timeAttack, .survival] }
    }

    let id = UUID()
    let mode: Mode
    /// Solo en `.level`: el nivel de la campaña que se está jugando.
    let level: Level?
    let title: String
    let alphabet: [Character]
    let newCharacters: [Character]
    var timing: FarnsworthTiming
    let mix: DrillMix
    /// `nil` = sin corazones: fallar no termina la partida.
    let hearts: Int?
    /// `nil` = sin límite de ítems.
    let itemLimit: Int?
    /// `nil` = sin límite de tiempo.
    let timeLimit: TimeInterval?
    /// La velocidad efectiva sube cada pocos aciertos.
    let speedRamp: Bool
    /// El resultado se funde con el histórico del jugador.
    let persists: Bool

    var isEndless: Bool { itemLimit == nil && timeLimit == nil }

    // MARK: Constructores

    static func level(_ level: Level) -> GameSession {
        GameSession(
            mode: .level,
            level: level,
            title: level.title,
            alphabet: level.activeAlphabet,
            newCharacters: level.newCharacters,
            timing: level.timing,
            mix: level.mix,
            hearts: level.hearts,
            itemLimit: level.drillCount,
            timeLimit: nil,
            speedRamp: false,
            persists: true
        )
    }

    /// Repaso sin presión: ni corazones ni final. Se sale cuando se quiere.
    /// Sigue alimentando el motor adaptativo, que es lo que la hace útil y no
    /// un modo de relleno: practicar aquí cambia lo que sale en la campaña.
    static func practice(alphabet: [Character], timing: FarnsworthTiming) -> GameSession {
        GameSession(
            mode: .practice,
            level: nil,
            title: Mode.practice.title,
            alphabet: alphabet,
            newCharacters: [],
            timing: timing,
            mix: DrillMix(receptionShare: 0.5, wordRounds: 0),
            hearts: nil,
            itemLimit: nil,
            timeLimit: nil,
            speedRamp: false,
            persists: true
        )
    }

    /// Un minuto. Sin corazones —fallar cuesta tiempo, no vidas— y recepción
    /// casi entera: tecleando no da tiempo a suficientes letras para medir.
    static func timeAttack(alphabet: [Character], timing: FarnsworthTiming) -> GameSession {
        GameSession(
            mode: .timeAttack,
            level: nil,
            title: Mode.timeAttack.title,
            alphabet: alphabet,
            newCharacters: [],
            timing: timing,
            mix: DrillMix(receptionShare: 0.85, wordRounds: 0),
            hearts: nil,
            itemLimit: nil,
            timeLimit: 60,
            speedRamp: false,
            persists: true
        )
    }

    /// Tres corazones y la velocidad subiendo hasta que se acaban. Es el modo
    /// que enseña dónde está tu techo real, que la campaña nunca te muestra
    /// porque se detiene en cuanto dominas el nivel.
    static func survival(alphabet: [Character], timing: FarnsworthTiming) -> GameSession {
        GameSession(
            mode: .survival,
            level: nil,
            title: Mode.survival.title,
            alphabet: alphabet,
            newCharacters: [],
            timing: timing,
            mix: DrillMix(receptionShare: 0.7, wordRounds: 0),
            hearts: 3,
            itemLimit: nil,
            timeLimit: nil,
            speedRamp: true,
            persists: true
        )
    }

    /// Velocidad de arranque para los modos libres: la del último nivel
    /// desbloqueado, para que no sorprenda ni aburra.
    static func startingTiming(forUnlockedLevel id: Int) -> FarnsworthTiming {
        LevelPlan.level(id: max(1, min(id, LevelPlan.levels.count)))?.timing ?? .level1
    }

    /// Alfabeto disponible en los modos libres: todo lo enseñado hasta ahora.
    static func unlockedAlphabet(upTo levelID: Int) -> [Character] {
        let clamped = max(1, min(levelID, LevelPlan.levels.count))
        return LevelPlan.level(id: clamped)?.activeAlphabet ?? ["E", "T"]
    }

    // MARK: Subida de velocidad (supervivencia)

    /// Cada cuántos aciertos seguidos sube la velocidad efectiva.
    static let rampInterval = 5
    /// Cuánto sube, en WPM efectivos.
    static let rampStep: Double = 1

    /// Siguiente escalón de velocidad. La de carácter también sube, más
    /// despacio, para que el Farnsworth no se quede sin holgura y acabe
    /// pidiendo silencios más cortos que los propios elementos.
    func ramped(from current: FarnsworthTiming) -> FarnsworthTiming {
        let effective = current.effectiveWPM + Self.rampStep
        let character = max(current.characterWPM, effective)
        return FarnsworthTiming(characterWPM: min(40, character),
                                effectiveWPM: min(40, effective))
    }
}
