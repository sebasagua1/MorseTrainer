import Foundation

// MARK: - Símbolos

enum MorseSymbol: Character, Codable, Sendable, Hashable {
    case dit = "."
    case dah = "-"

    /// Duración en "unidades" Morse (la unidad es la duración de un punto).
    var units: Int { self == .dit ? 1 : 3 }
}

struct MorseCode: Hashable, Codable, Sendable {
    let symbols: [MorseSymbol]

    var pattern: String { String(symbols.map(\.rawValue)) }

    init(_ symbols: [MorseSymbol]) { self.symbols = symbols }

    init?(pattern: String) {
        var parsed: [MorseSymbol] = []
        for character in pattern {
            guard let symbol = MorseSymbol(rawValue: character) else { return nil }
            parsed.append(symbol)
        }
        guard !parsed.isEmpty else { return nil }
        self.symbols = parsed
    }
}

// MARK: - Alfabeto

enum MorseAlphabet {
    static let table: [Character: MorseCode] = {
        let raw: [Character: String] = [
            "A": ".-",    "B": "-...",  "C": "-.-.",  "D": "-..",   "E": ".",
            "F": "..-.",  "G": "--.",   "H": "....",  "I": "..",    "J": ".---",
            "K": "-.-",   "L": ".-..",  "M": "--",    "N": "-.",    "O": "---",
            "P": ".--.",  "Q": "--.-",  "R": ".-.",   "S": "...",   "T": "-",
            "U": "..-",   "V": "...-",  "W": ".--",   "X": "-..-",  "Y": "-.--",
            "Z": "--..",
            "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
            "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----."
        ]
        return raw.compactMapValues(MorseCode.init(pattern:))
    }()

    static let reverse: [MorseCode: Character] = {
        Dictionary(uniqueKeysWithValues: table.map { ($0.value, $0.key) })
    }()

    static func code(for character: Character) -> MorseCode? {
        table[Character(character.uppercased())]
    }

    static func character(for code: MorseCode) -> Character? { reverse[code] }

    /// Orden clásico de Koch (máxima disimilitud auditiva al principio).
    static let kochOrder: [Character] = Array("KMRSUAPTLOWI.NJEF0Y,VG5/Q9ZH38B?427C1D6X")

    /// Orden del GDD: arranca por los caracteres más cortos (E, T) y construye
    /// palabras reales lo antes posible (TEA, MEAT, TIME, NAME…).
    static let gddOrder: [Character] = Array("ETANIMSOURCDKGWHBLPJVFYXQZ")
}

// MARK: - Temporización Farnsworth

/// Farnsworth: los caracteres suenan rápido (`characterWPM`) y el silencio entre
/// ellos se estira para bajar la velocidad percibida (`effectiveWPM`).
/// Reparto del retardo extra según la derivación estándar de ARRL:
/// "PARIS " = 50 unidades, de las cuales 31 son elementos y 19 son separación.
struct FarnsworthTiming: Equatable, Sendable, Codable {
    var characterWPM: Double
    var effectiveWPM: Double

    init(characterWPM: Double, effectiveWPM: Double) {
        self.characterWPM = max(1, characterWPM)
        self.effectiveWPM = max(1, min(effectiveWPM, characterWPM))
    }

    var ditDuration: TimeInterval { 1.2 / characterWPM }
    var dahDuration: TimeInterval { 3 * ditDuration }

    /// Silencio entre elementos de un mismo carácter: siempre 1 unidad.
    var intraCharacterGap: TimeInterval { ditDuration }

    /// Retardo total repartible por palabra "PARIS " (segundos).
    private var spreadableDelay: TimeInterval {
        let wc = characterWPM, wo = effectiveWPM
        return max(0, (60 * wc - 37.2 * wo) / (wc * wo))
    }

    var interCharacterGap: TimeInterval { max(3 * ditDuration, 3 * spreadableDelay / 19) }
    var interWordGap: TimeInterval { max(7 * ditDuration, 7 * spreadableDelay / 19) }

    static let level1 = FarnsworthTiming(characterWPM: 18, effectiveWPM: 5)
    static let comfortable = FarnsworthTiming(characterWPM: 20, effectiveWPM: 10)
}

// MARK: - Línea de tiempo reproducible

/// Un tramo de señal: portadora encendida o silencio, con su duración.
/// Lo consumen por igual el audio, el Taptic Engine y la linterna.
struct MorseEvent: Equatable, Sendable {
    let isOn: Bool
    let duration: TimeInterval
    let symbol: MorseSymbol?

    static func on(_ symbol: MorseSymbol, _ duration: TimeInterval) -> MorseEvent {
        MorseEvent(isOn: true, duration: duration, symbol: symbol)
    }
    static func off(_ duration: TimeInterval) -> MorseEvent {
        MorseEvent(isOn: false, duration: duration, symbol: nil)
    }
}

extension FarnsworthTiming {
    func timeline(for code: MorseCode) -> [MorseEvent] {
        var events: [MorseEvent] = []
        for (index, symbol) in code.symbols.enumerated() {
            if index > 0 { events.append(.off(intraCharacterGap)) }
            events.append(.on(symbol, symbol == .dit ? ditDuration : dahDuration))
        }
        return events
    }

    func timeline(for text: String) -> [MorseEvent] {
        var events: [MorseEvent] = []
        let words = text.uppercased().split(separator: " ")
        for (wordIndex, word) in words.enumerated() {
            if wordIndex > 0 { events.append(.off(interWordGap)) }
            for (charIndex, character) in word.enumerated() {
                guard let code = MorseAlphabet.code(for: character) else { continue }
                if charIndex > 0 { events.append(.off(interCharacterGap)) }
                events.append(contentsOf: timeline(for: code))
            }
        }
        return events
    }

    /// Duración total del prompt: la usa el motor de puntuación para normalizar
    /// el tiempo de respuesta del jugador.
    func duration(of text: String) -> TimeInterval {
        timeline(for: text).reduce(0) { $0 + $1.duration }
    }
}
