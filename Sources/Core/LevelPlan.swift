import Foundation

// MARK: - Modelo de nivel

struct DrillMix: Equatable, Sendable, Codable {
    /// Proporción de ejercicios de recepción (el resto son de transmisión).
    var receptionShare: Double
    /// Rondas de palabra completa al final del nivel (0 = ninguna).
    var wordRounds: Int
}

struct MasteryRule: Equatable, Sendable, Codable {
    /// Ventana móvil sobre la que se mide la precisión.
    var rollingWindow: Int
    /// Precisión mínima en esa ventana para desbloquear el siguiente nivel.
    var requiredAccuracy: Double
    /// Aciertos mínimos de *cada* carácter nuevo (evita aprobar por suerte).
    var minCorrectPerNewCharacter: Int
    /// Mediana de tiempo de respuesta exigida en recepción.
    var medianResponseTime: TimeInterval
}

struct Level: Identifiable, Sendable {
    let id: Int
    let world: Int
    let worldTitle: String
    let title: String
    let newCharacters: [Character]
    let activeAlphabet: [Character]
    let timing: FarnsworthTiming
    /// Ítems que se presentan en una pasada del nivel.
    let drillCount: Int
    let mix: DrillMix
    let mastery: MasteryRule
    let hearts: Int
    let copperReward: Int
    let unlockNote: String

    var isWorldFinale: Bool { id % 5 == 0 }
}

// MARK: - Plan de progresión

/// Nota de diseño: el Koch clásico empieza por K y M porque son largos y
/// máximamente disímiles; E y T son los más cortos y tientan a *contar*
/// elementos en vez de reconocer el ritmo. El GDD pide E/T, así que se respeta,
/// pero se compensa manteniendo la velocidad de carácter siempre alta (nunca
/// baja de 18 WPM) y metiendo caracteres de 2–3 elementos desde el nivel 2.
///
/// Cada nivel introduce deliberadamente **un par confundible** con algo ya
/// aprendido. Esa es toda la columna vertebral del plan: el orden no lo marca
/// la frecuencia de uso, lo marca qué confusión toca resolver a continuación.
enum LevelPlan {

    // MARK: Planos

    private struct Blueprint {
        let newCharacters: [Character]
        let title: String
        let world: Int
        let characterWPM: Double
        let effectiveWPM: Double
        let note: String
    }

    static let worldTitles: [Int: String] = [
        1: "Los átomos",
        2: "El ritmo",
        3: "Cuerpo",
        4: "Cierre del alfabeto",
        5: "Los raros",
        6: "Números"
    ]

    private static let blueprints: [Blueprint] = [
        // ── Mundo I ── E T A N I M
        .init(newCharacters: ["E", "T"], title: "Los dos átomos", world: 1,
              characterWPM: 18, effectiveWPM: 5,
              note: "Teclado de 2 teclas. Presenta la háptica: punto = impacto seco, raya = vibración sostenida."),
        .init(newCharacters: ["A"], title: "El primer ritmo", world: 1,
              characterWPM: 18, effectiveWPM: 6,
              note: "Primer carácter de 2 elementos. Ronda de palabra: EAT, ATE, TEA."),
        .init(newCharacters: ["N"], title: "El espejo", world: 1,
              characterWPM: 18, effectiveWPM: 7,
              note: "A (.-) frente a N (-.): el primer par espejo. El motor de confusión lo vigila desde el ítem 1."),
        .init(newCharacters: ["I"], title: "Dobles", world: 1,
              characterWPM: 20, effectiveWPM: 8,
              note: "E (.) frente a I (..) fuerza a oír la separación, no a contar."),
        .init(newCharacters: ["M"], title: "Cierre del mundo I", world: 1,
              characterWPM: 20, effectiveWPM: 9,
              note: "T (-) frente a M (--) e I frente a M cierran los pares difíciles. Primer tema cosmético."),

        // ── Mundo II ── S O U R C
        .init(newCharacters: ["S"], title: "Tres puntos", world: 2,
              characterWPM: 20, effectiveWPM: 10,
              note: "S (...) frente a I (..): la escalera de puntos empieza aquí y no se cierra hasta la H."),
        .init(newCharacters: ["O"], title: "Tres rayas", world: 2,
              characterWPM: 20, effectiveWPM: 10,
              note: "O (---) frente a M (--). Simétrico de la S: misma trampa, otro elemento."),
        .init(newCharacters: ["U"], title: "Subida", world: 2,
              characterWPM: 20, effectiveWPM: 11,
              note: "U (..-) frente a A (.-) e I (..). Primer carácter que combina los dos elementos en 3 tiempos."),
        .init(newCharacters: ["R"], title: "Sándwich", world: 2,
              characterWPM: 22, effectiveWPM: 11,
              note: "R (.-.) frente a A y N: el mismo material, otro orden. Aquí se rompe el contar."),
        .init(newCharacters: ["C"], title: "Cierre del mundo II", world: 2,
              characterWPM: 22, effectiveWPM: 12,
              note: "C (-.-.) es el primer carácter de 4 elementos alternos. Frente a R y a N."),

        // ── Mundo III ── D K G W H
        .init(newCharacters: ["D"], title: "Cuesta abajo", world: 3,
              characterWPM: 22, effectiveWPM: 12,
              note: "D (-..) frente a N (-.) y U (..-). El reverso exacto de la U."),
        .init(newCharacters: ["K"], title: "La llave", world: 3,
              characterWPM: 22, effectiveWPM: 13,
              note: "K (-.-) frente a C (-.-.) y R (.-.). Koch empezaba aquí por algo: es el patrón más nítido."),
        .init(newCharacters: ["G"], title: "Grave", world: 3,
              characterWPM: 22, effectiveWPM: 13,
              note: "G (--.) frente a M (--) y O (---). La familia de las rayas se llena."),
        .init(newCharacters: ["W"], title: "Cuesta arriba", world: 3,
              characterWPM: 22, effectiveWPM: 14,
              note: "W (.--) frente a A (.-) y M. Espejo de la G."),
        .init(newCharacters: ["H"], title: "Cierre del mundo III", world: 3,
              characterWPM: 25, effectiveWPM: 14,
              note: "H (....) frente a S (...) e I: la confusión clásica del Morse. Si algo va a costar, es esto."),

        // ── Mundo IV ── B L P J V
        .init(newCharacters: ["B"], title: "Peso", world: 4,
              characterWPM: 25, effectiveWPM: 15,
              note: "B (-...) frente a D (-..) y S. Reverso de la V, que aún no ha salido."),
        .init(newCharacters: ["L"], title: "Hueco", world: 4,
              characterWPM: 25, effectiveWPM: 15,
              note: "L (.-..) frente a R (.-.) y F. Una raya rodeada de puntos."),
        .init(newCharacters: ["P"], title: "Encerrado", world: 4,
              characterWPM: 25, effectiveWPM: 16,
              note: "P (.--.) frente a W (.--) y L. Dos rayas encerradas entre puntos."),
        .init(newCharacters: ["J"], title: "Despegue", world: 4,
              characterWPM: 25, effectiveWPM: 16,
              note: "J (.---) frente a W y O. El más largo de los que empiezan por punto."),
        .init(newCharacters: ["V"], title: "Cierre del mundo IV", world: 4,
              characterWPM: 25, effectiveWPM: 17,
              note: "V (...-) frente a U (..-), S y H. Cierra la escalera de puntos empezada en el nivel 6."),

        // ── Mundo V ── F Y X Q Z
        .init(newCharacters: ["F"], title: "Casi L", world: 5,
              characterWPM: 25, effectiveWPM: 17,
              note: "F (..-.) frente a L (.-..) y U. Los mismos cuatro elementos, la raya movida un sitio."),
        .init(newCharacters: ["Y"], title: "Bandera", world: 5,
              characterWPM: 25, effectiveWPM: 18,
              note: "Y (-.--) frente a K (-.-) y M. Empieza la familia de los distintivos de llamada."),
        .init(newCharacters: ["X"], title: "Simetría", world: 5,
              characterWPM: 25, effectiveWPM: 18,
              note: "X (-..-) frente a D, K y B. Palíndromo: el orden ya no ayuda, solo el ritmo."),
        .init(newCharacters: ["Q"], title: "Cadencia", world: 5,
              characterWPM: 25, effectiveWPM: 19,
              note: "Q (--.-) frente a G (--.) y Y. La cadencia del QRZ, QTH, QSL."),
        .init(newCharacters: ["Z"], title: "Alfabeto completo", world: 5,
              characterWPM: 25, effectiveWPM: 20,
              note: "Z (--..) frente a G y B. Con esto están las 26 letras. Recompensa grande."),

        // ── Mundo VI ── dígitos, de dos en dos
        .init(newCharacters: ["5", "0"], title: "Los extremos", world: 6,
              characterWPM: 25, effectiveWPM: 20,
              note: "5 (.....) y 0 (-----) son los anclajes: cinco iguales. Todo lo demás se cuenta desde aquí."),
        .init(newCharacters: ["1", "9"], title: "Los vecinos", world: 6,
              characterWPM: 25, effectiveWPM: 20,
              note: "1 (.----) y 9 (----.) son 5 y 0 con un elemento cambiado en los bordes."),
        .init(newCharacters: ["2", "8"], title: "Dos y ocho", world: 6,
              characterWPM: 25, effectiveWPM: 21,
              note: "2 (..---) y 8 (---..). El patrón ya es evidente: los dígitos son una rampa."),
        .init(newCharacters: ["3", "7"], title: "Tres y siete", world: 6,
              characterWPM: 25, effectiveWPM: 22,
              note: "3 (...--) y 7 (--...). Aquí el jugador ya predice en vez de memorizar."),
        .init(newCharacters: ["4", "6"], title: "Cierre", world: 6,
              characterWPM: 25, effectiveWPM: 22,
              note: "4 (....-) y 6 (-....) completan la rampa. Alfabeto y números al 25/22 WPM.")
    ]

    // MARK: Parámetros derivados
    //
    // Se derivan en vez de escribirse a mano nivel a nivel: con 30 niveles, una
    // tabla literal se desincroniza a la primera vez que se retoca una curva.
    // Lo que sí es literal es lo que constituye diseño: orden de letras,
    // velocidades y qué confusión introduce cada nivel.

    /// La sesión crece con el alfabeto, pero con tope: pasados ~2 minutos la
    /// atención cae y la precisión deja de medir aprendizaje.
    private static func drillCount(alphabetSize: Int) -> Int {
        min(30, 22 + alphabetSize)
    }

    /// Se empieza escuchando (es lo que enseña el oído) y se va equilibrando
    /// hacia la transmisión, que es lo que fija el ritmo en la mano.
    private static func mix(levelID: Int, alphabetSize: Int) -> DrillMix {
        let reception = levelID == 1 ? 0.75 : max(0.50, 0.65 - 0.03 * Double(levelID - 2))
        let wordRounds = alphabetSize < 3 ? 0 : min(4, 1 + (alphabetSize - 3) / 5)
        return DrillMix(receptionShare: reception, wordRounds: wordRounds)
    }

    private static func mastery(levelID: Int, newCount: Int, alphabetSize: Int) -> MasteryRule {
        // Niveles con 2 caracteres nuevos (los de dígitos) piden algo menos por
        // carácter: si no, el nivel no cabría en su propio número de ítems.
        let perCharacter = levelID == 1 ? 8 : (newCount > 1 ? 5 : 6)
        return MasteryRule(
            rollingWindow: min(24, 20 + alphabetSize / 6),
            requiredAccuracy: levelID % 5 == 0 ? 0.92 : 0.90,
            minCorrectPerNewCharacter: perCharacter,
            medianResponseTime: max(1.2, 3.0 - 0.18 * Double(levelID - 1))
        )
    }

    private static func reward(levelID: Int, world: Int) -> Int {
        if levelID == 1 { return 40 }
        return levelID % 5 == 0 ? 60 + world * 5 : 25 + world * 5
    }

    // MARK: Construcción

    static let levels: [Level] = {
        var alphabet: [Character] = []
        return blueprints.enumerated().map { index, blueprint in
            alphabet.append(contentsOf: blueprint.newCharacters)
            let id = index + 1
            return Level(
                id: id,
                world: blueprint.world,
                worldTitle: worldTitles[blueprint.world] ?? "",
                title: blueprint.title,
                newCharacters: blueprint.newCharacters,
                activeAlphabet: alphabet,
                timing: FarnsworthTiming(characterWPM: blueprint.characterWPM,
                                         effectiveWPM: blueprint.effectiveWPM),
                drillCount: drillCount(alphabetSize: alphabet.count),
                mix: mix(levelID: id, alphabetSize: alphabet.count),
                mastery: mastery(levelID: id, newCount: blueprint.newCharacters.count,
                                 alphabetSize: alphabet.count),
                hearts: 3,
                copperReward: reward(levelID: id, world: blueprint.world),
                unlockNote: blueprint.note
            )
        }
    }()

    static func level(id: Int) -> Level? { levels.first { $0.id == id } }

    static var worlds: [Int] { Array(Set(levels.map(\.world))).sorted() }

    static func levels(inWorld world: Int) -> [Level] {
        levels.filter { $0.world == world }
    }

    // MARK: Banco de palabras

    /// Vocabulario de las rondas de palabra. Está en inglés porque es la lengua
    /// franca del Morse (distintivos, Q-codes, tráfico internacional); si se
    /// localiza la app, esta lista se localiza aparte de la interfaz.
    static let wordBank: [String] = [
        // ETANIM
        "EAT", "ATE", "TEA", "TAN", "NET", "TEN", "ANT", "MAN", "MEN", "AIM",
        "MINE", "TIME", "ITEM", "MEAT", "MAIN", "NAME", "TAME", "MEAN", "MINT", "EMIT",
        // + S O U R C
        "SUN", "SON", "SIT", "SET", "SEA", "USE", "OUR", "OUT", "ONE", "RUN",
        "CAT", "CAN", "CUT", "ICE", "NICE", "ONCE", "SAME", "SOON", "MOON", "NOTE",
        "STONE", "SOURCE", "REASON", "CUSTOM", "MONSTER", "ROMANCE", "COSTUME",
        // + D K G W H
        "DOG", "DAY", "AND", "END", "OLD", "KIT", "ASK", "GAS", "BIG", "WIN",
        "NEW", "HOT", "HAS", "THE", "THAT", "WITH", "WHEN", "HAND", "WIND", "SONG",
        "NIGHT", "WATCH", "THOUGHT", "MACHINE", "STRENGTH",
        // + B L P J V
        "BAD", "BUS", "LOT", "TOP", "JOB", "VAN", "ABLE", "BEST", "PLAN", "JUMP",
        "LOVE", "VOICE", "PEOPLE", "PROBLEM", "JOURNAL", "VARIABLE",
        // + F Y X Q Z
        "FOR", "FLY", "BOX", "ZIP", "FACT", "YEAR", "QUIT", "MIXED", "QUARTZ", "FREQUENCY"
    ]

    static func words(for alphabet: [Character]) -> [String] {
        let allowed = Set(alphabet)
        return wordBank.filter { !$0.isEmpty && $0.allSatisfy(allowed.contains) }
    }
}
