import Foundation

enum DrillKind: Equatable, Sendable {
    /// Suena el Morse, el jugador elige la letra.
    case reception
    /// Se ve la letra, el jugador la manipula con el telégrafo.
    case transmission
    /// Palabra completa transmitida carácter a carácter.
    case word
}

struct Drill: Identifiable, Equatable, Sendable {
    let id = UUID()
    let kind: DrillKind
    let prompt: String
    /// Teclado dinámico: solo se usa en recepción.
    let options: [Character]

    var targetCharacter: Character? { kind == .word ? nil : prompt.first }
}

struct WeakSpot: Equatable, Sendable {
    let pair: ConfusionPair
    let count: Int
}

struct LessonSummary: Equatable, Sendable {
    let mode: GameSession.Mode
    /// Nivel de campaña; 0 en los modos libres, que no desbloquean nada.
    let levelID: Int
    let itemsCorrect: Int
    let itemsTotal: Int
    /// Velocidad efectiva alcanzada. Solo cambia en supervivencia.
    let topEffectiveWPM: Double
    let accuracy: Double
    let heartsRemaining: Int
    let copperEarned: Int
    let mastered: Bool
    let medianResponseTime: TimeInterval
    let weakSpots: [WeakSpot]
    /// Por qué no se superó el nivel. Sin esto, quien acertaba casi todo veía
    /// «Otra pasada» sin saber qué le pedían y lo tomaba por un fallo de la app.
    var shortfall: MasteryShortfall? = nil
}

/// El primer requisito de dominio que no se cumplió.
enum MasteryShortfall: Equatable, Sendable {
    case incomplete
    case accuracy(achieved: Double, required: Double, window: Int)
    case newCharacter(Character, correct: Int, required: Int)
    case speed(median: TimeInterval, required: TimeInterval)

    var message: String {
        switch self {
        case .incomplete:
            return "La partida terminó antes de poder medir el nivel."
        case let .accuracy(achieved, required, window):
            return "En los últimos \(window) ejercicios acertaste el \(Int((achieved * 100).rounded(.down)))%. "
                + "Hace falta el \(Int((required * 100).rounded()))%."
        case let .newCharacter(character, correct, required):
            return "Te faltan aciertos de la \(String(character)): llevas \(correct) de \(required)."
        case let .speed(median, required):
            // Con un decimal, 1,93 frente a 1,92 se leería «1,9 s… hace falta 1,9 s».
            var digits = 1
            if Self.seconds(median, digits) == Self.seconds(required, digits) { digits = 2 }
            return "Acertaste, pero te faltó rapidez al escuchar: tardas \(Self.seconds(median, digits)) "
                + "en responder y hace falta \(Self.seconds(required, digits))."
        }
    }

    private static func seconds(_ value: TimeInterval, _ digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits))) + " s"
    }
}

enum LessonPhase: Equatable, Sendable {
    case idle
    /// Se está transmitiendo el prompt: el teclado está bloqueado.
    case presenting
    case awaitingAnswer
    /// Veredicto visible durante ~0.6 s antes del siguiente ítem.
    case judging(correct: Bool)
    case completed(LessonSummary)
    case outOfHearts
}
