import AppKit

// Build-time helper: renders AppSeed's brand assets from the committed leaf
// artwork (Resources/leaf.svg — the single source of truth for the mark):
//
//   1. The app icon: a flat clay rounded square with the leaf as a white
//      silhouette, 1024×1024 PNG. The build script turns this into
//      AppIcon.icns via sips + iconutil — the same pipeline the factory uses
//      at runtime, so the .icns is never authored with unreliable Cocoa APIs.
//   2. The menu bar template: the leaf silhouette alone, tight and centered
//      on transparent, marked as a template image at runtime so macOS tints
//      it for light/dark menu bars.
//
// Usage: swift make-default-icon.swift <leaf.svg> <appicon-out.png> <menubar-out.png>

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data(
        "Usage: swift make-default-icon.swift <leaf.svg> <appicon-out.png> <menubar-out.png>\n".utf8))
    exit(2)
}
let leafSVGURL = URL(fileURLWithPath: arguments[1])
let appIconURL = URL(fileURLWithPath: arguments[2])
let menuBarURL = URL(fileURLWithPath: arguments[3])

// MARK: - Helpers

func makeBitmap(_ pixels: Int) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write(Data("Could not create bitmap\n".utf8))
        exit(1)
    }
    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) {
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Could not encode PNG\n".utf8))
        exit(1)
    }
    do { try png.write(to: url) } catch {
        FileHandle.standardError.write(Data("Could not write \(url.path): \(error)\n".utf8))
        exit(1)
    }
}

/// Renders the leaf artwork as a tight, centered white silhouette on a
/// transparent square canvas. The source SVG is a wide banner with the leaf
/// offset to one side, so we render at full size, find the alpha bounding
/// box, and crop to it — the mark stays reproducible from committed art with
/// no hand-measured coordinates.
func renderLeafSilhouette(canvas: Int, paddingFraction: CGFloat) -> NSBitmapImageRep {
    guard let svg = NSImage(contentsOf: leafSVGURL) else {
        FileHandle.standardError.write(Data("Could not load \(leafSVGURL.path)\n".utf8))
        exit(1)
    }
    let renderW = Int(svg.size.width.rounded()), renderH = Int(svg.size.height.rounded())
    // The SVG is a wide banner, not square, so render at its true aspect for
    // an accurate alpha bounding box (makeBitmap only produces squares).
    guard let full = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: renderW, pixelsHigh: renderH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: full)
    svg.draw(in: NSRect(x: 0, y: 0, width: renderW, height: renderH))
    NSGraphicsContext.restoreGraphicsState()

    var minX = renderW, minY = renderH, maxX = 0, maxY = 0
    for y in 0..<renderH {
        for x in 0..<renderW where (full.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else {
        FileHandle.standardError.write(Data("Leaf artwork rendered empty\n".utf8))
        exit(1)
    }
    let boxW = maxX - minX + 1, boxH = maxY - minY + 1

    let out = makeBitmap(canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    let padding = CGFloat(canvas) * paddingFraction
    let fitBox = CGFloat(canvas) - padding * 2
    let scale = min(fitBox / CGFloat(boxW), fitBox / CGFloat(boxH))
    let drawW = CGFloat(boxW) * scale, drawH = CGFloat(boxH) * scale
    let originX = (CGFloat(canvas) - drawW) / 2, originY = (CGFloat(canvas) - drawH) / 2
    // AppKit is bottom-left origin; flip the source Y for the crop rect.
    let srcRect = NSRect(x: minX, y: renderH - maxY - 1, width: boxW, height: boxH)
    full.draw(in: NSRect(x: originX, y: originY, width: drawW, height: drawH),
              from: srcRect, operation: .sourceOver, fraction: 1,
              respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    // Recolor to pure white, preserving the leaf's alpha (incl. interior vein).
    NSColor.white.set()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    return out
}

// MARK: - App icon (clay square + white leaf)

let iconPixels = 1024
let icon = makeBitmap(iconPixels)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: icon)

// Flat clay rounded square (matches the HUD accent).
NSColor(srgbRed: 0.788, green: 0.482, blue: 0.294, alpha: 1).setFill()
NSBezierPath(
    roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848),
    xRadius: 190, yRadius: 190
).fill()

// White leaf silhouette, centered, occupying ~54% of the canvas.
let leafForIcon = renderLeafSilhouette(canvas: iconPixels, paddingFraction: 0.23)
leafForIcon.draw(in: NSRect(x: 0, y: 0, width: iconPixels, height: iconPixels),
                 from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])

NSGraphicsContext.restoreGraphicsState()
writePNG(icon, to: appIconURL)

// MARK: - Menu bar template (leaf silhouette only)

// Rendered at 44px = 22pt @2x. White silhouette; StatusItemController marks it
// as a template so macOS handles the menu bar tint in light and dark.
let menuBar = renderLeafSilhouette(canvas: 44, paddingFraction: 0.06)
writePNG(menuBar, to: menuBarURL)
