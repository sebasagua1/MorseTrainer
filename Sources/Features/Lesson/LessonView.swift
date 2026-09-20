import SwiftUI

struct LessonView: View {
    @StateObject private var model: LessonViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    private var theme: Theme { model.theme }

    /// Se llama al superar el nivel, para que el mapa desbloquee el siguiente.
    var onFinish: (LessonSummary) -> Void = { _ in }

    init(level: Level,
         store: PersistenceStore? = nil,
         settings: GameSettings? = nil,
         onFinish: @escaping (LessonSummary) -> Void = { _ in }) {
        self.init(session: .level(level), store: store,
                  settings: settings, onFinish: onFinish)
    }

    init(session: GameSession,
         store: PersistenceStore? = nil,
         settings: GameSettings? = nil,
         onFinish: @escaping (LessonSummary) -> Void = { _ in }) {
        // `StateObject(wrappedValue:)` con un autoclosure: SwiftUI puede
        // descartar instancias creadas en `init`, así que no guardamos ninguna
        // referencia suelta al VM ni a sus objetos internos.
        _model = StateObject(wrappedValue: LessonViewModel(session: session, store: store, settings: settings))
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
        .tint(theme.accent(scheme))
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

            if model.session.isEndless {
                // Sin final no hay barra que llenar: se muestra lo que sí
                // avanza, que son los aciertos.
                Text("\(model.itemsCompleted)")
                    .font(.headline.monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(model.itemsCompleted) ítems")
            } else {
                LessonProgressBar(progress: model.progress)
            }

            if let total = model.session.hearts {
                HeartsBar(remaining: model.hearts, total: total)
            } else if model.session.timeLimit != nil {
                CountdownBadge(secondsRemaining: model.secondsRemaining)
            } else {
                Text("\(Int(model.timing.effectiveWPM)) WPM")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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

                if case .judging(let correct) = model.phase, drill.kind != .reception {
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

    private var judgement: Bool? {
        if case .judging(let correct) = model.phase { return correct }
        return nil
    }

    var body: some View {
        VStack(spacing: 20) {
            // El centro de la pantalla ya no es un hueco: lleva el estado, el
            // destello y, tras responder, la letra con su patrón. Antes el
            // jugador miraba 40 % de pantalla vacía sin saber si sonaba algo.
            VStack(spacing: 18) {
                Text(statusText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: statusText)

                ZStack {
                    CarrierIndicator(isKeyed: model.isKeyed,
                                     isPlaying: model.isTransmitting)

                    if let target = revealedTarget {
                        RevealedAnswer(character: target,
                                       pattern: MorseAlphabet.code(for: target)?.pattern ?? "",
                                       correct: judgement ?? false)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .frame(height: 150)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: revealedTarget)
            }
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
            .opacity(isAnswering ? 1 : 0.35)
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

    private var statusText: String {
        if let correct = judgement { return correct ? "¡Correcto!" : "Era esta" }
        return model.isTransmitting ? "Escucha…" : "¿Qué letra has oído?"
    }

    private var statusTint: Color {
        guard let correct = judgement else { return .primary }
        return correct ? .green : .red
    }

    private var revealedTarget: Character? {
        if case .judging = model.phase { return model.lastTarget }
        return nil
    }
}

/// La letra y su patrón, revelados solo después de responder. Enseñarlos antes
/// convierte el ejercicio de escucha en lectura y rompe el método entero.
private struct RevealedAnswer: View {
    let character: Character
    let pattern: String
    let correct: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(String(character))
                .font(.system(size: 72, weight: .bold, design: .rounded))
            Text(pattern)
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .tracking(6)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(correct ? Color.green : Color.red)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(correct ? "Correcto" : "Era") \(String(character))")
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
            Image(systemName: headline.symbol)
                .font(.system(size: 64))
                .foregroundStyle(headline.tint)
                .symbolEffect(.bounce, value: summary.itemsCorrect)

            Text(headline.title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)

            HStack(spacing: 28) {
                ForEach(stats, id: \.title) { stat in
                    VStack(spacing: 4) {
                        Text(stat.value).font(.title2.weight(.bold).monospacedDigit())
                        Text(stat.title).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 8)

            if let weak = summary.weakSpots.first {
                Text("Tu punto débil: \(String(weak.pair.shown)) frente a \(String(weak.pair.answered))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button(action: onContinue) {
                Text(summary.mastered ? "Continuar" : "Volver")
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

    private var headline: (symbol: String, title: String, tint: Color) {
        switch summary.mode {
        case .level:
            return summary.mastered
                ? ("checkmark.seal.fill", "Nivel superado", .green)
                : ("arrow.counterclockwise.circle", "Casi. Otra pasada.", .orange)
        case .practice:
            return ("infinity.circle.fill", "Sesión de práctica", .accentColor)
        case .timeAttack:
            return ("timer", "¡Tiempo!", .accentColor)
        case .survival:
            return ("flame.fill", "Hasta aquí llegaste", .orange)
        }
    }

    /// Cada modo se mide por lo suyo. Enseñar «precisión» en contrarreloj o
    /// «corazones» en práctica libre sería ruido: no es lo que el jugador
    /// estaba intentando hacer.
    private var stats: [(title: String, value: String)] {
        let accuracy = ("Precisión", "\(Int(summary.accuracy * 100))%")
        let copper = ("Cobre", "\(summary.copperEarned)")
        switch summary.mode {
        case .level:
            return [accuracy, copper, ("Corazones", "\(summary.heartsRemaining)")]
        case .practice:
            return [("Ítems", "\(summary.itemsTotal)"), accuracy, copper]
        case .timeAttack:
            return [("Aciertos", "\(summary.itemsCorrect)"), accuracy, copper]
        case .survival:
            return [("Aciertos", "\(summary.itemsCorrect)"),
                    ("Velocidad", "\(Int(summary.topEffectiveWPM)) WPM"),
                    copper]
        }
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

#Preview("Campaña") {
    LessonView(level: LevelPlan.levels[0], store: PersistenceStore(inMemory: true))
}

#Preview("Contrarreloj") {
    LessonView(session: .timeAttack(alphabet: Array("ETANIMSO"), timing: .comfortable),
               store: PersistenceStore(inMemory: true))
}

#Preview("Supervivencia") {
    LessonView(session: .survival(alphabet: Array("ETANIMSO"), timing: .comfortable),
               store: PersistenceStore(inMemory: true))
}
