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
