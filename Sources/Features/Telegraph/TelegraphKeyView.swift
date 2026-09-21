import SwiftUI

struct TelegraphKeyView: View {
    @ObservedObject var model: TelegraphKeyViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// La cara de la tecla la pone el tema comprado en la tienda. Antes esto
    /// era `.regularMaterial`: los cuatro temas anunciaban "teclas de baquelita"
    /// o "bronce pulido" y los cuatro se veían exactamente igual.
    var theme: Theme = .classic

    private let diameter: CGFloat = 188

    private var keyFace: Color { theme.keyFace(scheme) }

    var body: some View {
        ZStack {
            // Anillo exterior: cuenta atrás hasta que el carácter se cierra.
            // Sin esto el jugador no tiene forma de saber cuánto margen le
            // queda para seguir tecleando, y una letra de tres elementos se
            // convierte en adivinar cuándo hay prisa.
            Circle()
                .trim(from: 0, to: model.isAwaitingCommit ? 0 : 1)
                .stroke(palette.textSecondary.opacity(0.55),
                        style: .init(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter + 44, height: diameter + 44)
                .opacity(model.isAwaitingCommit ? 1 : 0)
                // Animada solo al entrar en la espera; al salir, instantánea.
                .animation(model.isAwaitingCommit ? .linear(duration: model.letterGap) : nil,
                           value: model.isAwaitingCommit)

            // Anillo de progreso: se llena mientras el toque avanza hacia "raya".
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !model.isDown)) { _ in
                Circle()
                    .trim(from: 0, to: model.willBeDah ? 1 : 0.0001)
                    .stroke(palette.accent, style: .init(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: model.ditDahThreshold), value: model.willBeDah)
                    .opacity(model.isDown ? 1 : 0)
            }
            .frame(width: diameter + 18, height: diameter + 18)

            // Bisel: el aro metálico sobre el que se apoya la tecla.
            Circle()
                .fill(
                    LinearGradient(colors: [palette.border, palette.surface],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: diameter + 16, height: diameter + 16)
                .shadow(color: .black.opacity(model.isDown ? 0.12 : 0.40),
                        radius: model.isDown ? 6 : 22, y: model.isDown ? 3 : 12)

            // Cara de la tecla. El degradado vertical le da volumen: pulsada,
            // se invierte, que es lo que hace un botón físico al hundirse.
            Circle()
                .fill(
                    LinearGradient(
                        colors: model.isDown
                            ? [keyFace.darker(0.10), keyFace]
                            : [keyFace.lighter(0.09), keyFace.darker(0.06)],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    Circle().strokeBorder(
                        model.isDown ? palette.accent.opacity(0.55) : .white.opacity(0.14),
                        lineWidth: model.isDown ? 3 : 1)
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(model.isDown && !reduceMotion ? 0.955 : 1)
                .animation(.spring(response: 0.18, dampingFraction: 0.7), value: model.isDown)

            // El glifo es la forma real —punto o raya— y no los caracteres
            // "•" y "—", que dependen de la fuente y no dicen su duración.
            Capsule(style: .continuous)
                .frame(width: model.willBeDah ? 96 : 30, height: 30)
                .foregroundStyle(model.isDown ? palette.accent : palette.textSecondary)
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: model.willBeDah)
                .shadow(color: palette.accent.opacity(model.isDown ? 0.5 : 0), radius: 14)
        }
        .frame(width: diameter + 60, height: diameter + 60)
        .contentShape(Circle())
        // minimumDistance: 0 → onChanged dispara en el key-down exacto,
        // onEnded en el key-up exacto. Dos timestamps, una duración medible.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in model.keyDown() }
                .onEnded { _ in model.keyUp() }
        )
        .accessibilityLabel("Manipulador telegráfico")
        .accessibilityHint("Toque corto para punto, mantén pulsado para raya")
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.releaseIfNeeded() }
        }
        .onDisappear { model.releaseIfNeeded() }
    }
}

/// Eco del buffer actual encima de la tecla: ".-." mientras el jugador teclea.
struct MorseBufferStrip: View {
    let symbols: [MorseSymbol]

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Capsule()
                    .frame(width: symbol == .dit ? 12 : 34, height: 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(palette.accent)
        .frame(height: 12)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: symbols)
    }
}
