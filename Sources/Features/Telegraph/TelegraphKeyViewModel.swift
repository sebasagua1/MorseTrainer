import Foundation
import QuartzCore

/// Motor de entrada del manipulador (telégrafo).
///
/// Por qué `DragGesture(minimumDistance: 0)` y no `onLongPressGesture`:
/// `onLongPressGesture` dispara **una vez** al cruzar el umbral y no entrega el
/// instante de soltado, así que no puedes medir la duración real de la pulsación
/// ni distinguir "raya corta" de "raya larga". `DragGesture` con distancia 0 da
/// `onChanged` en el key-down y `onEnded` en el key-up: dos timestamps limpios.
@MainActor
final class TelegraphKeyViewModel: ObservableObject {

    // MARK: Estado publicado

    @Published private(set) var buffer: [MorseSymbol] = []
    @Published private(set) var isDown = false
    /// El toque ya lleva suficiente tiempo como para contar como raya.
    /// La vista lo usa para cambiar el glifo del botón en vivo (`·` → `−`).
    @Published private(set) var willBeDah = false
    /// Hay un carácter en el buffer esperando a cerrarse. La vista dibuja la
    /// cuenta atrás para que el jugador vea que aún puede seguir tecleando.
    @Published private(set) var isAwaitingCommit = false

    // MARK: Callbacks

    /// Cada punto/raya confirmado (para partículas + háptica).
    var onSymbol: ((MorseSymbol) -> Void)?
    /// Un carácter cerrado por silencio: el patrón y la letra decodificada (si existe).
    var onCharacter: ((MorseCode, Character?) -> Void)?

    // MARK: Configuración

    var timing: FarnsworthTiming
    /// Silencio que cierra un carácter.
    ///
    /// No se deriva de la velocidad del nivel. Eso daba 654 ms en el nivel de
    /// la O, y quien acaba de aprender una letra de tres rayas duda más que eso
    /// entre una y otra: el carácter se cerraba a mitad, se contaba como T y
    /// costaba un corazón por haberlo hecho bien.
    ///
    /// Se calcula sobre el pulso del propio jugador —`ditDahThreshold` ya está
    /// calibrado con sus puntos— con un suelo generoso. La contrapartida es que
    /// la letra tarda en confirmarse, así que la tecla lo muestra con un anillo
    /// que se vacía: el tiempo de espera deja de ser invisible.
    var letterGap: TimeInterval { letterGapOverride ?? max(0.9, 4 * ditDahThreshold) }

    // MARK: Costuras para pruebas
    //
    // El manipulador mide el tiempo real, que es justo lo que hay que probar y
    // justo lo que no se puede reproducir en un runner cargado: un `sleep` de
    // 60 ms puede tardar 200 y convertir un punto en una raya. Estas dos
    // costuras dejan fijar la duración de la pulsación y el margen de cierre
    // sin depender de la precisión del planificador.

    /// Reloj monótono. Sustituible para simular pulsaciones de duración exacta.
    var now: () -> CFTimeInterval = { CACurrentMediaTime() }
    /// Margen de cierre fijo. `nil` usa el calculado sobre el pulso del jugador.
    var letterGapOverride: TimeInterval?
    /// Seguro anti-bloqueo: si el gesto se cancela (llamada entrante, notificación)
    /// `onEnded` puede no llegar nunca. Pasado este tiempo cerramos como raya.
    private let watchdogTimeout: TimeInterval = 2.0

    // MARK: Umbral adaptativo punto/raya

    /// Arranca en 2 unidades a la velocidad del nivel, acotado a algo pulsable
    /// con el pulgar. Se recalibra con la mediana de los puntos recientes.
    private(set) var ditDahThreshold: TimeInterval
    private var recentDits: [TimeInterval] = []
    private let thresholdRange: ClosedRange<TimeInterval> = 0.09...0.45

    // MARK: Internos

    private let feedback: TelegraphFeedbackProviding
    private var pressStart: CFTimeInterval = 0
    private var dahArmTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var letterCommitTask: Task<Void, Never>?

    // Los argumentos por defecto se evalúan fuera del actor, así que un
    // `= TelegraphFeedback()` aquí rompería el aislamiento de MainActor.
    init(timing: FarnsworthTiming = .level1,
         feedback: TelegraphFeedbackProviding? = nil) {
        self.timing = timing
        self.feedback = feedback ?? TelegraphFeedback()
        self.ditDahThreshold = min(max(2 * timing.ditDuration, 0.16), 0.30)
    }

    // MARK: - Ciclo de la tecla

    func keyDown() {
        guard !isDown else { return }          // `onChanged` se repite: idempotente.
        isDown = true
        willBeDah = false
        isAwaitingCommit = false
        letterCommitTask?.cancel()
        letterCommitTask = nil

        pressStart = now()
        feedback.keyDown()                      // háptica continua + sidetone

        dahArmTask = Task { [threshold = ditDahThreshold] in
            try? await Task.sleep(for: .seconds(threshold))
            guard !Task.isCancelled else { return }
            self.willBeDah = true
            self.feedback.dahArmed()            // "clic" que confirma que ya es raya
        }
        watchdogTask = Task { [watchdogTimeout] in
            try? await Task.sleep(for: .seconds(watchdogTimeout))
            guard !Task.isCancelled else { return }
            self.keyUp()
        }
    }

    func keyUp() {
        guard isDown else { return }
        isDown = false
        willBeDah = false
        dahArmTask?.cancel(); dahArmTask = nil
        watchdogTask?.cancel(); watchdogTask = nil

        let held = now() - pressStart
        feedback.keyUp()

        let symbol: MorseSymbol = held < ditDahThreshold ? .dit : .dah
        if symbol == .dit { calibrate(withDit: held) }

        buffer.append(symbol)
        onSymbol?(symbol)
        scheduleLetterCommit()
    }

    /// Fuerza el cierre del carácter (botón "enviar" o fin de ronda).
    func flush() {
        letterCommitTask?.cancel()
        letterCommitTask = nil
        commitCharacter()
    }

    /// Aplica las preferencias del jugador al manipulador.
    func apply(_ settings: GameSettings) {
        feedback.isAudioEnabled = settings.audioEnabled
        feedback.isHapticsEnabled = settings.hapticsEnabled
        feedback.toneFrequency = settings.toneFrequency
    }

    func reset() {
        dahArmTask?.cancel(); watchdogTask?.cancel(); letterCommitTask?.cancel()
        dahArmTask = nil; watchdogTask = nil; letterCommitTask = nil
        buffer.removeAll()
        isDown = false
        willBeDah = false
        isAwaitingCommit = false
        feedback.keyUp()
    }

    /// Llamar desde `.onChange(of: scenePhase)` y `.onDisappear`.
    func releaseIfNeeded() { if isDown { keyUp() } }

    // MARK: - Privado

    private func scheduleLetterCommit() {
        isAwaitingCommit = true
        letterCommitTask = Task { [letterGap] in
            try? await Task.sleep(for: .seconds(letterGap))
            guard !Task.isCancelled else { return }
            self.commitCharacter()
        }
    }

    private func commitCharacter() {
        isAwaitingCommit = false
        guard !buffer.isEmpty else { return }
        let code = MorseCode(buffer)
        buffer.removeAll()
        onCharacter?(code, MorseAlphabet.character(for: code))
    }

    /// El umbral persigue la mano del jugador: mediana de los últimos puntos × 2.
    /// Solo aprende de los puntos, porque las rayas las alarga tanto el jugador
    /// que contaminarían la estimación de la unidad base.
    private func calibrate(withDit duration: TimeInterval) {
        recentDits.append(duration)
        if recentDits.count > 8 { recentDits.removeFirst() }
        guard recentDits.count >= 4 else { return }
        let median = recentDits.sorted()[recentDits.count / 2]
        let target = median * 2
        // Suavizado: nunca saltamos más de un 20 % de golpe.
        let blended = ditDahThreshold * 0.8 + target * 0.2
        ditDahThreshold = min(max(blended, thresholdRange.lowerBound), thresholdRange.upperBound)
    }
}
