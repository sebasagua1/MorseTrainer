import SwiftUI

// MARK: - Paleta semántica

/// Colores por *función*, no por nombre.
///
/// Antes el `Theme` solo exponía `accent` y `keyFace`, así que comprar un tema
/// cambiaba dos elementos y dejaba el resto de la app igual: el resto eran
/// `.green`, `.red` y grises del sistema repartidos por las vistas. Aquí cada
/// papel tiene un token y cada token tiene su pareja clara/oscura, así que el
/// tema tiñe la app entera y el contraste se decide una vez.
///
/// Los valores de `success` y `danger` no son los `.green`/`.red` del sistema:
/// esos, sobre fondo claro, se quedan en 3:1 y el texto de estado no llega al
/// mínimo. Los de aquí están calculados para pasar 4.5:1 en ambos modos.
struct MorsePalette: Equatable {

    let accent: Color
    /// Texto/iconos que van *encima* del acento.
    let onAccent: Color
    let background: Color
    let surface: Color
    /// Superficie que debe leerse por encima de `surface` (tarjetas sobre lista).
    let surfaceRaised: Color
    let textPrimary: Color
    let textSecondary: Color
    let border: Color
    let success: Color
    let danger: Color
    /// Portadora encendida y apagada. El "apagado" no es transparente: sobre
    /// negro tiene que seguir viéndose el disco, o en modo oscuro la pista
    /// visual desaparece justo para quien juega sin sonido.
    let signalOn: Color
    let signalOff: Color

    static func make(theme: Theme, scheme: ColorScheme) -> MorsePalette {
        let accent = theme.accent(scheme)
        let dark = scheme == .dark
        return MorsePalette(
            accent: accent,
            onAccent: theme.onAccent(scheme),
            background: dark ? Color(hex: 0x0B0B0F) : Color(hex: 0xF4F5F9),
            surface: dark ? Color(hex: 0x17181D) : .white,
            surfaceRaised: dark ? Color(hex: 0x212329) : .white,
            textPrimary: dark ? Color(hex: 0xF2F3F7) : Color(hex: 0x14161C),
            textSecondary: dark ? Color(hex: 0x9EA3B0) : Color(hex: 0x5B6170),
            border: dark ? Color(hex: 0x2E3138) : Color(hex: 0xDFE2EA),
            success: dark ? Color(hex: 0x35D07F) : Color(hex: 0x157F3D),
            danger: dark ? Color(hex: 0xFF6B5E) : Color(hex: 0xB3261E),
            signalOn: accent,
            signalOff: dark ? Color(hex: 0x2A2D34) : Color(hex: 0xD9DDE6)
        )
    }
}

extension Theme {
    func palette(_ scheme: ColorScheme) -> MorsePalette {
        .make(theme: self, scheme: scheme)
    }

    /// Blanco o casi-negro según la luminancia del acento, para que el texto
    /// encima del color del tema siempre se lea. El neón verde y el cobre
    /// necesitan respuestas distintas.
    func onAccent(_ scheme: ColorScheme) -> Color {
        accent(scheme).wcagLuminance > 0.45 ? Color(hex: 0x14161C) : .white
    }
}

// MARK: - Acceso desde las vistas

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = MorsePalette.make(theme: .classic, scheme: .light)
}

extension EnvironmentValues {
    /// Paleta vigente. La fija cada pantalla raíz con `.morseTheme(_:)`; los
    /// componentes de dentro solo la leen, así ninguno vuelve a inventarse un
    /// `.green` propio.
    var palette: MorsePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Aplica el tema del jugador: paleta al entorno y `tint` para los
    /// controles del sistema, en una sola llamada.
    func morseTheme(_ theme: Theme, _ scheme: ColorScheme) -> some View {
        let palette = theme.palette(scheme)
        return environment(\.palette, palette).tint(palette.accent)
    }
}

// MARK: - Color: utilidades

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Mezcla con blanco. Para el degradado de volumen de la tecla.
    func lighter(_ amount: Double) -> Color { mixed(with: .white, amount) }
    /// Mezcla con negro.
    func darker(_ amount: Double) -> Color { mixed(with: .black, amount) }

    private func mixed(with other: Color, _ amount: Double) -> Color {
        #if canImport(UIKit)
        let t = min(max(amount, 0), 1)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(.sRGB,
                     red: Double(r1) * (1 - t) + Double(r2) * t,
                     green: Double(g1) * (1 - t) + Double(g2) * t,
                     blue: Double(b1) * (1 - t) + Double(b2) * t,
                     opacity: Double(a1))
        #else
        return self
        #endif
    }

    /// Luminancia relativa WCAG. Se usa para decidir texto claro u oscuro
    /// encima de un color de tema que el jugador puede cambiar en la tienda.
    var wcagLuminance: Double {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        #else
        return 0.5
        #endif
    }
}

// MARK: - Tipografía

/// Tamaños de display que **sí** escalan con Dynamic Type.
///
/// `.font(.system(size: 92))` no escala: el jugador que sube el tamaño de
/// letra del sistema ve exactamente lo mismo. Había dieciséis de esos repartidos
/// por la app. `@ScaledMetric` ata el tamaño a un estilo de texto, así que la
/// cifra grande sigue siendo grande pero crece con el resto.
private struct ScaledRounded: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .rounded))
    }
}

extension View {
    /// Glifo de display escalable. `minimumScaleFactor` incluido: a tamaños de
    /// accesibilidad un 92 pt se saldría de pantalla.
    func displayFont(_ size: CGFloat,
                     _ weight: Font.Weight = .bold,
                     relativeTo style: Font.TextStyle = .largeTitle) -> some View {
        modifier(ScaledRounded(size: size, weight: weight, relativeTo: style))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

extension Font {
    /// Estilo semántico + diseño redondeado. Escala con Dynamic Type por ser
    /// un `TextStyle` y no un tamaño suelto.
    static func rounded(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    static func mono(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
}

// MARK: - Ritmo

/// Escala 4/8. Tener los números con nombre evita que aparezcan 18, 22 y 26
/// sueltos en tres vistas distintas, que es lo que pasaba.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Radius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
}

// MARK: - Patrón Morse como elemento gráfico

/// Puntos y rayas dibujados, no escritos.
///
/// El texto ".-" depende de la fuente y se lee como puntuación. Dibujarlo con
/// formas da el ritmo de un vistazo —que es justo lo que enseña la app— y es
/// el único motivo visual que la interfaz tenía y no usaba en ninguna parte.
struct MorseGlyph: View {
    let code: MorseCode
    var unit: CGFloat = 6
    var tint: Color = .primary
    /// Cuántos elementos están "encendidos". `nil` = todos.
    var highlighted: Int?

    var body: some View {
        HStack(spacing: unit * 0.9) {
            ForEach(Array(code.symbols.enumerated()), id: \.offset) { index, symbol in
                Capsule(style: .continuous)
                    .frame(width: symbol == .dit ? unit : unit * 3, height: unit)
                    .opacity(highlighted.map { index < $0 ? 1 : 0.25 } ?? 1)
            }
        }
        .foregroundStyle(tint)
        .accessibilityHidden(true)
    }
}
