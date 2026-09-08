import AppKit
import Foundation

// ClipFormat app icon: the menu-bar braces, opened up to hold three
// syntax-coloured lines. Palette is Theme.dark so the icon, popover and
// Quick Look preview all read as one thing.
func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)
    let s = px / 1024.0

    // Rounded-square plate on Apple's icon grid, with a top-lit gradient.
    // At 16px the plate's own margin costs more than it buys, so it grows.
    let tiny = px <= 16
    let inset = (tiny ? 56.0 : 100.0) * s
    let plate = NSRect(x: inset, y: inset, width: px - inset * 2, height: px - inset * 2)
    let path = NSBezierPath(roundedRect: plate, xRadius: 190 * s, yRadius: 190 * s)
    ctx.saveGState()
    path.addClip()
    NSGradient(colors: [color(0x32363F), color(0x191A1E)])!
        .draw(in: plate, angle: -90)
    // A soft highlight along the top edge keeps it from looking flat at 512px.
    NSGradient(colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0.0)])!
        .draw(in: NSRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: -90)
    ctx.restoreGState()

    // Three content lines, standing in for a formatted key/value block.
    // Below 64px three thin lines merge into a smudge, so the small sizes
    // carry two heavier ones and thicker braces instead.
    let small = px < 64
    let bars: [(UInt32, CGFloat, CGFloat)] = tiny
        ? []                                     // 16px: braces alone, or it smears
        : small
        ? [(0x7AA2F7, 210, 556), (0x8FD48A, 154, 396)]
        : [(0x7AA2F7, 208, 570), (0x8FD48A, 164, 484), (0xD9A5F5, 116, 398)]
    let barHeight: CGFloat = small ? 92 : 56
    for (hex, w, y) in bars {
        let r = NSRect(x: 412 * s, y: y * s, width: w * s, height: barHeight * s)
        color(hex).setFill()
        NSBezierPath(roundedRect: r, xRadius: barHeight / 2 * s, yRadius: barHeight / 2 * s).fill()
    }

    // The braces themselves, matching the status-item glyph.
    let braceSize = (tiny ? 500 : small ? 560 : 470) * s
    let font = NSFont.monospacedSystemFont(ofSize: braceSize, weight: small ? .bold : .semibold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(0xF2F3F5)]
    let braceX: (CGFloat, CGFloat) = tiny ? (330, 694) : small ? (316, 708) : (336, 688)
    for (glyph, x) in [("{", braceX.0), ("}", braceX.1)] {
        let str = NSAttributedString(string: glyph, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: x * s - size.width / 2, y: px / 2 - size.height / 2))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func zoom(_ rep: NSBitmapImageRep, _ factor: Int, to path: String) {
    let w = rep.pixelsWide * factor, h = rep.pixelsHigh * factor
    let big = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: big)
    NSGraphicsContext.current!.imageInterpolation = .none
    rep.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try! big.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
for px in [16, 32, 64, 128, 256, 512, 1024] {  // 1x and 2x pairs across the catalog
    let rep = render(CGFloat(px))
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/icon_\(px).png"))
    if px <= 64 { zoom(rep, 512 / px, to: "\(out)/zoom_\(px).png") }
}
print("rendered")
