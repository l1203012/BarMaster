// Renders SF Symbols as white-on-transparent PNGs for Scripts/make_screenshots.py.
//
//   swift Scripts/render_symbols.swift <out dir> <point size> <symbol>…
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 4, let size = Double(arguments[2]) else {
    print("usage: render_symbols.swift <out dir> <point size> <symbol>…")
    exit(1)
}
let outDir = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for name in arguments.dropFirst(3) {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        print("missing symbol: \(name)")
        continue
    }
    let width = Int(symbol.size.width.rounded(.up)), height = Int(symbol.size.height.rounded(.up))
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    symbol.draw(in: rect)
    NSColor.white.set()
    rect.fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("\(name).png"))
}
