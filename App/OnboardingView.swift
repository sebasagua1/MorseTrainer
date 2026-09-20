import SwiftUI

/// Tres pantallas en el primer arranque. Existe porque sin ellas el juego pide
/// un acto de fe: te suelta letras a 18 WPM y parece roto o imposible. Explicar
/// *por qué* suenan rápido es la diferencia entre abandonar en el primer minuto
/// y entender que eso es el método.
struct OnboardingView: View {
    @ObservedObject var settings: GameSettings
    let onFinish: () -> Void

    @State private var page = 0
    @State private var isPlaying = false
    /// Mismo motivo que en la tienda: un `let` recrearía el motor de audio en
    /// cada redibujo, y aquí además hay un TabView que redibuja al deslizar.
    @StateObject private var demo = MorseTransmitter()

    private static let pages: [Page] = [
        Page(symbol: "dot.radiowaves.left.and.right",
             title: "Morse de verdad",
             body: "Vas a aprender a reconocer letras de oído, no a leer puntos y rayas escritos. Es la única forma que sirve fuera de una tabla."),
        Page(symbol: "hare",
             title: "Rápido desde el primer día",
             body: "Las letras suenan a velocidad final y lo que se alarga es el silencio entre ellas. Si sonaran despacio aprenderías a contar elementos, y ese hábito cuesta meses de quitar.",
             demo: true),
        Page(symbol: "iphone.radiowaves.left.and.right",
             title: "Oído, tacto o vista",
             body: "Cada señal suena, se siente en el Taptic Engine y puede salir por la linterna. Los tres canales van a la vez y se encienden y apagan en Ajustes.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, item in
                    PageView(page: item, isPlaying: isPlaying, play: playDemo)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(action: advance) {
                Text(page == Self.pages.count - 1 ? "Empezar" : "Siguiente")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            Button("Saltar", action: finish)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
                .opacity(page == Self.pages.count - 1 ? 0 : 1)
                .disabled(page == Self.pages.count - 1)
        }
        .background(Color(.systemBackground))
        .onDisappear { demo.cancel() }
    }

    private func advance() {
        if page < Self.pages.count - 1 {
            withAnimation { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        demo.cancel()
        settings.hasSeenOnboarding = true
        onFinish()
    }

    /// Oír una letra de verdad durante la explicación vale más que describirla,
    /// y de paso descubre el problema más tonto: tener el volumen a cero.
    private func playDemo() {
        guard !isPlaying else { return }
        isPlaying = true
        demo.channels = settings.channels.isEmpty ? [.audio] : settings.channels
        Task {
            await demo.play(text: "A", timing: FarnsworthTiming(characterWPM: 18, effectiveWPM: 5))
            isPlaying = false
        }
    }

    private struct Page {
        let symbol: String
        let title: String
        let body: String
        var demo: Bool = false
    }

    private struct PageView: View {
        let page: Page
        let isPlaying: Bool
        let play: () -> Void

        var body: some View {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: page.symbol)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor, isActive: isPlaying)

                Text(page.title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if page.demo {
                    Button(action: play) {
                        Label(isPlaying ? "Sonando…" : "Escuchar una A",
                              systemImage: isPlaying ? "speaker.wave.3.fill" : "play.fill")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isPlaying)
                }
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview { OnboardingView(settings: GameSettings()) {} }
