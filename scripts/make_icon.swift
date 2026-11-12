// Génère l’icône 1024 px de l’app : swift scripts/make_icon.swift <sortie.png>
import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset = 100.0
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(
    starting: NSColor(red: 0.16, green: 0.56, blue: 0.96, alpha: 1),
    ending: NSColor(red: 0.02, green: 0.27, blue: 0.68, alpha: 1))!
    .draw(in: shape, angle: -90)

func draw(_ name: String, pointSize: Double, center: NSPoint, color: NSColor) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return }
    let s = symbol.size
    symbol.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
}

draw("cloud.fill", pointSize: 430, center: NSPoint(x: 512, y: 540), color: .white)
draw("stethoscope", pointSize: 230, center: NSPoint(x: 512, y: 505),
     color: NSColor(red: 0.04, green: 0.33, blue: 0.75, alpha: 1))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
