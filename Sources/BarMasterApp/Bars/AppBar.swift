import AppKit

extension NSTouchBarItem.Identifier {
    static func barMaster(_ name: String) -> Self {
        Self("io.github.l1203012.barmaster.\(name)")
    }

    static let escape = barMaster("escape")
    static let handBack = barMaster("hand-back")
}

/// One full-width Touch Bar layout: Esc, the app's own items, then a bottle
/// that hands the Touch Bar back. Subclasses supply the middle part.
/// Built once and reused; `refresh()` runs each time the bar is presented.
class AppBar: NSObject, NSTouchBarDelegate {
    /// Set by BarController: collapse the bar back into the Control Strip.
    var onHandBack: (() -> Void)?
    /// The app's accessibility element while it is frontmost (nil without the permission).
    var appElement: AXUIElement?

    private(set) lazy var touchBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = itemIdentifiers
        return bar
    }()

    private var itemIdentifiers: [NSTouchBarItem.Identifier] {
        [.escape, .fixedSpaceSmall] + appItems + [.flexibleSpace, .handBack]
    }

    /// Call after `appItems` changes; the Touch Bar updates in place.
    func reloadItems() {
        touchBar.defaultItemIdentifiers = itemIdentifiers
    }

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

    @objc private func escape() { KeyPress.escape() }
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
