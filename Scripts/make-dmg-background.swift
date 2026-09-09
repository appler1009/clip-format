import AppKit
import Foundation

/// Finder window content size, in points. `package.sh` must use the same
/// numbers for window bounds and icon positions.
let canvas = NSSize(width: 640, height: 400)
let scale: CGFloat = 2
let appIconCenter = NSPoint(x: 160, y: 188)
let applicationsCenter = NSPoint(x: 480, y: 188)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func drawJSON(_ text: String, at origin: NSPoint, size: CGFloat, color: NSColor) {
    let str = NSAttributedString(string: text, attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
        .foregroundColor: color,
    ])
    str.draw(at: origin)
}

func drawCentered(_ text: String, at center: NSPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
    let str = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ])
    let box = str.size()
    str.draw(at: NSPoint(x: center.x - box.width / 2, y: center.y - box.height / 2))
}

let px = NSSize(width: canvas.width * scale, height: canvas.height * scale)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px.width), pixelsHigh: Int(px.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = canvas

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.cgContext.setShouldAntialias(true)

let bounds = NSRect(origin: .zero, size: canvas)

// Opaque white so Finder's default background never shows through at the edges.
rgb(0xFFFFFF).setFill()
bounds.fill()

// A whisper of warmth at the top, still essentially white — matches the popover's
// light theme without fighting the folder chrome.
NSGradient(colors: [rgb(0xFDFDFB), rgb(0xFFFFFF)])!
    .draw(in: bounds, angle: -90)

// Architectural braces, watermark-quiet.
let watermark = NSFont.monospacedSystemFont(ofSize: 220, weight: .semibold)
for (glyph, x) in [("{", CGFloat(-18)), ("}", canvas.width - 118)] {
    let str = NSAttributedString(string: glyph, attributes: [
        .font: watermark,
        .foregroundColor: rgb(0x1C1C1E, 0.04),
    ])
    str.draw(at: NSPoint(x: x, y: 40))
}

// Minified on the left, pretty on the right — same direction as the drag.
drawJSON("{\"pretty\":false}",
         at: NSPoint(x: 48, y: 356), size: 12, color: rgb(0x6E6E73))
let prettyLines: [(String, UInt32)] = [
    ("{", 0x9A9A9F),
    ("  \"pretty\": true", 0x0F766E),
    ("}", 0x9A9A9F),
]
var prettyY: CGFloat = 368
for (line, hex) in prettyLines {
    drawJSON(line, at: NSPoint(x: 478, y: prettyY), size: 12, color: rgb(hex))
    prettyY -= 15
}

drawCentered("Drag ClipFormat onto Applications.",
             at: NSPoint(x: canvas.width / 2, y: 312),
             size: 13, color: rgb(0x1C1C1E), weight: .semibold)
drawCentered("We'll indent the rest.",
             at: NSPoint(x: canvas.width / 2, y: 292),
             size: 12, color: rgb(0x6E6E73), weight: .regular)

func well(at center: NSPoint) {
    let r = NSRect(x: center.x - 78, y: center.y - 86, width: 156, height: 168)
    let path = NSBezierPath(roundedRect: r, xRadius: 28, yRadius: 28)
    rgb(0xF1F1EE).setFill()
    path.fill()
    rgb(0x1C1C1E, 0.06).setStroke()
    path.lineWidth = 1
    path.stroke()
}

well(at: appIconCenter)
well(at: applicationsCenter)

// Arrow: the icon's syntax-coloured bars, pointing at Applications.
let midY = appIconCenter.y
let shaftX: [CGFloat] = [268, 300, 332]
let shaftColors: [UInt32] = [0x1D4ED8, 0x0F766E, 0x9333EA]
for (x, hex) in zip(shaftX, shaftColors) {
    let bar = NSRect(x: x, y: midY - 4, width: 22, height: 8)
    rgb(hex).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()
}
let head = NSBezierPath()
head.move(to: NSPoint(x: 358, y: midY))
head.line(to: NSPoint(x: 344, y: midY + 11))
head.line(to: NSPoint(x: 344, y: midY - 11))
head.close()
rgb(0x9333EA).setFill()
head.fill()

drawCentered("Revived.",
             at: NSPoint(x: canvas.width / 2, y: 36),
             size: 15, color: rgb(0x1C1C1E), weight: .semibold)

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.dropFirst().first
    ?? "Packaging/dmg-background.png"
let url = URL(fileURLWithPath: out)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
try rep.representation(using: .png, properties: [:])!.write(to: url)
print("wrote \(out) (\(Int(px.width))×\(Int(px.height)) px, \(Int(canvas.width))×\(Int(canvas.height)) pt)")
