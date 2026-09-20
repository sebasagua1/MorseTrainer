import SwiftUI

// MARK: - Corazones

struct HeartsBar: View {
    let remaining: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            // Array(0..<total): un Range dinámico en ForEach provoca avisos de
            // identidad inestable cuando `total` cambia entre niveles.
            ForEach(Array(0..<total), id: \.self) { index in
                Image(systemName: index < remaining ? "heart.fill" : "heart")
                    .foregroundStyle(index < remaining ? Color.red : Color.secondary.opacity(0.4))
                    .symbolEffect(.bounce, value: remaining)
            }
        }
        .font(.system(size: 17, weight: .semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(remaining) de \(total) corazones")
    }
}

// MARK: - Barra de progreso

struct LessonProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(
                        LinearGradient(colors: [.accentColor.opacity(0.7), .accentColor],
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

// MARK: - Veredicto

struct JudgeBanner: View {
    let correct: Bool
    let target: Character
    let answer: Character?
    let pattern: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(correct ? Color.green : Color.red)
                .symbolEffect(.bounce, value: correct)

            VStack(alignment: .leading, spacing: 2) {
                Text(correct ? "¡Correcto!" : "Era \(String(target))")
                    .font(.headline)
                // El patrón se revela *después* de responder: enseñarlo antes
                // convierte el ejercicio en lectura, no en escucha.
                Text(pattern)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(4)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill((correct ? Color.green : Color.red).opacity(0.14))
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Indicador de portadora

/// Destello sincronizado con la transmisión. Es la pista visual para jugar en
/// silencio y el sustituto en pantalla de la linterna.
struct CarrierIndicator: View {
    let isKeyed: Bool
    let isPlaying: Bool

    var body: some View {
        Circle()
            .fill(isKeyed ? Color.accentColor : Color.secondary.opacity(0.18))
            .frame(width: 96, height: 96)
            .overlay(
                Circle().stroke(Color.accentColor.opacity(isKeyed ? 0.45 : 0), lineWidth: 14)
                    .scaleEffect(isKeyed ? 1.45 : 1)
            )
            .shadow(color: .accentColor.opacity(isKeyed ? 0.6 : 0), radius: 26)
            // Sin animación en el encendido: el destello debe caer justo con el
            // audio. Animarlo introduciría un retardo perceptible de ~100 ms.
            .animation(.easeOut(duration: 0.08), value: isKeyed)
            .opacity(isPlaying ? 1 : 0.5)
            .accessibilityHidden(true)
    }
}
