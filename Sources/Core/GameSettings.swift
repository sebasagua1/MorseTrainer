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

    private let defaults: UserDefaults

    /// Tonos habituales en radioafición. 600 Hz es el estándar de facto; los
    /// extremos ayudan a quien tiene pérdida auditiva en ciertas frecuencias.
    static let toneChoices: [Double] = [440, 500, 600, 700, 800]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        audioEnabled = defaults.object(forKey: "audioEnabled") as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        torchEnabled = defaults.object(forKey: "torchEnabled") as? Bool ?? false
        toneFrequency = defaults.object(forKey: "toneFrequency") as? Double ?? 600
        revealPatternOnError = defaults.object(forKey: "revealPatternOnError") as? Bool ?? false
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
