// Recadre les captures de l’app et compose l’image de présentation.
//   swift scripts/make_visuals.swift crop <capture.png> <sortie.png>
//   swift scripts/make_visuals.swift banner <icone.png> <capture recadrée.png> <sortie.png>
import AppKit

func load(_ path: String) -> NSBitmapImageRep {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let rep = NSBitmapImageRep(data: data) else {
        fatalError("Image illisible : \(path)")
    }
    return rep
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func canvas(_ width: Int, _ height: Int, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.current = nil
    return rep
}

/// Abscisse du séparateur entre la barre latérale et le contenu : première colonne opaque nettement plus sombre.
/// (La barre latérale, non rendue par la capture interne, est transparente.)
func dividerX(_ rep: NSBitmapImageRep) -> Int {
    let rows = [rep.pixelsHigh / 3, rep.pixelsHigh / 2, rep.pixelsHigh * 2 / 3]
    for x in (rep.pixelsWide / 8)..<(rep.pixelsWide / 2) {
        let dark = rows.allSatisfy { y in
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
            return c.alphaComponent > 0.9 && c.redComponent < 0.86 && c.greenComponent < 0.86 && c.blueComponent < 0.86
        }
        if dark { return x }
    }
    return rep.pixelsWide / 4
}

let args = CommandLine.arguments
switch args[1] {
case "crop":
    // Retire la barre latérale (non rendue par la capture interne) et la barre de titre vide.
    let source = load(args[2])
    let left = dividerX(source) + 2
    let top = 110
    let width = source.pixelsWide - left
    let height = source.pixelsHigh - top
    let image = NSImage(size: NSSize(width: source.pixelsWide, height: source.pixelsHigh))
    image.addRepresentation(source)
    let out = canvas(width, height) {
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: NSRect(x: left, y: 0, width: width, height: height), operation: .sourceOver, fraction: 1)
    }
    save(out, args[3])

case "banner":
    let icon = NSImage(contentsOfFile: args[2])!
    let shotRep = load(args[3])
    let shot = NSImage(size: NSSize(width: shotRep.pixelsWide, height: shotRep.pixelsHigh))
    shot.addRepresentation(shotRep)
    let w = 2400.0, h = 1254.0  // 1200 × 627 en double densité, format des aperçus de lien
    let out = canvas(Int(w), Int(h)) {
        NSGradient(colors: [
            NSColor(red: 0.20, green: 0.62, blue: 0.98, alpha: 1),
            NSColor(red: 0.07, green: 0.42, blue: 0.87, alpha: 1),
            NSColor(red: 0.03, green: 0.24, blue: 0.62, alpha: 1),
        ])!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -35)

        // Capture, à droite, coins arrondis et ombre, débordant en bas.
        let shotWidth = 1380.0
        let shotHeight = shotWidth * Double(shotRep.pixelsHigh) / Double(shotRep.pixelsWide)
        let shotRect = NSRect(x: w - shotWidth - 70, y: h - 150 - shotHeight, width: shotWidth, height: shotHeight)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 60
        shadow.shadowOffset = NSSize(width: 0, height: -20)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: shotRect, xRadius: 28, yRadius: 28).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: shotRect, xRadius: 28, yRadius: 28).addClip()
        shot.draw(in: shotRect)
        NSGraphicsContext.restoreGraphicsState()

        // Icône, titre et accroche, à gauche.
        icon.draw(in: NSRect(x: 50, y: h - 420, width: 320, height: 320))
        // `top` : distance entre le haut de l’image et le haut du texte.
        func text(_ string: String, size: Double, weight: NSFont.Weight, alpha: Double, top: Double, width: Double = 820) {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 6
            NSAttributedString(string: string, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor.white.withAlphaComponent(alpha),
                .paragraphStyle: style,
            ]).draw(with: NSRect(x: 80, y: h - top - 500, width: width, height: 500), options: [.usesLineFragmentOrigin])
        }
        text("SyncDoctor", size: 124, weight: .bold, alpha: 1, top: 440)
        text("Le diagnostic pour OneDrive\net SharePoint sur Mac,\nen un clic.", size: 56, weight: .medium, alpha: 0.95, top: 620)
        text("14 vérifications · lecture seule\ngratuit et open source", size: 36, weight: .regular, alpha: 0.85, top: 930)
        text("Application indépendante. OneDrive et SharePoint\nsont des marques de Microsoft Corporation.", size: 23, weight: .regular, alpha: 0.7, top: 1130)
    }
    save(out, args[4])

default:
    fatalError("Usage : crop | banner")
}
