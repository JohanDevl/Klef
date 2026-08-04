// make-iconset.swift — Render the app icon SVG into a macOS .iconset.
//
// The source artwork already carries the macOS icon grid: an 824x824 rounded
// rect inset in a 1024x1024 canvas, with everything outside it transparent. So
// this only rasterises — no masking or insetting. Feeding it full-bleed artwork
// would produce an icon a size step larger than its neighbours.
//
// Each entry is rendered from the vector at its own size rather than downscaled
// from the 1024 raster, so the 16 and 32 px entries stay crisp.
//
// `NSImage` parses SVG natively on macOS 13+, gradients and masks included.
//
// Usage: swift scripts/make-iconset.swift <source.svg> <output.iconset>

import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("Usage: make-iconset.swift <source.svg> <output.iconset>\n".data(using: .utf8)!)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: args[1])
let iconsetURL = URL(fileURLWithPath: args[2])

guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write("Cannot read image: \(sourceURL.path)\n".data(using: .utf8)!)
    exit(1)
}

func render(canvas: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvas,
        pixelsHigh: canvas,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    source.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas))

    return rep
}

// The ten entries iconutil expects. A missing or misnamed file is accepted
// silently and produces an icon that degrades at that size.
let entries: [(name: String, canvas: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for entry in entries {
    guard let rep = render(canvas: entry.canvas),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to render \(entry.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try png.write(to: iconsetURL.appendingPathComponent(entry.name))
}

print("Wrote \(entries.count) sizes to \(iconsetURL.path)")
