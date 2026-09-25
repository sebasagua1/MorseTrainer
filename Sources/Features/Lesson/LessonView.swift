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
        .background(theme.palette(scheme).background)
        .morseTheme(theme, scheme)
        .shake(on: model.shakeTrigger, reduceMotion: reduceMotion)
        // Borde rojo en el fallo: es el canal que sobrevive a "Reducir movimiento".
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(theme.palette(scheme).danger.opacity(isWrong ? 0.6 : 0), lineWidth: 5)
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
                    .font(.rounded(.headline, .semibold))
                    .foregroundStyle(theme.palette(scheme).textSecondary)
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
                                          keyModel: model.keyModel,
                                          theme: theme)
                case .word:
                    TransmissionDrillView(prompt: drill.prompt,
                                          subtitle: "Transmite la palabra completa",
                                          progress: model.wordProgress,
                                          keyModel: model.keyModel,
                                          theme: theme)
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

    @Environment(\.palette) private var palette

    private var isAnswering: Bool {
        if case .awaitingAnswer = model.phase { return true }
        return false
    }

    private var judgement: Bool? {
        if case .judging(let correct) = model.phase { return correct }
        return nil
    }

    var body: some View {
        VStack(spacing: Space.lg) {
            // El centro de la pantalla ya no es un hueco: lleva el estado, el
            // destello y, tras responder, la letra con su patrón. Antes el
            // jugador miraba 40 % de pantalla vacía sin saber si sonaba algo.
            VStack(spacing: Space.lg) {
                Text(statusText)
                    .font(.rounded(.title3, .semibold))
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
                // 150 reservaba menos alto del que ocupa el indicador, así que
                // el hueco sobrante se iba todo arriba y la señal quedaba baja
                // y pequeña en medio de una pantalla vacía.
                .frame(height: 220)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: revealedTarget)
            }
            .frame(maxHeight: .infinity)

            Button {
                model.replay()
            } label: {
                Label("Repetir", systemImage: "arrow.clockwise")
                    .font(.rounded(.callout, .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm + 4)
                    .background(
                        Capsule()
                            .fill(palette.surfaceRaised)
                            .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1.5))
                    )
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
        guard let correct = judgement else { return palette.textSecondary }
        return correct ? palette.success : palette.danger
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

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Space.md) {
            Text(String(character))
                .displayFont(76)
            MorseGlyph(code: MorseCode(pattern: pattern) ?? MorseCode([]), unit: 9)
        }
        .foregroundStyle(correct ? palette.success : palette.danger)
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
    var theme: Theme = .classic

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Space.lg) {
            Text(subtitle)
                .font(.rounded(.title3, .semibold))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.md)

            promptDisplay
                .frame(maxHeight: .infinity)

            // Eco de lo que el jugador lleva tecleado en el carácter actual.
            MorseBufferStrip(symbols: keyModel.buffer)
                .frame(height: 16)

            TelegraphKeyView(model: keyModel, theme: theme)
        }
        .padding(.bottom, Space.lg)
    }

    @ViewBuilder
    private var promptDisplay: some View {
        if let progress {
            HStack(spacing: 4) {
                ForEach(Array(prompt.enumerated()), id: \.offset) { index, character in
                    let done = index < progress.count
                    Text(String(character))
                        .displayFont(48, .bold, relativeTo: .title)
                        .foregroundStyle(done ? palette.success : palette.textPrimary)
                        .opacity(done ? 1 : (index == progress.count ? 1 : 0.35))
                        .scaleEffect(index == progress.count ? 1.12 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
                }
            }
            .accessibilityLabel("Palabra \(prompt), transmitidas \(progress.count) letras")
        } else {
            Text(prompt)
                .displayFont(96)
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
                .displayFont(64, .regular)
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

            if !summary.mastered, let shortfall = summary.shortfall {
                Text(shortfall.message)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }

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
    @Environment(\.palette) private var palette

    let onRetry: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "heart.slash.fill")
                .displayFont(56, .regular)
                .foregroundStyle(palette.danger)
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
