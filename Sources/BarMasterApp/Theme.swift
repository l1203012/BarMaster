import AppKit

/// BarMaster's green. Defined once; everything else reads it from here.
enum Theme {
    static let green = NSColor(name: "BarMasterGreen") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x2F / 255, green: 0xBF / 255, blue: 0x6B / 255, alpha: 1)
            : NSColor(srgbRed: 0x1E / 255, green: 0x8E / 255, blue: 0x4F / 255, alpha: 1)
    }

    /// The Touch Bar is always dark, so its buttons use the dark-mode green.
    static let touchBarGreen = NSColor(srgbRed: 0x2F / 255, green: 0xBF / 255, blue: 0x6B / 255, alpha: 1)

    /// Bottle glyph from the bundle (template image), or an SF Symbol before the icon exists.
    static func bottleImage() -> NSImage {
        if let image = Bundle.main.image(forResource: "MenuBarIcon") {
            image.isTemplate = true
            return image
        }
        let fallback = NSImage(systemSymbolName: "wineglass", accessibilityDescription: "BarMaster")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        fallback.isTemplate = true
        return fallback
    }
}
