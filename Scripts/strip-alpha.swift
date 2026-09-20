// Reescribe PNG sin canal alfa, sobre fondo blanco.
//
//   swift Scripts/strip-alpha.swift docs/appstore/*.png
//
// `simctl io screenshot` guarda con alfa aunque la pantalla sea opaca, y App
// Store Connect rechaza las capturas que lo llevan. sips no sabe quitarlo, así
// que se redibuja el bitmap en un contexto sin canal alfa.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

var changed = 0
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("no se pudo leer \(path)"); continue
    }
    guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast,
          image.alphaInfo != .noneSkipFirst else { continue }

    let width = image.width, height = image.height
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { print("contexto fallido en \(path)"); continue }

    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let flat = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { print("no se pudo escribir \(path)"); continue }
    CGImageDestinationAddImage(destination, flat, nil)
    if CGImageDestinationFinalize(destination) { changed += 1 }
}
print("aplanadas: \(changed)")
