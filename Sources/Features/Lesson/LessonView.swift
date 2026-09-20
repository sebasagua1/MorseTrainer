import SwiftUI

struct LessonView: View {
    @StateObject private var model: LessonViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    /// Se llama al superar el nivel, para que el mapa desbloquee el siguiente.
    var onFinish: (LessonSummary) -> Void = { _ in }

    init(level: Level,
         store: PersistenceStore? = nil,
         onFinish: @escaping (LessonSummary) -> Void = { _ in }) {
        // `StateObject(wrappedValue:)` con un autoclosure: SwiftUI puede
        // descartar instancias creadas en `init`, así que no guardamos ninguna
        // referencia suelta al VM ni a sus objetos internos.
        _model = StateObject(wrappedValue: LessonViewModel(level: level, store: store))
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                switch model.phase {
                case .completed(let summary):
                    LessonSummaryView(summary: summary) { onFinish(summary); dismiss() }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                case .outOfHearts:
                    OutOfHeartsView(onRetry: { model.start() }, onExit: { dismiss() })
                        .transition(.opacity)
                default:
                    drillContent
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: model.phase)
        }
        .background(Color(.systemBackground))
        .shake(on: model.shakeTrigger, reduceMotion: reduceMotion)
        // Borde rojo en el fallo: es el canal que sobrevive a "Reducir movimiento".
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Color.red.opacity(isWrong ? 0.55 : 0), lineWidth: 5)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.3), value: isWrong)
        )
        .onAppear { model.start() }
        .onDisappear { model.exit() }
    }

    private var isWrong: Bool {
        if case .judging(false) = model.phase { return true }
        return false
    }

    // MARK: - Barra superior

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { model.exit(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)      // objetivo táctil completo
            }
            .accessibilityLabel("Salir de la lección")

            LessonProgressBar(progress: model.progress)

            HeartsBar(remaining: model.hearts, total: model.level.hearts)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Contenido del ejercicio

    @ViewBuilder
    private var drillContent: some View {
        if let drill = model.drill {
            VStack(spacing: 0) {
                switch drill.kind {
                case .reception:
                    ReceptionDrillView(drill: drill, model: model)
                case .transmission:
                    TransmissionDrillView(prompt: drill.prompt,
                                          subtitle: "Transmite esta letra",
                                          progress: nil,
                                          keyModel: model.keyModel)
                case .word:
                    TransmissionDrillView(prompt: drill.prompt,
                                          subtitle: "Transmite la palabra completa",
                                          progress: model.wordProgress,
                                          keyModel: model.keyModel)
                }

                if case .judging(let correct) = model.phase {
                    JudgeBanner(correct: correct,
                                target: model.lastTarget ?? " ",
                                answer: model.lastAnswer,
                                pattern: pattern(for: model.lastTarget))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
        } else {
            ProgressView().controlSize(.large)
        }
    }

    private func pattern(for character: Character?) -> String {
        guard let character, let code = MorseAlphabet.code(for: character) else { return "" }
        return code.pattern
    }
}

// MARK: - Recepción

struct ReceptionDrillView: View {
    let drill: Drill
    @ObservedObject var model: LessonViewModel

    private var isAnswering: Bool {
        if case .awaitingAnswer = model.phase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("¿Qué letra has oído?")
                .font(.title3.weight(.semibold))
                .padding(.top, 12)

            CarrierIndicator(isKeyed: model.isKeyed,
                             isPlaying: model.isTransmitting)
                .frame(maxHeight: .infinity)

            Button {
                model.replay()
            } label: {
                Label("Repetir", systemImage: "arrow.clockwise")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(.plain)
            .disabled(!isAnswering)
            .opacity(isAnswering ? 1 : 0.4)
            .accessibilityHint("Vuelve a reproducir la señal. No cuesta corazones.")

            DynamicKeyboardView(options: drill.options,
                                isEnabled: isAnswering,
                                revealedTarget: revealedTarget,
                                chosenAnswer: model.lastAnswer) { character in
                model.submitReception(character)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private var revealedTarget: Character? {
        if case .judging = model.phase { return model.lastTarget }
        return nil
    }
}

// MARK: - Transmisión

struct TransmissionDrillView: View {
    let prompt: String
    let subtitle: String
    /// Para rondas de palabra: lo ya transmitido correctamente.
    let progress: String?
    /// Se observa el manipulador directamente: es un objeto estable (se crea
    /// una vez y nunca se reemplaza), así que `@ObservedObject` es seguro aquí.
    @ObservedObject var keyModel: TelegraphKeyViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text(subtitle)
                .font(.title3.weight(.semibold))
                .padding(.top, 12)

            promptDisplay
                .frame(maxHeight: .infinity)

            // Eco de lo que el jugador lleva tecleado en el carácter actual.
            MorseBufferStrip(symbols: keyModel.buffer)
                .frame(height: 16)

            TelegraphKeyView(model: keyModel)
                .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var promptDisplay: some View {
        if let progress {
            HStack(spacing: 4) {
                ForEach(Array(prompt.enumerated()), id: \.offset) { index, character in
                    let done = index < progress.count
                    Text(String(character))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(done ? Color.green : .primary)
                        .opacity(done ? 1 : (index == progress.count ? 1 : 0.35))
                        .scaleEffect(index == progress.count ? 1.12 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
                }
            }
            .accessibilityLabel("Palabra \(prompt), transmitidas \(progress.count) letras")
        } else {
            Text(prompt)
                .font(.system(size: 92, weight: .bold, design: .rounded))
                .accessibilityLabel("Transmite la letra \(prompt)")
        }
    }
}

// MARK: - Cierre

struct LessonSummaryView: View {
    let summary: LessonSummary
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: summary.mastered ? "checkmark.seal.fill" : "arrow.counterclockwise.circle")
                .font(.system(size: 64))
                .foregroundStyle(summary.mastered ? Color.green : Color.orange)
                .symbolEffect(.bounce, value: summary.mastered)

            Text(summary.mastered ? "Nivel superado" : "Casi. Otra pasada.")
                .font(.title.weight(.bold))

            HStack(spacing: 28) {
                stat("Precisión", "\(Int(summary.accuracy * 100))%")
                stat("Cobre", "\(summary.copperEarned)")
                stat("Corazones", "\(summary.heartsRemaining)")
            }
            .padding(.vertical, 8)

            if let weak = summary.weakSpots.first {
                Text("Tu punto débil: \(String(weak.pair.shown)) frente a \(String(weak.pair.answered))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: onContinue) {
                Text(summary.mastered ? "Continuar" : "Reintentar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct OutOfHeartsView: View {
    let onRetry: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "heart.slash.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
            Text("Te has quedado sin corazones")
                .font(.title2.weight(.bold))
            Text("El nivel se reinicia, pero lo que el motor aprendió sobre tus fallos se conserva.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(action: onRetry) {
                Text("Reintentar")
                    .font(.headline)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Button("Volver al mapa", action: onExit)
                .font(.callout)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Previews

#Preview("Recepción") {
    LessonView(level: LevelPlan.levels[0], store: PersistenceStore(inMemory: true))
}

#Preview("Palabras") {
    LessonView(level: LevelPlan.levels[4], store: PersistenceStore(inMemory: true))
}
