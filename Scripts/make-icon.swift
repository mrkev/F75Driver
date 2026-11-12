// Draws the app icon and writes every size the asset catalog needs.
//
//   swift Scripts/make-icon.swift
//
// The icon is drawn from shapes here rather than from an SF Symbol, whose
// licence does not allow use in app icons.

import AppKit

let output = URL(fileURLWithPath: "F75Driver/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fill(_ path: NSBezierPath, top: NSColor, bottom: NSColor) {
    NSGradient(starting: bottom, ending: top)!.draw(in: path, angle: 90)
}

/// One keycap seen from above: a darker skirt with a lighter dished top.
func keycap(_ rect: CGRect, base: UInt32, legend: String?, legendColor: NSColor) {
    let r = rect.width * 0.16
    // Shadow under the cap.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = rect.width * 0.08
    shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.05)
    shadow.set()
    color(base).blended(withFraction: 0.35, of: .black)!.setFill()
    roundedRect(rect, r).fill()
    NSGraphicsContext.restoreGraphicsState()

    let skirt = roundedRect(rect, r)
    fill(skirt, top: color(base).blended(withFraction: 0.05, of: .black)!,
         bottom: color(base).blended(withFraction: 0.4, of: .black)!)

    let top = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12)
        .offsetBy(dx: 0, dy: rect.height * 0.05)
    let face = roundedRect(top, r * 0.75)
    fill(face, top: color(base).blended(withFraction: 0.18, of: .white)!, bottom: color(base))

    guard let legend else { return }
    let font = NSFont.systemFont(ofSize: top.height * 0.5, weight: .semibold)
    let text = NSAttributedString(string: legend, attributes: [.font: font, .foregroundColor: legendColor])
    let size = text.size()
    text.draw(at: CGPoint(x: top.midX - size.width / 2, y: top.midY - size.height / 2 + top.height * 0.02))
}

func drawIcon(in canvas: CGFloat) {
    let s = canvas / 1024
    // macOS icon grid: an 824-point body centred on the 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: s, y: s))
    let bodyPath = roundedRect(body, 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = .black.withAlphaComponent(0.35)
    drop.shadowBlurRadius = 20 * s
    drop.shadowOffset = NSSize(width: 0, height: -10 * s)
    drop.set()
    color(0x2A2D33).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The keyboard case.
    fill(bodyPath, top: color(0x3B3F47), bottom: color(0x1C1E22))

    // Under-glow along the bottom edge, for the backlight.
    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    let glow = NSGradient(colors: [color(0xFF5F6D, 0.55), color(0xFFC371, 0.5), color(0x47E5BC, 0.5),
                                   color(0x4F8CFF, 0.55), color(0xB86BFF, 0.55)])!
    let band = CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height * 0.3)
    let cg = NSGraphicsContext.current!.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    glow.draw(in: band, angle: 0)
    // Fade the glow out towards the top so it has no visible edge.
    NSGraphicsContext.current!.compositingOperation = .destinationIn
    NSGradient(starting: .white, ending: .white.withAlphaComponent(0))!.draw(in: band, angle: 90)
    cg.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()

    // A 3 × 3 block of keys; the middle row reads F 7 5.
    let gap = 26 * s
    let key = (body.width - 2 * 110 * s - 2 * gap) / 3
    let origin = CGPoint(x: body.minX + 110 * s, y: body.minY + 120 * s)
    let legends: [[String?]] = [[nil, nil, nil], ["F", "7", "5"], [nil, nil, nil]]
    for row in 0..<3 {
        for column in 0..<3 {
            let rect = CGRect(x: origin.x + CGFloat(column) * (key + gap),
                              y: origin.y + CGFloat(2 - row) * (key + gap),
                              width: key, height: key)
            let accent = row == 0 && column == 0
            keycap(rect, base: accent ? 0xF2703A : 0xE4E6EA,
                   legend: legends[row][column],
                   legendColor: color(0x2E3138))
        }
    }

    // Light sheen across the top of the case.
    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    NSGradient(starting: .white.withAlphaComponent(0.10), ending: .white.withAlphaComponent(0))!
        .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, 0.12).setStroke()
    let rim = roundedRect(body.insetBy(dx: 1.5 * s, dy: 1.5 * s), 184 * s)
    rim.lineWidth = 3 * s
    rim.stroke()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon(in: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: points * scale).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon sizes to \(output.path)")
