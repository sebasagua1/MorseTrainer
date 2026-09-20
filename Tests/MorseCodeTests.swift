import Testing
@testable import MorseTrainer

@Suite("Alfabeto Morse")
struct MorseAlphabetTests {

    @Test("La tabla es biyectiva: ningún patrón se repite")
    func tableIsBijective() {
        #expect(MorseAlphabet.table.count == MorseAlphabet.reverse.count)
        #expect(MorseAlphabet.table.count == 36)   // 26 letras + 10 dígitos
    }

    @Test("Cada carácter vuelve a sí mismo tras codificar y decodificar")
    func roundTrip() {
        for (character, code) in MorseAlphabet.table {
            #expect(MorseAlphabet.character(for: code) == character)
        }
    }

    @Test("Patrones canónicos conocidos")
    func knownPatterns() {
        #expect(MorseAlphabet.code(for: "S")?.pattern == "...")
        #expect(MorseAlphabet.code(for: "O")?.pattern == "---")
        #expect(MorseAlphabet.code(for: "H")?.pattern == "....")
        #expect(MorseAlphabet.code(for: "0")?.pattern == "-----")
    }

    @Test("Se acepta minúscula")
    func lowercaseIsAccepted() {
        #expect(MorseAlphabet.code(for: "s")?.pattern == "...")
    }

    @Test("Un patrón inválido no produce código")
    func invalidPattern() {
        #expect(MorseCode(pattern: "..x") == nil)
        #expect(MorseCode(pattern: "") == nil)
    }

    @Test("El orden del GDD cubre las 26 letras sin repetir")
    func gddOrderIsComplete() {
        #expect(MorseAlphabet.gddOrder.count == 26)
        #expect(Set(MorseAlphabet.gddOrder).count == 26)
    }
}

@Suite("Temporización Farnsworth")
struct FarnsworthTimingTests {

    /// La prueba de fuego de la fórmula ARRL: "PARIS " son 50 unidades, de las
    /// cuales 31 son elementos y 19 separación. A velocidad plena, una palabra
    /// completa debe durar exactamente 60/WPM segundos.
    @Test("PARIS dura 60/WPM a velocidad plena")
    func parisAtFullSpeed() {
        let timing = FarnsworthTiming(characterWPM: 20, effectiveWPM: 20)
        // duration(of:) no añade el silencio final de palabra, así que se suma.
        let paris = timing.duration(of: "PARIS") + timing.interWordGap
        #expect(abs(paris - 3.0) < 0.0001)
    }

    /// Y el punto entero de Farnsworth: con caracteres a 18 WPM y velocidad
    /// efectiva de 5, "PARIS " debe durar 60/5 = 12 s exactos. Si el reparto
    /// del retardo entre letras y palabras estuviera mal, esto fallaría.
    @Test("PARIS dura 60/efectiva con Farnsworth")
    func parisWithFarnsworth() {
        let timing = FarnsworthTiming(characterWPM: 18, effectiveWPM: 5)
        let paris = timing.duration(of: "PARIS") + timing.interWordGap
        #expect(abs(paris - 12.0) < 0.0001)
    }

    @Test("Los elementos no se ralentizan: solo se estiran los silencios")
    func charactersStayFast() {
        let fast = FarnsworthTiming(characterWPM: 18, effectiveWPM: 18)
        let slow = FarnsworthTiming(characterWPM: 18, effectiveWPM: 5)
        #expect(fast.ditDuration == slow.ditDuration)
        #expect(slow.interCharacterGap > fast.interCharacterGap)
        #expect(slow.interWordGap > fast.interWordGap)
    }

    @Test("Una raya dura tres puntos y el silencio interno, uno")
    func elementRatios() {
        let timing = FarnsworthTiming(characterWPM: 20, effectiveWPM: 10)
        #expect(abs(timing.dahDuration - 3 * timing.ditDuration) < 1e-12)
        #expect(timing.intraCharacterGap == timing.ditDuration)
    }

    @Test("Una efectiva mayor que la de carácter se recorta en vez de romper")
    func effectiveIsClamped() {
        let timing = FarnsworthTiming(characterWPM: 15, effectiveWPM: 30)
        #expect(timing.effectiveWPM == 15)
        // Sin el recorte, el retardo repartible sería negativo y los silencios
        // saldrían más cortos que el mínimo legal de 3 y 7 unidades.
        #expect(timing.interCharacterGap >= 3 * timing.ditDuration)
        #expect(timing.interWordGap >= 7 * timing.ditDuration)
    }

    @Test("La línea de tiempo alterna señal y silencio sin huecos")
    func timelineStructure() {
        let timing = FarnsworthTiming(characterWPM: 20, effectiveWPM: 20)
        let events = timing.timeline(for: MorseCode(pattern: "-.-")!)
        #expect(events.count == 5)                     // 3 elementos + 2 silencios
        #expect(events.map(\.isOn) == [true, false, true, false, true])
        #expect(events.allSatisfy { $0.duration > 0 })
    }
}

@Suite("Plan de niveles")
struct LevelPlanTests {

    @Test("Cada nivel añade lo suyo al alfabeto acumulado")
    func alphabetAccumulates() {
        var seen: [Character] = []
        for level in LevelPlan.levels {
            seen.append(contentsOf: level.newCharacters)
            #expect(level.activeAlphabet == seen)
        }
    }

    @Test("Ningún carácter se enseña dos veces")
    func noDuplicateTeaching() {
        let taught = LevelPlan.levels.flatMap(\.newCharacters)
        #expect(Set(taught).count == taught.count)
    }

    @Test("El plan cubre las 26 letras y los 10 dígitos")
    func planIsComplete() {
        let taught = Set(LevelPlan.levels.flatMap(\.newCharacters))
        #expect(taught == Set(MorseAlphabet.table.keys))
    }

    @Test("Todo carácter enseñado existe en la tabla Morse")
    func everyCharacterIsEncodable() {
        for level in LevelPlan.levels {
            for character in level.newCharacters {
                #expect(MorseAlphabet.code(for: character) != nil)
            }
        }
    }

    @Test("La velocidad de carácter nunca baja (principio de Koch)")
    func characterSpeedNeverDrops() {
        var previous = 0.0
        for level in LevelPlan.levels {
            #expect(level.timing.characterWPM >= previous)
            previous = level.timing.characterWPM
        }
    }

    @Test("La velocidad efectiva nunca baja y nunca supera la de carácter")
    func effectiveSpeedIsMonotonic() {
        var previous = 0.0
        for level in LevelPlan.levels {
            #expect(level.timing.effectiveWPM >= previous)
            #expect(level.timing.effectiveWPM <= level.timing.characterWPM)
            previous = level.timing.effectiveWPM
        }
    }

    @Test("El nivel cabe en sus propios ítems")
    func masteryIsAchievable() {
        for level in LevelPlan.levels {
            // Aciertos exigidos por caracteres nuevos + ventana de precisión no
            // pueden pedir más respuestas de las que el nivel llega a presentar.
            let required = level.mastery.minCorrectPerNewCharacter * level.newCharacters.count
            #expect(required <= level.drillCount)
            #expect(level.mastery.rollingWindow <= level.drillCount)
        }
    }

    @Test("Las rondas de palabra no se comen el nivel entero")
    func wordRoundsLeaveRoom() {
        for level in LevelPlan.levels {
            #expect(level.mix.wordRounds < level.drillCount / 2)
        }
    }

    @Test("Hay palabras jugables en cuanto se anuncian rondas de palabra")
    func wordBankCoversWordRounds() {
        for level in LevelPlan.levels where level.mix.wordRounds > 0 {
            let available = LevelPlan.words(for: level.activeAlphabet)
            #expect(!available.isEmpty, "Nivel \(level.id) pide palabras y no hay ninguna")
        }
    }

    @Test("Todas las palabras del banco son transmisibles")
    func wordBankIsEncodable() {
        for word in LevelPlan.wordBank {
            for character in word {
                #expect(MorseAlphabet.code(for: character) != nil, "\(word) contiene \(character)")
            }
        }
    }
}
