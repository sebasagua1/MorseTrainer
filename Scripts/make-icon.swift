// Genera el icono de la app. Por código y no como binario suelto para que el
// icono sea reproducible y se pueda retocar sin abrir un editor gráfico.
//
//   swift Scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// El motivo es el punto y la raya: los dos elementos del Morse y, de paso, el
// nivel 1 del juego. A 40 px sigue leyéndose, que es la prueba que importa.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "AppIcon.png")

let space = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil,
                              width: side, height: side,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              // Sin canal alfa: un icono de iOS debe ser opaco.
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("No se pudo crear el contexto") }

// Fondo: degradado diagonal en el azul de la app.
let start = CGColor(srgbRed: 0.18, green: 0.56, blue: 1.00, alpha: 1)
let end = CGColor(srgbRed: 0.02, green: 0.20, blue: 0.62, alpha: 1)
guard let gradient = CGGradient(colorsSpace: space,
                                colors: [start, end] as CFArray,
                                locations: [0, 1])
else { fatalError("No se pudo crear el degradado") }
context.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: side),
                           end: CGPoint(x: side, y: 0),
                           options: [])

// Punto y raya centrados. La raya mide tres veces el punto, como en el código.
let thickness: CGFloat = 168
let gap: CGFloat = 104
let dashWidth = thickness * 3
let totalWidth = thickness + gap + dashWidth
let left = (CGFloat(side) - totalWidth) / 2
let centerY = CGFloat(side) / 2

context.setShadow(offset: CGSize(width: 0, height: -14),
                  blur: 36,
                  color: CGColor(srgbRed: 0, green: 0.08, blue: 0.28, alpha: 0.35))
context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))

context.fillEllipse(in: CGRect(x: left,
                               y: centerY - thickness / 2,
                               width: thickness,
                               height: thickness))

let dash = CGRect(x: left + thickness + gap,
                  y: centerY - thickness / 2,
                  width: dashWidth,
                  height: thickness)
context.addPath(CGPath(roundedRect: dash,
                       cornerWidth: thickness / 2,
                       cornerHeight: thickness / 2,
                       transform: nil))
context.fillPath()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("No se pudo generar la imagen") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("No se pudo escribir el PNG") }
print("Icono escrito en \(output.path)")
