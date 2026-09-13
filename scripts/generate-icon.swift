import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
// Reproducible, code-native hairspring mark. Opaque RGB; no external assets.
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.975, green: 0.965, blue: 0.94, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setStrokeColor(CGColor(red: 0.12, green: 0.12, blue: 0.10, alpha: 1))
context.setLineWidth(17); context.setLineCap(.round)
for i in 0...900 {
    let t = Double(i) / 900, angle = t * .pi * 7.5
    let radius = 24 + t * 345
    let point = CGPoint(x: 512 + cos(angle) * radius, y: 512 + sin(angle) * radius)
    if i == 0 { context.move(to: point) } else { context.addLine(to: point) }
}
context.strokePath()
context.setFillColor(CGColor(red: 0.92, green: 0.25, blue: 0.045, alpha: 1))
context.fillEllipse(in: CGRect(x: 772, y: 732, width: 60, height: 60))
let image = context.makeImage()!
let url = URL(fileURLWithPath: "ios/Overcoil/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
