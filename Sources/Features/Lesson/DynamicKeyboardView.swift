import SwiftUI

/// Teclado de respuesta en los ejercicios de recepción.
///
/// "Dinámico" en dos sentidos: las opciones las elige `LessonViewModel` según
/// las confusiones reales del jugador, y el número de columnas se adapta a
/// cuántas hay, para que las teclas nunca bajen del objetivo táctil de 44 pt.
struct DynamicKeyboardView: View {
    let options: [Character]
    let isEnabled: Bool
    /// Durante el veredicto: la correcta se pinta verde y la fallada, roja.
    let revealedTarget: Character?
    let chosenAnswer: Character?
    let onSelect: (Character) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: [GridItem] {
        let count = options.count <= 4 ? min(options.count, 2) : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: max(1, count))
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(options, id: \.self) { character in
                KeyCap(character: character,
                       state: state(for: character),
                       reduceMotion: reduceMotion) {
                    onSelect(character)
                }
                .disabled(!isEnabled)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: options)
    }

    private func state(for character: Character) -> KeyCap.State {
        guard let revealedTarget else { return .idle }
        if character == revealedTarget { return .correct }
        if character == chosenAnswer { return .wrong }
        return .dimmed
    }
}

// MARK: - Tecla

struct KeyCap: View {
    enum State { case idle, correct, wrong, dimmed }

    let character: Character
    let state: State
    let reduceMotion: Bool
    let action: () -> Void

    @SwiftUI.State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(String(character))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .foregroundStyle(foreground)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(background)
                        .shadow(color: .black.opacity(isPressed ? 0.06 : 0.18),
                                radius: isPressed ? 2 : 8, y: isPressed ? 1 : 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(border, lineWidth: 2)
                )
                .scaleEffect(isPressed && !reduceMotion ? 0.95 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isPressed)
        .animation(.easeOut(duration: 0.2), value: state)
        .accessibilityLabel("Letra \(String(character))")
    }

    // El estado nunca viaja solo en el color: la correcta y la fallada llevan
    // además borde propio, para daltonismo y para "Aumentar contraste".
    private var background: Color {
        switch state {
        case .idle:    return Color(.secondarySystemBackground)
        case .correct: return .green.opacity(0.22)
        case .wrong:   return .red.opacity(0.22)
        case .dimmed:  return Color(.secondarySystemBackground).opacity(0.5)
        }
    }

    private var border: Color {
        switch state {
        case .idle:    return .clear
        case .correct: return .green
        case .wrong:   return .red
        case .dimmed:  return .clear
        }
    }

    private var foreground: Color {
        switch state {
        case .idle:    return .primary
        case .correct: return .green
        case .wrong:   return .red
        case .dimmed:  return .secondary
        }
    }
}
