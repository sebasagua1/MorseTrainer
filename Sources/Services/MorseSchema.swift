import Foundation
import SwiftData

// MARK: - Versión 1

/// Los modelos viven **dentro** de la versión del esquema, no sueltos en el
/// módulo: es lo que permitirá que dos versiones coexistan el día que haga
/// falta una migración de verdad.
///
/// ⚠️ Cuidado al crear esa segunda versión. Duplicar las clases en un
/// `MorseSchemaV2` dentro del mismo módulo hace que ambas generen la entidad
/// `PlayerProfile`; SwiftData resuelve la clase por nombre de entidad, elige la
/// que no toca y revienta al leer:
///
///     Fatal error: Failed to cast model MorseSchemaV2.PlayerProfile …
///
/// Solo merece la pena pagar ese precio para cambios **destructivos**
/// (renombrar, cambiar de tipo, repartir datos). Añadir propiedades con valor
/// por defecto, como hizo la tienda, es aditivo y SwiftData lo migra solo.
enum MorseSchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 1, 0) }

    static var models: [any PersistentModel.Type] {
        [PlayerProfile.self, LetterRecord.self, ConfusionRecord.self, SessionRecord.self]
    }

    @Model
    final class PlayerProfile {
        var highestUnlockedLevel: Int = 1
        var copper: Int = 0
        var streakDays: Int = 0
        /// Último día jugado, normalizado a medianoche local.
        var lastPlayedDay: Date?
        var totalDrills: Int = 0
        var createdAt: Date = Date()

        // Tienda. Con valor por defecto: así SwiftData migra los almacenes ya
        // instalados sin plan explícito — un cambio aditivo es ligero por
        // definición y los perfiles existentes arrancan sin nada comprado.
        var ownedCosmetics: [String] = []
        var selectedThemeID: String = ""
        var selectedSoundBankID: String = ""

        @Relationship(deleteRule: .cascade, inverse: \LetterRecord.profile)
        var letters: [LetterRecord] = []

        @Relationship(deleteRule: .cascade, inverse: \ConfusionRecord.profile)
        var confusions: [ConfusionRecord] = []

        @Relationship(deleteRule: .cascade, inverse: \SessionRecord.profile)
        var sessions: [SessionRecord] = []

        init() {}
    }

    /// Historial de por vida de un carácter. `symbol` es `String` y no
    /// `Character` porque SwiftData solo persiste tipos `Codable`.
    @Model
    final class LetterRecord {
        var symbol: String = ""
        var attempts: Int = 0
        var correct: Int = 0
        var medianResponseTime: Double = 0
        var lastPracticed: Date = Date()
        var profile: PlayerProfile?

        init(symbol: String) { self.symbol = symbol }

        var character: Character? { symbol.first }
        var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
    }

    @Model
    final class ConfusionRecord {
        var shown: String = ""
        var answered: String = ""
        var count: Int = 0
        var lastSeen: Date = Date()
        var profile: PlayerProfile?

        init(shown: String, answered: String) {
            self.shown = shown
            self.answered = answered
        }
    }

    @Model
    final class SessionRecord {
        var levelID: Int = 0
        var date: Date = Date()
        var accuracy: Double = 0
        var copperEarned: Int = 0
        var mastered: Bool = false
        var medianResponseTime: Double = 0
        var profile: PlayerProfile?

        init(levelID: Int) { self.levelID = levelID }
    }
}

// MARK: - Versión actual

/// El resto de la app usa estos nombres y nunca `MorseSchemaV2.…`. Al publicar
/// una V3, estos alias se mueven y no hay que tocar ni una línea fuera de aquí.
typealias PlayerProfile = MorseSchemaV1.PlayerProfile
typealias LetterRecord = MorseSchemaV1.LetterRecord
typealias ConfusionRecord = MorseSchemaV1.ConfusionRecord
typealias SessionRecord = MorseSchemaV1.SessionRecord

// MARK: - Plan de migración

/// Con una sola versión el plan está vacío, y eso es correcto: lo que importa es
/// que el contenedor ya se abre **a través** del plan. Añadir la V2 será editar
/// dos arrays; si el plan no existiera, habría que reescribir la construcción
/// del contenedor con una base de usuarios ya instalada, que es justo el momento
/// en que no se quiere tocar eso.
///
/// ## Cómo añadir una versión
///
/// 1. Copiar `MorseSchemaV1` a `MorseSchemaV2`, subir el `versionIdentifier` y
///    hacer el cambio **solo en la V2**. La V1 queda congelada para siempre: es
///    la descripción de lo que hay en los discos ya instalados.
/// 2. Mover los `typealias` de arriba a `MorseSchemaV2`.
/// 3. Añadir `MorseSchemaV2.self` a `schemas` y la etapa a `stages`:
///
///    ```swift
///    static let v1ToV2 = MigrationStage.lightweight(
///        fromVersion: MorseSchemaV1.self,
///        toVersion: MorseSchemaV2.self
///    )
///    ```
///
/// `lightweight` cubre añadir una propiedad con valor por defecto, quitarla, o
/// hacerla opcional. **No** cubre renombrar, cambiar de tipo ni redistribuir
/// datos entre entidades: eso pide `MigrationStage.custom(…)` con sus bloques
/// `willMigrate` / `didMigrate`, y ahí es obligatorio escribir un test que
/// arranque de un almacén V1 real y verifique que no se pierde nada.
enum MorseMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [MorseSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
