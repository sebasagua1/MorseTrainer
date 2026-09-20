import Foundation
import CoreHaptics
import AVFoundation
import UIKit

@MainActor
protocol TelegraphFeedbackProviding: AnyObject {
    func keyDown()
    /// El toque ya cuenta como raya: micro-impacto que lo confirma sin mirar.
    func dahArmed()
    func keyUp()
}

// MARK: - Sidetone (oscilador senoidal)

/// Estado del render en tiempo real. Vive en su propia clase para poder
/// capturarse en el bloque de `AVAudioSourceNode` antes de terminar el `init`.
private final class ToneState: @unchecked Sendable {
    var phase: Double = 0
    var gain: Double = 0
    var targetGain: Double = 0
    var frequency: Double = 600      // Hz; el banco de sonidos lo cambia
    var rampCoefficient: Double = 0  // se calcula con el sample rate
}

/// Tono continuo con envolvente suavizada. La rampa de ~4 ms evita el "clic"
/// de conmutación, que a 20 WPM se oiría en cada punto.
final class Sidetone {
    private let engine = AVAudioEngine()
    private let state = ToneState()
    private var isRunning = false

    var frequency: Double {
        get { state.frequency }
        set { state.frequency = newValue }
    }

    init() {
        // `mainMixerNode` (y no `outputNode`) da un formato válido ya al
        // construir el grafo; leer el del outputNode aquí puede devolver 0 Hz.
        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000
        state.rampCoefficient = 1 - exp(-1.0 / (0.004 * sampleRate))

        let toneState = state
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let increment = 2 * Double.pi * toneState.frequency / sampleRate
            for frame in 0..<Int(frameCount) {
                toneState.gain += (toneState.targetGain - toneState.gain) * toneState.rampCoefficient
                let sample = Float(sin(toneState.phase) * toneState.gain * 0.25)
                toneState.phase += increment
                if toneState.phase > 2 * .pi { toneState.phase -= 2 * .pi }
                for buffer in buffers {
                    let pointer = UnsafeMutableBufferPointer<Float>(buffer)
                    pointer[frame] = sample
                }
            }
            return noErr
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate,
                                   channels: 1,
                                   interleaved: false)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    func prepare() {
        guard !isRunning else { return }
        // .playback ignora el interruptor de silencio (el jugador espera oír
        // el Morse). Expón un ajuste para respetarlo si el usuario lo prefiere.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
        isRunning = engine.isRunning
    }

    func start() { prepare(); state.targetGain = 1 }
    func stop() { state.targetGain = 0 }
}

// MARK: - Implementación real

@MainActor
final class TelegraphFeedback: TelegraphFeedbackProviding {

    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticPatternPlayer?
    private let fallbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let tickGenerator = UISelectionFeedbackGenerator()
    private let sidetone = Sidetone()

    var isAudioEnabled = true
    var isHapticsEnabled = true
    var toneFrequency: Double {
        get { sidetone.frequency }
        set { sidetone.frequency = newValue }
    }

    init() {
        prepareHaptics()
        sidetone.prepare()
        fallbackGenerator.prepare()
        tickGenerator.prepare()
    }

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in
            try? self?.engine?.start()
            self?.continuousPlayer = nil
        }
        try? engine?.start()

        // Vibración sostenida de hasta 3 s: la arrancamos en el key-down y la
        // paramos en el key-up, así el punto y la raya se *sienten* distintos
        // en lugar de ser dos impactos idénticos.
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.75)
            ],
            relativeTime: 0,
            duration: 3.0
        )
        if let pattern = try? CHHapticPattern(events: [event], parameters: []) {
            continuousPlayer = try? engine?.makePlayer(with: pattern)
        }
    }

    // MARK: TelegraphFeedbackProviding

    func keyDown() {
        if isAudioEnabled { sidetone.start() }
        guard isHapticsEnabled else { return }
        if let player = continuousPlayer {
            try? engine?.start()
            try? player.start(atTime: CHHapticTimeImmediate)
        } else {
            fallbackGenerator.impactOccurred(intensity: 0.8)
        }
    }

    func dahArmed() {
        guard isHapticsEnabled else { return }
        tickGenerator.selectionChanged()
    }

    func keyUp() {
        sidetone.stop()
        try? continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
    }
}

// MARK: - Linterna (accesibilidad / juego en silencio)

/// Reproduce una línea de tiempo Morse con el flash de la cámara.
/// Úsalo también como pista visual para jugadores con pérdida auditiva.
@MainActor
final class TorchTransmitter {
    private var task: Task<Void, Never>?

    func play(_ events: [MorseEvent]) {
        cancel()
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        task = Task {
            for event in events {
                if Task.isCancelled { break }
                setTorch(device, on: event.isOn)
                try? await Task.sleep(for: .seconds(event.duration))
            }
            setTorch(device, on: false)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
            setTorch(device, on: false)
        }
    }

    private func setTorch(_ device: AVCaptureDevice, on: Bool) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}
