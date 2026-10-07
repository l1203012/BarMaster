import AppKit

extension NSTouchBarItem.Identifier {
    static func barMaster(_ name: String) -> Self {
        Self("io.github.l1203012.barmaster.\(name)")
    }

    static let escape = barMaster("escape")
    static let brightnessDown = barMaster("brightness-down")
    static let brightnessUp = barMaster("brightness-up")
    static let volumeDown = barMaster("volume-down")
    static let volumeUp = barMaster("volume-up")
    static let mute = barMaster("mute")
    static let handBack = barMaster("hand-back")
    static let systemControls = barMaster("system-controls")
}

/// One full-width Touch Bar layout: Esc, the app's own items, then the
/// brightness/volume keys the Control Strip would normally provide and a
/// bottle that hands the Touch Bar back. Subclasses supply the middle part.
/// Built once and reused; `refresh()` runs each time the bar is presented.
class AppBar: NSObject, NSTouchBarDelegate {
    /// Set by BarController: collapse the bar back into the Control Strip.
    var onHandBack: (() -> Void)?
    /// The app's accessibility element while it is frontmost (nil without the permission).
    var appElement: AXUIElement?

    private(set) lazy var touchBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [.escape, .fixedSpaceSmall] + appItems + [
            .flexibleSpace, .systemControls, .handBack,
        ]
        return bar
    }()

    /// The app-specific items between Esc and the system keys.
    var appItems: [NSTouchBarItem.Identifier] { [] }

    func makeAppItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? { nil }

    /// Re-reads app state (e.g. tab titles). Called on present; never on a timer.
    func refresh() {}

    /// An accessibility notification (`kAX…Notification`) from the app while it is frontmost.
    func appEvent(_ name: String) {}

    final func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        // System-modal bars hide the virtual Esc key, and Touch Bar MacBooks have no real one.
        case .escape:
            let item = button(identifier, title: "esc", action: #selector(escape))
            item.view.widthAnchor.constraint(equalToConstant: 56).isActive = true
            return item
        case .brightnessDown: return compact(identifier, "sun.min", "Brightness down", #selector(brightnessDown))
        case .brightnessUp: return compact(identifier, "sun.max", "Brightness up", #selector(brightnessUp))
        case .volumeDown: return compact(identifier, "speaker.wave.1", "Volume down", #selector(volumeDown))
        case .volumeUp: return compact(identifier, "speaker.wave.3", "Volume up", #selector(volumeUp))
        case .mute: return compact(identifier, "speaker.slash", "Mute", #selector(mute))
        case .systemControls: return systemControls()
        case .handBack:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(image: Theme.bottleImage(), target: self, action: #selector(handBack))
            item.view.widthAnchor.constraint(equalToConstant: 40).isActive = true
            item.customizationLabel = "Show app's own Touch Bar"
            return item
        default: return makeAppItem(identifier)
        }
    }

    // MARK: Item helpers for subclasses

    func button(_ identifier: NSTouchBarItem.Identifier, title: String, action: Selector) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = NSButton(title: title, target: self, action: action)
        item.customizationLabel = title
        return item
    }

    func button(_ identifier: NSTouchBarItem.Identifier, symbol: String, label: String, title: String? = nil,
                action: Selector) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = title.map { NSButton(title: $0, image: image, target: self, action: action) }
            ?? NSButton(image: image, target: self, action: action)
        button.imagePosition = title == nil ? .imageOnly : .imageLeading
        // The default 72pt width doesn't fit a full layout plus the system keys on one bar.
        if title == nil { button.widthAnchor.constraint(equalToConstant: 40).isActive = true }
        item.view = button
        item.customizationLabel = label
        return item
    }

    /// Brightness and volume behind one button, to leave room for the app's own items.
    private func systemControls() -> NSTouchBarItem {
        let item = NSPopoverTouchBarItem(identifier: .systemControls)
        item.collapsedRepresentationImage = NSImage(systemSymbolName: "slider.horizontal.3",
                                                    accessibilityDescription: "Brightness and volume")
        item.customizationLabel = "Brightness and volume"
        item.collapsedRepresentation.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let popover = NSTouchBar()
        popover.delegate = self
        popover.defaultItemIdentifiers = [
            .brightnessDown, .brightnessUp, .fixedSpaceLarge, .volumeDown, .volumeUp, .mute,
        ]
        item.popoverTouchBar = popover
        return item
    }

    private func compact(_ identifier: NSTouchBarItem.Identifier, _ symbol: String, _ label: String,
                         _ action: Selector) -> NSCustomTouchBarItem {
        let item = button(identifier, symbol: symbol, label: label, action: action)
        item.view.constraints.forEach { $0.isActive = false }
        item.view.widthAnchor.constraint(equalToConstant: 56).isActive = true
        return item
    }

    @objc private func escape() { KeyPress.escape() }
    @objc private func brightnessDown() { KeyPress.post(.brightnessDown) }
    @objc private func brightnessUp() { KeyPress.post(.brightnessUp) }
    @objc private func volumeDown() { KeyPress.post(.volumeDown) }
    @objc private func volumeUp() { KeyPress.post(.volumeUp) }
    @objc private func mute() { KeyPress.post(.mute) }
    @objc private func handBack() { onHandBack?() }
}

/// Shown when the Control Strip bottle is tapped in an app BarMaster doesn't know.
final class HomeBar: AppBar {
    private static let hint = NSTouchBarItem.Identifier.barMaster("hint")

    override var appItems: [NSTouchBarItem.Identifier] { [Self.hint] }

    override func makeAppItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = NSTextField(labelWithString: "BarMaster works in Chrome, Slack and Ghostty")
        return item
    }
}
