import AppKit

// Build-time helper: renders the default AppSeed icon as a 1024×1024 PNG
// (flat clay rounded square with a white leaf glyph). The build script then
// turns it into AppIcon.icns with sips + iconutil — the same pipeline the
// factory uses at runtime, so the .icns is never authored with Cocoa APIs.
//
// Usage: swift make-default-icon.swift <output.png>

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift make-default-icon.swift <output.png>\n".utf8))
    exit(2)
}
let outputURL = URL(fileURLWithPath: arguments[1])

let pixels = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("Could not create bitmap\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

// Flat clay rounded square (matches the HUD accent).
NSColor(srgbRed: 0.788, green: 0.482, blue: 0.294, alpha: 1).setFill()
NSBezierPath(
    roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848),
    xRadius: 190,
    yRadius: 190
).fill()

// White leaf glyph, aspect-fit into a centered box.
let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 400, weight: .medium)
if let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfiguration) {
    let tinted = NSImage(size: leaf.size, flipped: false) { rect in
        leaf.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let box: CGFloat = 460
    let aspect = leaf.size.width / max(leaf.size.height, 1)
    let glyphSize = aspect > 1
        ? NSSize(width: box, height: box / aspect)
        : NSSize(width: box * aspect, height: box)
    let glyphOrigin = NSPoint(
        x: (CGFloat(pixels) - glyphSize.width) / 2,
        y: (CGFloat(pixels) - glyphSize.height) / 2
    )
    tinted.draw(
        in: NSRect(origin: glyphOrigin, size: glyphSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Could not encode PNG\n".utf8))
    exit(1)
}
try png.write(to: outputURL)
