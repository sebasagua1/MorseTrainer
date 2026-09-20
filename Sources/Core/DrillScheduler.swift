import Foundation

// MARK: - Estadística por carácter

struct CharacterStat: Sendable {
    var character: Character
    var attempts: Int = 0
    var correct: Int = 0
    var lastSeenIndex: Int = -999
    var medianResponseTime: TimeInterval = 0

    var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
    /// Sin datos asumimos "a medias": ni se ceba ni se ignora.
    var effectiveAccuracy: Double { attempts < 3 ? 0.5 : accuracy }
}

struct ConfusionPair: Hashable, Sendable {
    let shown: Character
    let answered: Character
}

// MARK: - Serialización

// `Character` no es `Codable`, así que la síntesis automática no sirve.
// Se persiste como `String` de un carácter, que además es lo que quiere
// SwiftData y lo que se lee sin dolor en un volcado JSON de soporte.

extension CharacterStat: Codable {
    private enum CodingKeys: String, CodingKey {
        case character, attempts, correct, lastSeenIndex, medianResponseTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .character)
        guard let character = raw.first else {
            throw DecodingError.dataCorruptedError(forKey: .character, in: container,
                                                   debugDescription: "carácter vacío")
        }
        self.character = character
        self.attempts = try container.decode(Int.self, forKey: .attempts)
        self.correct = try container.decode(Int.self, forKey: .correct)
        self.lastSeenIndex = try container.decode(Int.self, forKey: .lastSeenIndex)
        self.medianResponseTime = try container.decode(TimeInterval.self, forKey: .medianResponseTime)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(character), forKey: .character)
        try container.encode(attempts, forKey: .attempts)
        try container.encode(correct, forKey: .correct)
        try container.encode(lastSeenIndex, forKey: .lastSeenIndex)
        try container.encode(medianResponseTime, forKey: .medianResponseTime)
    }
}

extension ConfusionPair: Codable {
    private enum CodingKeys: String, CodingKey { case shown, answered }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let shownRaw = try container.decode(String.self, forKey: .shown)
        let answeredRaw = try container.decode(String.self, forKey: .answered)
        guard let shown = shownRaw.first, let answered = answeredRaw.first else {
            throw DecodingError.dataCorruptedError(forKey: .shown, in: container,
                                                   debugDescription: "carácter vacío")
        }
        self.shown = shown
        self.answered = answered
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(shown), forKey: .shown)
        try container.encode(String(answered), forKey: .answered)
    }
}

// MARK: - Programador adaptativo

/// Repetición espaciada ponderada. No es SM-2 (que optimiza intervalos de días);
/// aquí el objetivo es intra-sesión: elegir el siguiente ítem para maximizar la
/// corrección de errores sin que el jugador note que le están castigando.
struct DrillScheduler {

    var alphabet: [Character]
    var stats: [Character: CharacterStat] = [:]
    var confusions: [ConfusionPair: Int] = [:]
    /// Índice del ítem actual dentro de la sesión (para penalizar la recencia).
    private(set) var itemIndex = 0
    /// Aciertos conseguidos **en esta sesión**, separados del histórico.
    /// Sin esto, sembrar el prior desde disco dejaría aprobar el requisito de
    /// "6 aciertos del carácter nuevo" sin haber respondido ni una vez hoy.
    private(set) var sessionCorrect: [Character: Int] = [:]

    // Pesos del modelo.
    private let baseWeight = 1.0
    private let errorWeight = 3.5        // cuánto tira el fallo
    private let confusionWeight = 2.5    // cuánto tira un par confundido
    private let noveltyWeight = 2.0      // impulso a los caracteres nuevos del nivel
    private let recencyPenalty = 0.65    // evita repetir lo que acaba de salir

    /// `seededStats` / `seededConfusions` vienen de `PersistenceStore`: es lo
    /// que el motor ya sabía del jugador antes de empezar la lección.
    init(alphabet: [Character],
         newCharacters: [Character] = [],
         seededStats: [Character: CharacterStat] = [:],
         seededConfusions: [ConfusionPair: Int] = [:]) {
        self.alphabet = alphabet
        self.newCharacters = Set(newCharacters)
        self.confusions = seededConfusions
        for character in alphabet {
            stats[character] = seededStats[character] ?? CharacterStat(character: character)
        }
    }

    private let newCharacters: Set<Character>

    // MARK: Selección

    func weight(for character: Character) -> Double {
        let stat = stats[character] ?? CharacterStat(character: character)
        var weight = baseWeight

        // 1. Déficit de precisión: una letra al 60 % pesa mucho más que una al 95 %.
        weight += errorWeight * (1 - stat.effectiveAccuracy)

        // 2. Tirón por confusión: si el jugador responde H cuando suena S,
        //    tanto S como H suben. Así el motor mete el par junto en la cola.
        let pull = confusions.reduce(0.0) { partial, entry in
            let (pair, count) = entry
            guard pair.shown == character || pair.answered == character else { return partial }
            return partial + Double(count)
        }
        weight += confusionWeight * min(pull / 3.0, 1.5)

        // 3. Novedad: el carácter recién introducido necesita exposiciones.
        if newCharacters.contains(character), stat.attempts < 8 { weight += noveltyWeight }

        // 4. Recencia: penaliza lo visto en los últimos 2 ítems.
        let distance = itemIndex - stat.lastSeenIndex
        if distance <= 2 { weight *= recencyPenalty }

        // 5. Techo de dominio: al 90 % sostenido casi desaparece de la cola,
        //    pero nunca del todo (el repaso de fondo evita el olvido).
        if stat.attempts >= 6 && stat.accuracy >= 0.90 { weight *= 0.35 }

        return max(weight, 0.15)
    }

    /// Muestreo por ruleta ponderada.
    func nextCharacter(using generator: inout some RandomNumberGenerator) -> Character {
        let weights = alphabet.map { weight(for: $0) }
        let total = weights.reduce(0, +)
        var cursor = Double.random(in: 0..<total, using: &generator)
        for (index, weight) in weights.enumerated() {
            cursor -= weight
            if cursor <= 0 { return alphabet[index] }
        }
        return alphabet.last ?? "E"
    }

    func nextCharacter() -> Character {
        var generator = SystemRandomNumberGenerator()
        return nextCharacter(using: &generator)
    }

    // MARK: Registro

    mutating func record(shown: Character, answered: Character?, responseTime: TimeInterval) {
        itemIndex += 1
        var stat = stats[shown] ?? CharacterStat(character: shown)
        stat.attempts += 1
        stat.lastSeenIndex = itemIndex
        if answered == shown {
            stat.correct += 1
            sessionCorrect[shown, default: 0] += 1
            stat.medianResponseTime = stat.medianResponseTime == 0
                ? responseTime
                : stat.medianResponseTime * 0.7 + responseTime * 0.3
        } else if let answered {
            confusions[ConfusionPair(shown: shown, answered: answered), default: 0] += 1
        }
        stats[shown] = stat
    }

    /// Los pares que el jugador confunde más, para el resumen de fin de nivel
    /// ("Tu punto débil: A frente a N").
    func topConfusions(limit: Int = 3) -> [(ConfusionPair, Int)] {
        confusions.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    // MARK: Criterio de dominio

    func hasMastered(_ rule: MasteryRule, rollingResults: [Bool]) -> Bool {
        let window = rollingResults.suffix(rule.rollingWindow)
        guard window.count >= rule.rollingWindow else { return false }
        let accuracy = Double(window.filter { $0 }.count) / Double(window.count)
        guard accuracy >= rule.requiredAccuracy else { return false }
        // Se exige `sessionCorrect`, no `stat.correct`: el histórico sembrado
        // informa la cola, pero no aprueba el nivel por el jugador.
        for character in newCharacters {
            guard sessionCorrect[character, default: 0] >= rule.minCorrectPerNewCharacter else {
                return false
            }
        }
        return true
    }
}
