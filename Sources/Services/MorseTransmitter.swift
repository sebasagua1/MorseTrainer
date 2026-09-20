import Foundation
import AVFoundation
import CoreHaptics
import Combine
import UIKit

/// Canales de salida activos. El jugador los combina en Ajustes:
/// audio solo, háptica sola, linterna sola, o los tres a la vez.
struct TransmissionChannels: OptionSet, Sendable {
    let rawValue: Int
    static let audio   = TransmissionChannels(rawValue: 1 << 0)
    static let haptics = TransmissionChannels(rawValue: 1 << 1)
    static let torch   = TransmissionChannels(rawValue: 1 << 2)
    static let all: TransmissionChannels = [.audio, .haptics, .torch]
    static let `default`: TransmissionChannels = [.audio, .haptics]
}

/// Reproduce una línea de tiempo Morse por audio, Taptic Engine y linterna
/// **a la vez y desde la misma fuente**.
///
/// Estrategia de sincronía, por canal:
/// - Audio:   búfer PCM pre-renderizado, exactitud de muestra.
/// - Háptica: un único `CHHapticPattern` con todos los eventos colocados en su
///            `relativeTime`. Lo programa Core Haptics, no nuestro planificador:
///            así no hay deriva acumulada entre el tono y la vibración.
/// - Linterna: bucle con *deadlines* absolutos. El flash tarda ~5 ms en
///            responder; a esa escala no se nota, y no vale la pena más.
/// - UI:      el mismo bucle de deadlines publica el elemento en curso.
@MainActor
final class MorseTransmitter: ObservableObject {

    @Published private(set) var isPlaying = false
    /// Portadora encendida: la vista lo usa para el destello en pantalla.
    @Published private(set) var isKeyed = false
    /// Índice del elemento que suena ahora, para resaltar el patrón en vivo.
    @Published private(set) var currentSymbolIndex: Int?

    var channels: TransmissionChannels = .default
    var toneFrequency: Double = 600
    var soundBank: SoundBank = .sine

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var hapticEngine: CHHapticEngine?
    private let torch = TorchTransmitter()
    private let fallbackHaptics = UIImpactFeedbackGenerator(style: .rigid)

    private var playbackTask: Task<Void, Never>?
    private var isEngineReady = false
    /// Formato en el que se renderiza y se reproduce. Mono a propósito: el
    /// sidetone Morse no tiene nada que panoramizar, y el mixer se encarga de
    /// subirlo a los canales que tenga la salida.
    private var renderFormat: AVAudioFormat?

    init() {
        engine.attach(player)
        configureHaptics()
    }

    // MARK: - Configuración

    /// Conecta el reproductor con un formato **explícito**. Usar el formato del
    /// `outputNode` era un error doble: en el simulador es estéreo, y
    /// `scheduleBuffer` exige que el búfer tenga los mismos canales que el nodo
    /// (assert fatal de AVFAudio, no un error recuperable). Además se leía en
    /// `init`, antes de activar la sesión, así que el sample rate podía quedar
    /// obsoleto. Ahora se fija después de activar la sesión y se usa el mismo
    /// para renderizar: nunca pueden divergir.
    private func configureAudioIfNeeded() {
        guard renderFormat == nil else { return }
        // Tocar `mainMixerNode` lo materializa y da un formato de salida válido.
        let hardwareRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : 48_000
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate,
                                   channels: 1,
                                   interleaved: false)
        renderFormat = format
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    private func configureHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        hapticEngine = try? CHHapticEngine()
        hapticEngine?.isAutoShutdownEnabled = true
        hapticEngine?.resetHandler = { [weak self] in try? self?.hapticEngine?.start() }
    }

    /// Llamar al entrar en la lección: arrancar motores cuesta ~50 ms y no
    /// queremos pagarlos en el primer prompt.
    func prepare() {
        guard !isEngineReady else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        configureAudioIfNeeded()
        try? engine.start()
        try? hapticEngine?.start()
        fallbackHaptics.prepare()
        isEngineReady = engine.isRunning
    }

    // MARK: - Reproducción

    @discardableResult
    func play(text: String, timing: FarnsworthTiming) async -> Bool {
        await play(events: timing.timeline(for: text))
    }

    @discardableResult
    func play(code: MorseCode, timing: FarnsworthTiming) async -> Bool {
        await play(events: timing.timeline(for: code))
    }

    /// Devuelve `true` si la transmisión terminó entera, `false` si se canceló.
    @discardableResult
    func play(events: [MorseEvent]) async -> Bool {
        cancel()
        guard !events.isEmpty else { return true }
        prepare()

        isPlaying = true
        defer { isPlaying = false; isKeyed = false; currentSymbolIndex = nil }

        if channels.contains(.audio) { startAudio(events) }
        if channels.contains(.haptics) { startHaptics(events) }
        if channels.contains(.torch) { torch.play(events) }

        let task = Task { await runTimeline(events) }
        playbackTask = task
        await task.value
        return !task.isCancelled
    }

    func cancel() {
        playbackTask?.cancel()
        playbackTask = nil
        player.stop()
        torch.cancel()
        isKeyed = false
        currentSymbolIndex = nil
    }

    // MARK: - Canales

    private func startAudio(_ events: [MorseEvent]) {
        guard let renderFormat,
              let buffer = MorseWaveformRenderer.render(events: events,
                                                        sampleRate: renderFormat.sampleRate,
                                                        bank: soundBank,
                                                        frequency: toneFrequency),
              // Cinturón además de tirantes: si alguna vez divergen, se salta
              // el audio en lugar de abortar el proceso.
              buffer.format.channelCount == renderFormat.channelCount
        else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func startHaptics(_ events: [MorseEvent]) {
        guard let hapticEngine else {
            // Sin Core Haptics (iPhone SE 1ª gen, iPad): el bucle de la línea de
            // tiempo dará un impacto por elemento. Peor, pero no silencioso.
            return
        }
        var hapticEvents: [CHHapticEvent] = []
        var time: TimeInterval = 0
        for event in events {
            if event.isOn {
                // La raya baja algo la nitidez: se percibe como un zumbido
                // sostenido frente al golpe seco del punto.
                let sharpness: Float = event.symbol == .dit ? 0.85 : 0.55
                hapticEvents.append(
                    CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [
                                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                                  ],
                                  relativeTime: time,
                                  duration: event.duration)
                )
            }
            time += event.duration
        }
        guard !hapticEvents.isEmpty,
              let pattern = try? CHHapticPattern(events: hapticEvents, parameters: []),
              let patternPlayer = try? hapticEngine.makePlayer(with: pattern)
        else { return }
        try? hapticEngine.start()
        try? patternPlayer.start(atTime: CHHapticTimeImmediate)
    }

    /// Bucle maestro con *deadlines absolutos*. Dormir `event.duration` en cada
    /// vuelta acumularía el retraso del planificador elemento a elemento; con
    /// deadlines calculados desde un origen fijo el error nunca se suma.
    private func runTimeline(_ events: [MorseEvent]) async {
        let clock = ContinuousClock()
        let origin = clock.now
        var elapsed: Duration = .zero
        var symbolIndex = 0
        let useFallbackHaptics = channels.contains(.haptics) && hapticEngine == nil

        for event in events {
            guard !Task.isCancelled else { return }
            isKeyed = event.isOn
            if event.isOn {
                currentSymbolIndex = symbolIndex
                symbolIndex += 1
                if useFallbackHaptics {
                    fallbackHaptics.impactOccurred(intensity: event.symbol == .dit ? 0.7 : 1.0)
                }
            }
            elapsed += .seconds(event.duration)
            try? await Task.sleep(until: origin + elapsed, clock: clock)
        }
        isKeyed = false
        currentSymbolIndex = nil
    }
}
