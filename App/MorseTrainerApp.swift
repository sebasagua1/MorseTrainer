import SwiftUI

@main
struct MorseTrainerApp: App {
    /// Un único `PersistenceStore` para toda la app. No usa el modificador
    /// `.modelContainer(...)`: el store envuelve el contenedor con la lógica de
    /// fusión y racha, y las vistas nunca tocan el `ModelContext` a pelo.
    @State private var store = PersistenceStore(inMemory: Self.isRunningTests)

    /// Bajo pruebas, la app anfitriona también arranca. Sin esto abriría el
    /// almacén de disco real: ensucia el log con errores de CoreData mientras
    /// el contenedor aún no está provisionado y, peor, deja que una ejecución
    /// de tests escriba en los datos del simulador.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        WindowGroup {
            MapView(store: store)
        }
    }
}
