import Foundation
import SwiftUI

// MARK: - Bancos de sonido

/// Un banco cambia el timbre, no solo la frecuencia. Si solo moviera los hercios
/// no sería un cosmético: sería el mismo pitido un poco más agudo, y nadie
/// gastaría cobre en eso.
///
/// El timbre se construye por síntesis aditiva: la lista dice qué amplitud tiene
/// cada armónico respecto al fundamental. Una onda senoidal pura es `[1]`; una
/// cuadrada se aproxima con los armónicos impares en 1/n.
struct SoundBank: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detail: String
    let price: Int
    let frequency: Double
    let harmonics: [Double]

    /// Muestra normalizada del timbre en la fase dada.
    func sample(phase: Double) -> Double {
        var value = 0.0
        var norm = 0.0
        for (index, amplitude) in harmonics.enumerated() where amplitude != 0 {
            value += sin(phase * Double(index + 1)) * amplitude
            norm += amplitude
        }
        return norm > 0 ? value / norm : 0
    }

    static let sine = SoundBank(
        id: "bank.sine", name: "Onda senoidal", price: 0,
        detail: "El tono limpio de siempre, 600 Hz. El estándar en radioafición.",
        frequency: 600, harmonics: [1]
    )

    static let military = SoundBank(
        id: "bank.military", name: "Radio militar", price: 120,
        detail: "Más grave y con cuerpo, como un receptor de campaña.",
        frequency: 480, harmonics: [1, 0, 0.35, 0, 0.18, 0, 0.08]
    )

    static let eightBit = SoundBank(
        id: "bank.8bit", name: "8 bits", price: 150,
        detail: "Onda cuadrada y aguda. Morse de recreativa.",
        frequency: 800, harmonics: [1, 0, 0.33, 0, 0.2, 0, 0.14, 0, 0.11]
    )

    static let all: [SoundBank] = [.sine, .military, .eightBit]

    static func bank(id: String) -> SoundBank { all.first { $0.id == id } ?? .sine }
}

extension SoundBank {
    init(id: String, name: String, price: Int, detail: String,
         frequency: Double, harmonics: [Double]) {
        self.id = id; self.name = name; self.detail = detail
        self.price = price; self.frequency = frequency; self.harmonics = harmonics
    }
}

// MARK: - Temas

/// Un tema cambia el color de acento y la cara de la tecla. Se define con
/// componentes y no con `Color` con nombre para que funcione igual en claro y
/// oscuro sin un catálogo de assets por tema.
struct Theme: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let price: Int
    let detail: String
    private let accentLight: RGB
    private let accentDark: RGB
    private let keyFaceLight: RGB
    private let keyFaceDark: RGB

    struct RGB: Equatable, Sendable {
        let r: Double, g: Double, b: Double
        var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    }

    func accent(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? accentDark : accentLight).color
    }
    func keyFace(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? keyFaceDark : keyFaceLight).color
    }
    /// Color de muestra para la tienda, donde no hay contexto de esquema.
    var swatch: Color { accentLight.color }

    static let classic = Theme(
        id: "theme.classic", name: "Clásico", price: 0,
        detail: "El azul de sistema. Sobrio y legible a cualquier hora.",
        accentLight: RGB(r: 0.04, g: 0.48, b: 1.00),
        accentDark:  RGB(r: 0.31, g: 0.65, b: 1.00),
        keyFaceLight: RGB(r: 0.96, g: 0.96, b: 0.97),
        keyFaceDark:  RGB(r: 0.17, g: 0.18, b: 0.21)
    )

    static let typewriter = Theme(
        id: "theme.typewriter", name: "Máquina de escribir", price: 200,
        detail: "Ámbar sobre marfil, teclas de baquelita.",
        accentLight: RGB(r: 0.72, g: 0.42, b: 0.09),
        accentDark:  RGB(r: 0.92, g: 0.64, b: 0.24),
        keyFaceLight: RGB(r: 0.96, g: 0.93, b: 0.86),
        keyFaceDark:  RGB(r: 0.22, g: 0.19, b: 0.15)
    )

    static let neon = Theme(
        id: "theme.neon", name: "Terminal neón", price: 250,
        detail: "Verde de fósforo sobre negro. Morse de sala de máquinas.",
        accentLight: RGB(r: 0.05, g: 0.62, b: 0.34),
        accentDark:  RGB(r: 0.22, g: 1.00, b: 0.55),
        keyFaceLight: RGB(r: 0.91, g: 0.96, b: 0.92),
        keyFaceDark:  RGB(r: 0.07, g: 0.14, b: 0.10)
    )

    static let copper = Theme(
        id: "theme.copper", name: "Cobre", price: 300,
        detail: "El color de la moneda del juego, en bronce pulido.",
        accentLight: RGB(r: 0.72, g: 0.35, b: 0.16),
        accentDark:  RGB(r: 0.93, g: 0.55, b: 0.31),
        keyFaceLight: RGB(r: 0.98, g: 0.94, b: 0.90),
        keyFaceDark:  RGB(r: 0.23, g: 0.16, b: 0.12)
    )

    static let all: [Theme] = [.classic, .typewriter, .neon, .copper]

    static func theme(id: String) -> Theme { all.first { $0.id == id } ?? .classic }
}

// MARK: - Catálogo

enum CosmeticCatalog {
    /// Lo gratuito se considera comprado desde el principio: no aparece con
    /// precio ni se puede "perder".
    static var freeIDs: Set<String> {
        Set(Theme.all.filter { $0.price == 0 }.map(\.id)
            + SoundBank.all.filter { $0.price == 0 }.map(\.id))
    }

    static var purchasableCount: Int {
        Theme.all.filter { $0.price > 0 }.count + SoundBank.all.filter { $0.price > 0 }.count
    }

    static func price(of id: String) -> Int? {
        if let theme = Theme.all.first(where: { $0.id == id }) { return theme.price }
        if let bank = SoundBank.all.first(where: { $0.id == id }) { return bank.price }
        return nil
    }
}
