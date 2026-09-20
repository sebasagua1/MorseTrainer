import Foundation
import SwiftData
import Testing
@testable import MorseTrainer

@Suite("Esquema y migración", .serialized)
@MainActor
struct SchemaMigrationTests {

    @Test("La versión actual está declarada")
    func versionIdentifier() {
        #expect(MorseSchemaV1.versionIdentifier == Schema.Version(1, 1, 0))
    }

    @Test("El esquema declara las cuatro entidades")
    func schemaDeclaresEveryModel() {
        let names = Set(Schema(versionedSchema: MorseSchemaV1.self).entities.map(\.name))
        #expect(names == ["PlayerProfile", "LetterRecord", "ConfusionRecord", "SessionRecord"])
    }

    /// Los alias del módulo deben apuntar a la versión que el contenedor abre.
    /// Si alguien añade una V2 y se olvida de moverlos, la app compilaría y
    /// guardaría contra un esquema distinto del que declara migrar.
    @Test("Los alias públicos apuntan a la versión que se abre")
    func aliasesTrackCurrentVersion() {
        #expect(PlayerProfile.self == MorseSchemaV1.PlayerProfile.self)
        #expect(LetterRecord.self == MorseSchemaV1.LetterRecord.self)
        #expect(ConfusionRecord.self == MorseSchemaV1.ConfusionRecord.self)
        #expect(SessionRecord.self == MorseSchemaV1.SessionRecord.self)
    }

    @Test("El plan incluye la versión actual")
    func planCoversCurrentVersion() {
        let versions = MorseMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(versions.contains(MorseSchemaV1.versionIdentifier))
    }

    /// Cada versión declarada necesita una etapa que llegue hasta ella, salvo la
    /// primera. Este test falla en cuanto alguien añada `MorseSchemaV2` a
    /// `schemas` y se olvide de la etapa correspondiente — que es exactamente el
    /// despiste que borra los datos de los usuarios.
    @Test("Hay una etapa por cada salto de versión")
    func everyVersionJumpHasAStage() {
        let versionCount = MorseMigrationPlan.schemas.count
        #expect(MorseMigrationPlan.stages.count == versionCount - 1)
    }

    @Test("Las versiones del plan van en orden ascendente")
    func versionsAreOrdered() {
        let versions = MorseMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(versions == versions.sorted())
    }

    // MARK: Apertura a través del plan

    @Test("Un contenedor abierto con el plan funciona igual")
    func containerOpensThroughPlan() throws {
        let schema = Schema(versionedSchema: MorseSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema,
                                           migrationPlan: MorseMigrationPlan.self,
                                           configurations: configuration)
        let context = ModelContext(container)
        let profile = PlayerProfile()
        profile.copper = 42
        context.insert(profile)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PlayerProfile>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.copper == 42)
    }

    /// Prueba de humo del recorrido real: escribir, cerrar y volver a abrir el
    /// mismo archivo a través del plan. Cuando exista una V2, este es el test
    /// que se duplica para el salto V1→V2 partiendo de un almacén V1 real.
    @Test("Los datos sobreviven a cerrar y reabrir el archivo")
    func dataSurvivesReopen() throws {
        let url = URL.temporaryDirectory.appending(path: "morse-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema(versionedSchema: MorseSchemaV1.self)

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: MorseMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, url: url)
            )
            let context = ModelContext(container)
            let profile = PlayerProfile()
            profile.copper = 130
            profile.streakDays = 4
            let letter = LetterRecord(symbol: "S")
            letter.attempts = 20
            letter.correct = 17
            letter.profile = profile
            context.insert(profile)
            context.insert(letter)
            try context.save()
        }

        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: MorseMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        let context = ModelContext(reopened)
        let profile = try #require(try context.fetch(FetchDescriptor<PlayerProfile>()).first)
        #expect(profile.copper == 130)
        #expect(profile.streakDays == 4)
        #expect(profile.letters.first?.symbol == "S")
        #expect(profile.letters.first?.attempts == 20)
    }

    @Test("El borrado en cascada se lleva los registros del perfil")
    func cascadeDeleteWorks() throws {
        let schema = Schema(versionedSchema: MorseSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: MorseMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let profile = PlayerProfile()
        let letter = LetterRecord(symbol: "E")
        letter.profile = profile
        context.insert(profile)
        context.insert(letter)
        try context.save()

        context.delete(profile)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<LetterRecord>()).isEmpty)
    }
}
