import Foundation
import SwiftData
import Testing
@testable import MorseTrainer

@Suite("Cosméticos")
struct CosmeticCatalogTests {

    @Test("Los identificadores no se repiten entre temas y bancos")
    func idsAreUnique() {
        let ids = Theme.all.map(\.id) + SoundBank.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Hay exactamente un tema y un banco gratuitos")
    func exactlyOneFreeOfEach() {
        #expect(Theme.all.filter { $0.price == 0 }.count == 1)
        #expect(SoundBank.all.filter { $0.price == 0 }.count == 1)
        #expect(Theme.all.first { $0.price == 0 }?.id == Theme.classic.id)
        #expect(SoundBank.all.first { $0.price == 0 }?.id == SoundBank.sine.id)
    }

    @Test("Un identificador desconocido cae en el gratuito, no revienta")
    func unknownIDFallsBack() {
        #expect(Theme.theme(id: "no.existe").id == Theme.classic.id)
        #expect(SoundBank.bank(id: "no.existe").id == SoundBank.sine.id)
    }

    @Test("Todo lo de pago tiene precio positivo y descripción")
    func purchasablesAreWellFormed() {
        for id in Theme.all.map(\.id) + SoundBank.all.map(\.id) {
            #expect(CosmeticCatalog.price(of: id) != nil)
        }
        for theme in Theme.all where theme.price > 0 { #expect(!theme.detail.isEmpty) }
        for bank in SoundBank.all where bank.price > 0 { #expect(!bank.detail.isEmpty) }
    }

    // MARK: Timbre

    /// Si un banco solo cambiara la frecuencia no sería un cosmético: sería el
    /// mismo pitido más agudo. Cada uno tiene que sonar distinto de verdad.
    @Test("Cada banco tiene un timbre distinto")
    func banksSoundDifferent() {
        let phases = stride(from: 0.0, to: 2 * .pi, by: 0.1)
        for (a, b) in [(SoundBank.sine, SoundBank.military),
                       (SoundBank.sine, SoundBank.eightBit),
                       (SoundBank.military, SoundBank.eightBit)] {
            let difference = phases.map { abs(a.sample(phase: $0) - b.sample(phase: $0)) }.max() ?? 0
            #expect(difference > 0.05, "\(a.name) y \(b.name) suenan igual")
        }
    }

    @Test("La onda senoidal es una senoide pura")
    func sineIsSine() {
        for phase in stride(from: 0.0, to: 2 * .pi, by: 0.2) {
            #expect(abs(SoundBank.sine.sample(phase: phase) - sin(phase)) < 1e-9)
        }
    }

    /// Una muestra fuera de [-1, 1] satura el búfer y suena a distorsión.
    @Test("Ningún banco se sale del rango de la muestra")
    func samplesStayNormalized() {
        for bank in SoundBank.all {
            for phase in stride(from: 0.0, to: 4 * .pi, by: 0.01) {
                let value = bank.sample(phase: phase)
                #expect(value >= -1.0001 && value <= 1.0001, "\(bank.name): \(value)")
            }
        }
    }

    @Test("Las frecuencias de los bancos son audibles")
    func frequenciesAreAudible() {
        for bank in SoundBank.all {
            #expect(bank.frequency >= 300 && bank.frequency <= 1200)
        }
    }
}

@Suite("Tienda", .serialized)
@MainActor
struct ShopTests {

    private func store(copper: Int) -> PersistenceStore {
        let store = PersistenceStore(inMemory: true)
        store.profile().copper = copper
        return store
    }

    @Test("Lo gratuito se tiene desde el principio y va puesto")
    func freeIsOwnedFromTheStart() {
        let sut = store(copper: 0)
        #expect(sut.owns(Theme.classic.id))
        #expect(sut.owns(SoundBank.sine.id))
        #expect(sut.selectedTheme.id == Theme.classic.id)
        #expect(sut.selectedSoundBank.id == SoundBank.sine.id)
    }

    @Test("Comprar descuenta el cobre exacto y añade el objeto")
    func buyingDeducts() {
        let sut = store(copper: 500)
        #expect(sut.buy(Theme.neon.id))
        #expect(sut.copper == 500 - Theme.neon.price)
        #expect(sut.owns(Theme.neon.id))
    }

    @Test("Sin cobre suficiente no se compra ni se cobra")
    func cannotBuyWithoutCopper() {
        let sut = store(copper: 10)
        #expect(sut.buy(Theme.copper.id) == false)
        #expect(sut.copper == 10)
        #expect(!sut.owns(Theme.copper.id))
    }

    @Test("Comprar dos veces no cobra dos veces")
    func noDoubleCharge() {
        let sut = store(copper: 500)
        #expect(sut.buy(SoundBank.military.id))
        let after = sut.copper
        #expect(sut.buy(SoundBank.military.id) == false)
        #expect(sut.copper == after)
    }

    @Test("Un identificador inventado no compra nada")
    func unknownPurchaseIsRejected() {
        let sut = store(copper: 500)
        #expect(sut.buy("theme.inventado") == false)
        #expect(sut.copper == 500)
    }

    @Test("Poner algo que no se tiene no hace nada")
    func cannotSelectUnowned() {
        let sut = store(copper: 0)
        #expect(sut.select(Theme.neon.id) == false)
        #expect(sut.selectedTheme.id == Theme.classic.id)
    }

    @Test("Temas y bancos se ponen en su propia ranura, sin pisarse")
    func slotsAreIndependent() {
        let sut = store(copper: 1000)
        sut.buy(Theme.typewriter.id); sut.select(Theme.typewriter.id)
        sut.buy(SoundBank.eightBit.id); sut.select(SoundBank.eightBit.id)

        #expect(sut.selectedTheme.id == Theme.typewriter.id)
        #expect(sut.selectedSoundBank.id == SoundBank.eightBit.id)
    }

    /// Si un cosmético desapareciera del catálogo, el perfil apuntaría a algo
    /// inexistente. Debe caer en lo gratuito, no dejar la app sin tema.
    @Test("Un cosmético fantasma cae en el gratuito")
    func danglingSelectionFallsBack() {
        let sut = store(copper: 0)
        sut.profile().selectedThemeID = "theme.borrado"
        sut.profile().selectedSoundBankID = "bank.borrado"
        #expect(sut.selectedTheme.id == Theme.classic.id)
        #expect(sut.selectedSoundBank.id == SoundBank.sine.id)
    }

    @Test("Se puede comprar todo el catálogo con cobre de sobra")
    func wholeCatalogIsPurchasable() {
        let total = Theme.all.map(\.price).reduce(0, +) + SoundBank.all.map(\.price).reduce(0, +)
        let sut = store(copper: total)
        for id in Theme.all.map(\.id) + SoundBank.all.map(\.id) where !sut.owns(id) {
            #expect(sut.buy(id), "no se pudo comprar \(id)")
        }
        #expect(sut.copper == 0)
    }
}

@Suite("Esquema con la tienda", .serialized)
@MainActor
struct SchemaWithShopTests {

    @Test("La versión del esquema subió al añadir la tienda")
    func versionBumped() {
        #expect(MorseSchemaV1.versionIdentifier == Schema.Version(1, 1, 0))
    }

    /// Los campos de la tienda son aditivos y con valor por defecto, que es lo
    /// que permite que SwiftData migre solo los almacenes ya instalados. Si
    /// alguien les quita el valor por defecto, esto deja de ser cierto.
    @Test("Un perfil recién creado trae los campos de tienda vacíos")
    func newProfileHasEmptyShopFields() throws {
        let schema = Schema(versionedSchema: MorseSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: MorseMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let profile = PlayerProfile()
        context.insert(profile)
        try context.save()

        #expect(profile.ownedCosmetics.isEmpty)
        #expect(profile.selectedThemeID.isEmpty)
        #expect(profile.selectedSoundBankID.isEmpty)
    }

    @Test("Las compras sobreviven a cerrar y reabrir el archivo")
    func purchasesSurviveReopen() throws {
        let url = URL.temporaryDirectory.appending(path: "tienda-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let schema = Schema(versionedSchema: MorseSchemaV1.self)

        do {
            let container = try ModelContainer(
                for: schema, migrationPlan: MorseMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let profile = PlayerProfile()
            profile.ownedCosmetics = [Theme.neon.id, SoundBank.eightBit.id]
            profile.selectedThemeID = Theme.neon.id
            context.insert(profile)
            try context.save()
        }

        let container = try ModelContainer(
            for: schema, migrationPlan: MorseMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        let profile = try #require(try context.fetch(FetchDescriptor<PlayerProfile>()).first)
        #expect(profile.ownedCosmetics.contains(Theme.neon.id))
        #expect(profile.selectedThemeID == Theme.neon.id)
    }
}
