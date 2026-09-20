import Foundation
import Combine
import QuartzCore

/// Dueño único del estado de una lección: la cola de ejercicios, los corazones,
/// la puntuación y el veredicto de dominio. Los VM de ejercicio (teclado
/// dinámico, manipulador) no deciden nada: le reportan hacia arriba.
@MainActor
final class LessonViewModel: ObservableObject {

    // MARK: Estado publicado

    @Published private(set) var phase: LessonPhase = .idle
    @Published private(set) var drill: Drill?
    @Published private(set) var hearts: Int
    @Published private(set) var itemsCompleted = 0
    @Published private(set) var copperEarned = 0
    /// Progreso de la palabra en curso ("MEA" de "MEAT").
    @Published private(set) var wordProgress = ""
    /// Contador que la vista observa para disparar el screen shake.
    @Published private(set) var shakeTrigger = 0
    /// Racha de aciertos seguidos dentro del nivel (multiplicador de cobre).
    @Published private(set) var comboStreak = 0
    /// Segundos que quedan en los modos con reloj.
    @Published private(set) var secondsRemaining: TimeInterval = 0
    /// Última respuesta y su objetivo: la vista los usa para colorear la tecla
    /// pulsada y revelar la correcta durante el veredicto.
    @Published private(set) var lastAnswer: Character?
    @Published private(set) var lastTarget: Character?
    /// Estado del transmisor *re-publicado*. SwiftUI no observa
    /// `ObservableObject` anidados: si la vista leyera `transmitter.isKeyed`
    /// directamente, el destello no se redibujaría nunca.
    @Published private(set) var isKeyed = false
    @Published private(set) var isTransmitting = false

    var progress: Double {
        if let limit = session.itemLimit, limit > 0 {
            return min(1, Double(itemsCompleted) / Double(limit))
        }
        if let total = session.timeLimit, total > 0 {
            return min(1, 1 - secondsRemaining / total)
        }
        return 0   // sin final: la barra no significa nada
    }

    // MARK: Dependencias

    let session: GameSession
    /// Nivel de campaña, si la sesión lo es. Los modos libres no tienen.
    var level: Level? { session.level }
    /// Velocidad actual: en supervivencia sube durante la partida.
    private(set) var timing: FarnsworthTiming
    /// Expuesto para Ajustes (canales, frecuencia del tono). Para el estado
    /// en vivo, la vista usa `isKeyed` / `isTransmitting` de este mismo VM.
    let transmitter: MorseTransmitter
    let keyModel: TelegraphKeyViewModel

    // MARK: Internos

    private var scheduler: DrillScheduler
    private var rollingResults: [Bool] = []
    private var responseTimes: [TimeInterval] = []
    private var words: [String]
    private var answerWindowStart: CFTimeInterval = 0
    private var usedReplay = false
    private var receptionCount = 0
    private var transmissionCount = 0
    private var advanceTask: Task<Void, Never>?

    private let store: PersistenceStore?
    private let settings: GameSettings
    /// Prior con el que arrancó la sesión. Se guarda para poder restarlo al
    /// fundir: el programador acumula sobre lo sembrado, así que sin esto el
    /// historial se contaría dos veces en cada lección.
    private var seededStats: [Character: CharacterStat] = [:]
    private var seededConfusions: [ConfusionPair: Int] = [:]
    private var hasPersisted = false
    private var correctStreakForRamp = 0
    private var countdownTask: Task<Void, Never>?

    private let keyboardSize = 6
    private let judgingPause: TimeInterval = 0.6

    convenience init(level: Level,
                     store: PersistenceStore? = nil,
                     settings: GameSettings? = nil,
                     transmitter: MorseTransmitter? = nil,
                     keyModel: TelegraphKeyViewModel? = nil) {
        self.init(session: .level(level), store: store, settings: settings,
                  transmitter: transmitter, keyModel: keyModel)
    }

    init(session: GameSession,
         store: PersistenceStore? = nil,
         settings: GameSettings? = nil,
         transmitter: MorseTransmitter? = nil,
         keyModel: TelegraphKeyViewModel? = nil) {
        let transmitter = transmitter ?? MorseTransmitter()
        self.session = session
        self.settings = settings ?? GameSettings()
        self.timing = session.timing
        self.store = store
        self.transmitter = transmitter
        self.hearts = session.hearts ?? 0
        self.scheduler = DrillScheduler(alphabet: session.alphabet,
                                        newCharacters: session.newCharacters)
        self.words = LevelPlan.words(for: session.alphabet)
        self.keyModel = keyModel ?? TelegraphKeyViewModel(timing: session.timing)

        // El manipulador solo sabe producir caracteres; quien juzga es la lección.
        self.keyModel.onCharacter = { [weak self] _, decoded in
            self?.submitTransmission(decoded)
        }

        transmitter.$isKeyed.assign(to: &$isKeyed)
        transmitter.$isPlaying.assign(to: &$isTransmitting)
    }

    // MARK: - Ciclo de la lección

    func start() {
        // Los ajustes se aplican al arrancar, no al construir: el jugador
        // puede cambiarlos entre partidas sin recrear nada.
        transmitter.channels = settings.channels
        transmitter.toneFrequency = settings.toneFrequency
        keyModel.apply(settings)
        transmitter.prepare()
        hearts = session.hearts ?? 0
        timing = session.timing
        correctStreakForRamp = 0
        secondsRemaining = session.timeLimit ?? 0
        itemsCompleted = 0
        copperEarned = 0
        comboStreak = 0
        receptionCount = 0
        transmissionCount = 0
        rollingResults.removeAll()
        responseTimes.removeAll()
        hasPersisted = false

        let seed = store?.seed(for: session.alphabet) ?? (stats: [:], confusions: [:])
        seededStats = seed.stats
        seededConfusions = seed.confusions
        scheduler = DrillScheduler(alphabet: session.alphabet,
                                   newCharacters: session.newCharacters,
                                   seededStats: seededStats,
                                   seededConfusions: seededConfusions)
        store?.registerPlay()
        startCountdownIfNeeded()
        Task { await presentNextDrill() }
    }

    func exit() {
        countdownTask?.cancel()
        advanceTask?.cancel()
        transmitter.cancel()
        keyModel.reset()
        // Abandonar a medias también deja datos útiles: los ítems respondidos
        // cuentan para el histórico aunque el nivel no se haya terminado.
        if itemsCompleted > 0 { persist(makeSummary(mastered: false)) }
    }

    /// Repetir el prompt es gratis en corazones, pero anula el bono de rapidez:
    /// castigar la repetición empuja a adivinar, y adivinar arruina el Koch.
    func replay() {
        guard case .awaitingAnswer = phase, let drill, drill.kind == .reception else { return }
        usedReplay = true
        Task { await presentPrompt(for: drill) }
    }

    // MARK: - Construcción de ejercicios

    private func presentNextDrill() async {
        if session.hearts != nil, hearts <= 0 {
            // Quedarse sin corazones también enseña: los fallos de esta pasada
            // son justo los datos que el motor necesita para la siguiente.
            if session.mode == .level {
                persist(makeSummary(mastered: false))
                phase = .outOfHearts
            } else {
                // En supervivencia quedarse sin corazones ES el final de la
                // partida, no un fracaso: lo que importa es hasta dónde llegó.
                finish()
            }
            return
        }
        if let limit = session.itemLimit, itemsCompleted >= limit { finish(); return }

        let next = makeDrill()
        drill = next
        wordProgress = ""
        usedReplay = false
        lastAnswer = nil
        lastTarget = nil
        keyModel.reset()
        keyModel.timing = timing

        await presentPrompt(for: next)
    }

    private func presentPrompt(for drill: Drill) async {
        switch drill.kind {
        case .reception:
            phase = .presenting
            await transmitter.play(text: drill.prompt, timing: timing)
        case .transmission, .word:
            // En transmisión el prompt es visual: no se le regala el audio,
            // el jugador debe recuperar el patrón de memoria.
            break
        }
        answerWindowStart = CACurrentMediaTime()
        phase = .awaitingAnswer
    }

    private func makeDrill() -> Drill {
        let wordZoneStart = (session.itemLimit ?? 0) - session.mix.wordRounds
        if session.mix.wordRounds > 0, itemsCompleted >= wordZoneStart,
           let word = words.randomElement() {
            return Drill(kind: .word, prompt: word, options: [])
        }
        let character = scheduler.nextCharacter()
        if preferReception() {
            return Drill(kind: .reception,
                         prompt: String(character),
                         options: keyboardOptions(for: character))
        }
        return Drill(kind: .transmission, prompt: String(character), options: [])
    }

    /// Mantiene la proporción recepción/transmisión del nivel sin dejar que el
    /// azar produzca rachas largas de un solo modo.
    private func preferReception() -> Bool {
        let total = receptionCount + transmissionCount
        guard total > 0 else { return true }
        return Double(receptionCount) / Double(total) < session.mix.receptionShare
    }

    /// Teclado dinámico. Con alfabeto pequeño se muestra entero; a partir de ahí
    /// los distractores se eligen entre los caracteres que el jugador *ya*
    /// confunde con este. Un teclado al azar deja aprobar por descarte.
    private func keyboardOptions(for target: Character) -> [Character] {
        guard session.alphabet.count > keyboardSize else {
            return session.alphabet.shuffled()
        }
        var options: Set<Character> = [target]
        let confusable = scheduler.confusions
            .filter { $0.key.shown == target || $0.key.answered == target }
            .sorted { $0.value > $1.value }
            .flatMap { [$0.key.shown, $0.key.answered] }
            .filter { $0 != target }
        for candidate in confusable where options.count < keyboardSize {
            options.insert(candidate)
        }
        for candidate in session.alphabet.shuffled() where options.count < keyboardSize {
            options.insert(candidate)
        }
        return options.shuffled()
    }

    // MARK: - Respuestas

    func submitReception(_ answer: Character) {
        guard case .awaitingAnswer = phase,
              let drill, drill.kind == .reception,
              let target = drill.targetCharacter else { return }
        receptionCount += 1
        complete(correct: answer == target, target: target, answer: answer)
    }

    private func submitTransmission(_ decoded: Character?) {
        guard case .awaitingAnswer = phase, let drill else { return }

        switch drill.kind {
        case .transmission:
            guard let target = drill.targetCharacter else { return }
            transmissionCount += 1
            complete(correct: decoded == target, target: target, answer: decoded)

        case .word:
            // La palabra se juzga carácter a carácter: un fallo la corta ahí
            // mismo, para que el error no se arrastre hasta el final.
            let expected = Array(drill.prompt)
            let index = wordProgress.count
            guard index < expected.count else { return }
            let target = expected[index]
            if decoded == target {
                wordProgress.append(target)
                if wordProgress.count == expected.count {
                    transmissionCount += 1
                    complete(correct: true, target: target, answer: decoded)
                } else {
                    // Carácter intermedio: cuenta para la estadística, pero no
                    // cierra el ítem — `complete` registrará el último.
                    comboStreak += 1
                    scheduler.record(shown: target, answered: decoded, responseTime: 0)
                }
            } else {
                transmissionCount += 1
                complete(correct: false, target: target, answer: decoded)
            }

        case .reception:
            break
        }
    }

    private func complete(correct: Bool, target: Character, answer: Character?) {
        let responseTime = CACurrentMediaTime() - answerWindowStart
        lastAnswer = answer
        lastTarget = target
        scheduler.record(shown: target, answered: answer, responseTime: responseTime)
        rollingResults.append(correct)
        // La mediana de respuesta mide reconocimiento de un carácter suelto:
        // las rondas de palabra duran varios segundos y la falsearían.
        if correct, drill?.kind != .word { responseTimes.append(responseTime) }

        if correct {
            comboStreak += 1
            copperEarned += reward(responseTime: responseTime)
            rampSpeedIfNeeded()
        } else {
            comboStreak = 0
            correctStreakForRamp = 0
            if session.hearts != nil { hearts -= 1 }
            shakeTrigger += 1
        }

        itemsCompleted += 1
        phase = .judging(correct: correct)

        advanceTask?.cancel()
        advanceTask = Task { [judgingPause] in
            try? await Task.sleep(for: .seconds(judgingPause))
            guard !Task.isCancelled else { return }
            await self.presentNextDrill()
        }
    }

    /// Cobre por ítem: base + bono de rapidez + multiplicador de combo.
    /// El bono de rapidez se mide contra la duración real del prompt, no contra
    /// un número fijo: así no penaliza los niveles lentos.
    private func reward(responseTime: TimeInterval) -> Int {
        var copper = 2
        if !usedReplay {
            let promptDuration = timing.duration(of: drill?.prompt ?? "")
            if responseTime < promptDuration * 0.8 { copper += 2 }
            else if responseTime < promptDuration * 1.5 { copper += 1 }
        }
        if comboStreak >= 10 { copper += 2 }
        else if comboStreak >= 5 { copper += 1 }
        return copper
    }

    // MARK: - Cierre

    private func finish() {
        countdownTask?.cancel()
        advanceTask?.cancel()
        transmitter.cancel()
        keyModel.reset()

        // El dominio solo existe en la campaña: los modos libres no enseñan
        // caracteres nuevos, así que no hay nada que desbloquear.
        var mastered = false
        if let level {
            mastered = scheduler.hasMastered(level.mastery, rollingResults: rollingResults)
                && medianResponseTime <= level.mastery.medianResponseTime
            if mastered {
                copperEarned += level.copperReward
                copperEarned += hearts * 5
                if hearts == level.hearts { copperEarned += 10 }   // ronda perfecta
            }
        }

        let summary = makeSummary(mastered: mastered)
        persist(summary)
        phase = .completed(summary)
    }

    private func makeSummary(mastered: Bool) -> LessonSummary {
        let correct = rollingResults.filter { $0 }.count
        let accuracy = rollingResults.isEmpty ? 0 : Double(correct) / Double(rollingResults.count)
        return LessonSummary(
            mode: session.mode,
            levelID: level?.id ?? 0,
            itemsCorrect: correct,
            itemsTotal: rollingResults.count,
            topEffectiveWPM: timing.effectiveWPM,
            accuracy: accuracy,
            heartsRemaining: hearts,
            copperEarned: copperEarned,
            mastered: mastered,
            medianResponseTime: medianResponseTime,
            weakSpots: scheduler.topConfusions().map { WeakSpot(pair: $0.0, count: $0.1) }
        )
    }

    /// Se llama una sola vez por pasada. `hasPersisted` evita que un reintento
    /// rápido vuelva a sumar los mismos intentos al histórico.
    private func persist(_ summary: LessonSummary) {
        guard !hasPersisted else { return }
        hasPersisted = true
        store?.merge(summary: summary,
                     stats: scheduler.stats,
                     confusions: scheduler.confusions,
                     seededStats: seededStats,
                     seededConfusions: seededConfusions)
    }

    private var medianResponseTime: TimeInterval {
        guard !responseTimes.isEmpty else { return .greatestFiniteMagnitude }
        let sorted = responseTimes.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - Reloj y rampa

    /// Cuenta atrás de los modos con tiempo. Usa deadlines absolutos: restar un
    /// segundo por vuelta acumularía el retraso del planificador y la partida
    /// duraría de más.
    private func startCountdownIfNeeded() {
        countdownTask?.cancel()
        guard let total = session.timeLimit else { return }
        secondsRemaining = total
        countdownTask = Task {
            let clock = ContinuousClock()
            let end = clock.now.advanced(by: .seconds(total))
            while !Task.isCancelled {
                let left = clock.now.duration(to: end)
                let seconds = Double(left.components.seconds)
                    + Double(left.components.attoseconds) * 1e-18
                if seconds <= 0 { break }
                self.secondsRemaining = seconds
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            self.secondsRemaining = 0
            self.timeExpired()
        }
    }

    private func timeExpired() {
        guard case .completed = phase else {
            advanceTask?.cancel()
            transmitter.cancel()
            keyModel.reset()
            finish()
            return
        }
    }

    /// En supervivencia la velocidad sube cada pocos aciertos seguidos. Es lo
    /// que convierte el modo en una medida de tu techo real: la campaña se
    /// detiene en cuanto dominas el nivel y nunca te enseña dónde te rompes.
    private func rampSpeedIfNeeded() {
        guard session.speedRamp else { return }
        correctStreakForRamp += 1
        guard correctStreakForRamp >= GameSession.rampInterval else { return }
        correctStreakForRamp = 0
        timing = session.ramped(from: timing)
        keyModel.timing = timing
    }

    /// Estadística acumulada del nivel, para que `PersistenceStore` la funda con
    /// el histórico del jugador: la repetición espaciada solo funciona si el
    /// fallo de hoy sigue pesando la semana que viene.
    var characterStats: [Character: CharacterStat] { scheduler.stats }
}
