import SwiftUI

struct TelegraphKeyView: View {
    @ObservedObject var model: TelegraphKeyViewModel
    @Environment(\.scenePhase) private var scenePhase

    private let diameter: CGFloat = 176

    var body: some View {
        ZStack {
            // Anillo exterior: cuenta atrás hasta que el carácter se cierra.
            // Sin esto el jugador no tiene forma de saber cuánto margen le
            // queda para seguir tecleando, y una letra de tres elementos se
            // convierte en adivinar cuándo hay prisa.
            Circle()
                .trim(from: 0, to: model.isAwaitingCommit ? 0 : 1)
                .stroke(Color.secondary.opacity(0.35),
                        style: .init(lineWidth: 3, lineCap: .round))
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
                    .stroke(Color.accentColor, style: .init(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: model.ditDahThreshold), value: model.willBeDah)
                    .opacity(model.isDown ? 1 : 0)
            }
            .frame(width: diameter + 18, height: diameter + 18)

            // Cuerpo neumórfico del manipulador.
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(model.isDown ? 0.10 : 0.35),
                        radius: model.isDown ? 4 : 18, y: model.isDown ? 2 : 10)
                .frame(width: diameter, height: diameter)
                .scaleEffect(model.isDown ? 0.955 : 1)
                .animation(.spring(response: 0.18, dampingFraction: 0.7), value: model.isDown)

            Text(model.willBeDah ? "—" : "•")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(model.isDown ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
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

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Capsule()
                    .frame(width: symbol == .dit ? 12 : 34, height: 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(Color.accentColor)
        .frame(height: 12)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: symbols)
    }
}
