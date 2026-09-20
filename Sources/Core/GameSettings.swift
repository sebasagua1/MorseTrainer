import Foundation
import Combine

/// Preferencias del jugador. Vive aparte de `PersistenceStore` porque no es
/// progreso: son ajustes del dispositivo, y perderlos al reinstalar no duele.
///
/// Los canales de salida son accesibilidad, no adorno: quien no oye juega con
/// linterna y háptica, y quien no puede sentir el Taptic Engine necesita el
/// tono. Sin una pantalla que los controle, la app solo sirve a quien puede
/// usar los tres.
@MainActor
final class GameSettings: ObservableObject {

    @Published var audioEnabled: Bool { didSet { save(audioEnabled, "audioEnabled") } }
    @Published var hapticsEnabled: Bool { didSet { save(hapticsEnabled, "hapticsEnabled") } }
    @Published var torchEnabled: Bool { didSet { save(torchEnabled, "torchEnabled") } }
    @Published var toneFrequency: Double { didSet { save(toneFrequency, "toneFrequency") } }
    /// Muestra el patrón en pantalla al fallar, para quien aprende con apoyo
    /// visual. Apagado por defecto: leer el patrón no es oírlo.
    @Published var revealPatternOnError: Bool { didSet { save(revealPatternOnError, "revealPatternOnError") } }
    /// Si ya se vio la introducción. Va aquí y no en el progreso: reinstalar la
    /// app y volver a ver la explicación es razonable; perder el progreso no.
    @Published var hasSeenOnboarding: Bool { didSet { save(hasSeenOnboarding, "hasSeenOnboarding") } }

    private let defaults: UserDefaults

    /// 0 significa "la que traiga el banco de sonido". El resto son tonos
    /// habituales en radioafición: los extremos ayudan a quien tiene pérdida
    /// auditiva en ciertas frecuencias, y por eso el ajuste manda sobre el
    /// cosmético. Un cosmético no puede dejarte sin oír el juego.
    static let toneChoices: [Double] = [0, 440, 500, 600, 700, 800]

    /// Frecuencia efectiva: la elegida a mano, o la del banco si es automática.
    func frequency(for bank: SoundBank) -> Double {
        toneFrequency > 0 ? toneFrequency : bank.frequency
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        audioEnabled = defaults.object(forKey: "audioEnabled") as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        torchEnabled = defaults.object(forKey: "torchEnabled") as? Bool ?? false
        toneFrequency = defaults.object(forKey: "toneFrequency") as? Double ?? 0
        revealPatternOnError = defaults.object(forKey: "revealPatternOnError") as? Bool ?? false
        hasSeenOnboarding = defaults.object(forKey: "hasSeenOnboarding") as? Bool ?? false
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    var channels: TransmissionChannels {
        var channels: TransmissionChannels = []
        if audioEnabled { channels.insert(.audio) }
        if hapticsEnabled { channels.insert(.haptics) }
        if torchEnabled { channels.insert(.torch) }
        return channels
    }

    /// Apagar los tres canales deja el juego sin forma de transmitir nada. La
    /// interfaz lo impide, pero el modelo también: un ajuste no debería poder
    /// dejar la app en un estado del que no se puede salir jugando.
    var hasAnyChannel: Bool { !channels.isEmpty }
}
