import SwiftUI

// MARK: - Corazones

struct HeartsBar: View {
    let remaining: Int
    let total: Int

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            // Array(0..<total): un Range dinámico en ForEach provoca avisos de
            // identidad inestable cuando `total` cambia entre niveles.
            ForEach(Array(0..<total), id: \.self) { index in
                Image(systemName: index < remaining ? "heart.fill" : "heart")
                    .foregroundStyle(index < remaining ? palette.danger : palette.border)
                    .symbolEffect(.bounce, value: remaining)
            }
        }
        .font(.rounded(.headline, .semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(remaining) de \(total) corazones")
    }
}

// MARK: - Barra de progreso

struct LessonProgressBar: View {
    let progress: Double

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.signalOff)
                Capsule()
                    .fill(
                        LinearGradient(colors: [palette.accent.opacity(0.65), palette.accent],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(0, geometry.size.width * progress))
            }
        }
        .frame(height: 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
        .accessibilityLabel("Progreso del nivel")
        .accessibilityValue("\(Int(progress * 100)) por ciento")
    }
}

// MARK: - Screen shake

/// Desplazamiento horizontal amortiguado. `animatableData` recibe el contador
/// de fallos del VM, así que cada incremento dispara una sacudida completa.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    var amplitude: CGFloat = 9
    var shakes: CGFloat = 3

    func effectValue(size: CGSize) -> ProjectionTransform {
        let decay = 1 - min(1, abs(animatableData.truncatingRemainder(dividingBy: 1)))
        let offset = sin(animatableData * .pi * 2 * shakes) * amplitude * decay
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

extension View {
    /// Respeta "Reducir movimiento": ahí el error se comunica solo con color,
    /// borde y háptica, nunca con desplazamiento.
    func shake(on trigger: Int, reduceMotion: Bool) -> some View {
        modifier(ShakeModifier(trigger: trigger, reduceMotion: reduceMotion))
    }
}

private struct ShakeModifier: ViewModifier {
    let trigger: Int
    let reduceMotion: Bool
    @State private var amount: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(animatableData: amount))
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                amount = CGFloat(trigger) - 1
                withAnimation(.easeOut(duration: 0.45)) { amount = CGFloat(trigger) }
            }
    }
}

// MARK: - Cuenta atrás

struct CountdownBadge: View {
    let secondsRemaining: TimeInterval

    private var isUrgent: Bool { secondsRemaining <= 10 }

    @Environment(\.palette) private var palette

    var body: some View {
        Text(String(format: "%d:%02d",
                    Int(secondsRemaining) / 60,
                    Int(secondsRemaining.rounded(.up)) % 60))
            .font(.headline.monospacedDigit())
            // El color no viaja solo: en los últimos diez segundos el texto
            // también engorda, para quien no distingue el rojo.
            .fontWeight(isUrgent ? .heavy : .semibold)
            .foregroundStyle(isUrgent ? palette.danger : palette.textPrimary)
            .accessibilityLabel("\(Int(secondsRemaining)) segundos restantes")
    }
}

// MARK: - Veredicto

struct JudgeBanner: View {
    let correct: Bool
    let target: Character
    let answer: Character?
    let pattern: String

    @Environment(\.palette) private var palette

    private var tint: Color { correct ? palette.success : palette.danger }

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.rounded(.title, .bold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: correct)

            VStack(alignment: .leading, spacing: Space.sm) {
                Text(correct ? "¡Correcto!" : "Era \(String(target))")
                    .font(.rounded(.headline, .bold))
                    .foregroundStyle(palette.textPrimary)
                // El patrón se revela *después* de responder: enseñarlo antes
                // convierte el ejercicio en lectura, no en escucha. Dibujado y
                // no escrito, porque el ritmo se ve de un vistazo y ".-" no.
                if let code = MorseCode(pattern: pattern) {
                    MorseGlyph(code: code, unit: 7, tint: tint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
                )
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Indicador de portadora

/// Destello sincronizado con la transmisión. Es la pista visual para jugar en
/// silencio y el sustituto en pantalla de la linterna.
struct CarrierIndicator: View {
    /// Duración de la transición encendido/apagado del destello: ninguna.
    ///
    /// Tiene que ser cero, no "rápida". El hueco entre los elementos de un
    /// carácter es de una unidad —60 ms a 20 WPM, 48 ms a 25— y cualquier
    /// animación más larga que eso no llega a apagarse: las tres rayas de la O
    /// se funden en un único destello indistinguible de una T. Quien juega en
    /// silencio o con la linterna se queda sin poder leer la letra.
    ///
    /// Todo lo *decorativo* de aquí abajo (halo, anillos, sombra) puede ser
    /// bonito porque no anima nada: cambia de golpe junto con la portadora.
    static let flashDuration: TimeInterval = 0

    let isKeyed: Bool
    let isPlaying: Bool

    @Environment(\.palette) private var palette

    private let core: CGFloat = 148

    var body: some View {
        ZStack {
            // Halo. Solo existe con la portadora encendida y da la sensación de
            // que el disco *emite*, en vez de cambiar de color.
            Circle()
                .fill(
                    RadialGradient(colors: [palette.signalOn.opacity(0.45), .clear],
                                   center: .center,
                                   startRadius: core * 0.45,
                                   endRadius: core * 1.15)
                )
                .frame(width: core * 2.3, height: core * 2.3)
                .opacity(isKeyed ? 1 : 0)

            // Anillo de reposo. En modo oscuro el disco apagado sobre negro
            // era invisible: sin este borde no se sabía dónde mirar.
            Circle()
                .strokeBorder(palette.border, lineWidth: 2)
                .frame(width: core * 1.42, height: core * 1.42)

            Circle()
                .strokeBorder(isKeyed ? palette.signalOn.opacity(0.55) : .clear, lineWidth: 10)
                .frame(width: core * 1.42, height: core * 1.42)

            // Disco.
            Circle()
                .fill(isKeyed ? palette.signalOn : palette.signalOff)
                .frame(width: core, height: core)
                .overlay(
                    // Luz superior: le da volumen sin recurrir a una imagen.
                    Circle()
                        .fill(
                            LinearGradient(colors: [.white.opacity(isKeyed ? 0.35 : 0.10), .clear],
                                           startPoint: .top, endPoint: .center)
                        )
                )
                .shadow(color: palette.signalOn.opacity(isKeyed ? 0.55 : 0), radius: 30)
        }
        // Sin animación en el encendido: el destello debe caer justo con el
        // audio. Animarlo introduciría un retardo perceptible de ~100 ms.
        .animation(nil, value: isKeyed)
        .opacity(isPlaying ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.25), value: isPlaying)
        .accessibilityHidden(true)
    }
}
