import Foundation
import AVFoundation

/// Renderiza una línea de tiempo Morse completa a un búfer PCM.
///
/// Por qué pre-renderizar en lugar de encender/apagar el oscilador con tareas:
/// el manipulador del jugador tiene duración desconocida (ahí sí hace falta un
/// oscilador en vivo, `Sidetone`), pero un prompt de recepción se conoce entero
/// de antemano. Renderizarlo da precisión de *muestra* — a 20 WPM un punto dura
/// 60 ms y una desviación de 10 ms del planificador ya deforma el ritmo, que es
/// justo lo que el jugador debe aprender a reconocer.
enum MorseWaveformRenderer {

    static func render(events: [MorseEvent],
                       sampleRate: Double,
                       frequency: Double = 600,
                       amplitude: Float = 0.25,
                       rampDuration: Double = 0.005) -> AVAudioPCMBuffer? {

        let totalDuration = events.reduce(0) { $0 + $1.duration }
        guard totalDuration > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1,
                                         interleaved: false)
        else { return nil }

        let frameCount = AVAudioFrameCount((totalDuration * sampleRate).rounded(.up))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount

        let increment = 2 * Double.pi * frequency / sampleRate
        let nominalRamp = max(1, Int(rampDuration * sampleRate))
        var phase: Double = 0          // fase continua: no hay saltos entre elementos
        var cursor = 0

        for event in events {
            let length = Int((event.duration * sampleRate).rounded())
            guard length > 0 else { continue }
            // A velocidades altas un punto puede ser más corto que dos rampas.
            let rampFrames = max(1, min(nominalRamp, length / 2))

            for frame in 0..<length {
                guard cursor < Int(frameCount) else { break }
                var envelope: Double = event.isOn ? 1 : 0
                if event.isOn {
                    // Rampa coseno elevado en ambos flancos: sin ella cada punto
                    // suena con un "clic" de conmutación muy audible a 20 WPM.
                    if frame < rampFrames {
                        envelope = 0.5 * (1 - cos(.pi * Double(frame) / Double(rampFrames)))
                    } else if frame > length - rampFrames {
                        let remaining = max(0, length - frame)
                        envelope = 0.5 * (1 - cos(.pi * Double(remaining) / Double(rampFrames)))
                    }
                    channel[cursor] = Float(sin(phase) * envelope) * amplitude
                    phase += increment
                    if phase > 2 * .pi { phase -= 2 * .pi }
                } else {
                    channel[cursor] = 0
                }
                cursor += 1
            }
        }

        return buffer
    }
}
