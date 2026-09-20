import SwiftUI

@main
struct MorseTrainerApp: App {
    /// Un único `PersistenceStore` para toda la app. No usa el modificador
    /// `.modelContainer(...)`: el store envuelve el contenedor con la lógica de
    /// fusión y racha, y las vistas nunca tocan el `ModelContext` a pelo.
    @State private var store = PersistenceStore()

    var body: some Scene {
        WindowGroup {
            MapView(store: store)
        }
    }
}
