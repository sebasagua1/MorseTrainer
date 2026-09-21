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
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.sm) {
                Text(String(character))
                    .displayFont(32, .bold, relativeTo: .title)

                // Tras el veredicto la tecla enseña su ritmo. Es el momento en
                // que el patrón ya no estorba —la respuesta está dada— y verlo
                // junto a la letra es lo que cierra el aprendizaje.
                if state != .idle, let code = MorseAlphabet.code(for: character) {
                    MorseGlyph(code: code, unit: 5, tint: foreground)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
            .padding(.vertical, Space.sm)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(background)
                    .shadow(color: .black.opacity(isPressed ? 0.05 : 0.14),
                            radius: isPressed ? 2 : 10, y: isPressed ? 1 : 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(border, lineWidth: state == .idle ? 1.5 : 2.5)
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
        case .idle:    return palette.surfaceRaised
        case .correct: return palette.success.opacity(0.18)
        case .wrong:   return palette.danger.opacity(0.18)
        case .dimmed:  return palette.surface.opacity(0.6)
        }
    }

    private var border: Color {
        switch state {
        // En reposo la tecla ya no es un rectángulo gris flotando sobre otro
        // gris: el borde la separa del fondo también en modo oscuro.
        case .idle:    return palette.border
        case .correct: return palette.success
        case .wrong:   return palette.danger
        case .dimmed:  return palette.border.opacity(0.5)
        }
    }

    private var foreground: Color {
        switch state {
        case .idle:    return palette.textPrimary
        case .correct: return palette.success
        case .wrong:   return palette.danger
        case .dimmed:  return palette.textSecondary
        }
    }
}
