import AppKit

private extension NSTouchBarItem.Identifier {
    static let escape = Self("io.github.l1203012.barmaster.escape")
    static let title = Self("io.github.l1203012.barmaster.title")
}

/// One Touch Bar layout: for a supported app, or the home bar (`app == nil`)
/// shown when the bottle is tapped anywhere else. Built once and reused.
/// Milestone 3: Esc + the app's name; the real controls arrive in milestones 4–6.
final class AppBar: NSObject, NSTouchBarDelegate {
    let app: SupportedApp?
    private(set) lazy var touchBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [.escape, .fixedSpaceLarge, .title]
        return bar
    }()

    init(app: SupportedApp?) {
        self.app = app
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .escape:
            // System-modal bars hide the virtual Esc key, and Touch Bar MacBooks have no real one.
            return button(identifier, title: "esc", action: #selector(escape))
        case .title:
            let title = app.map { "🥃 \($0.name)" } ?? "🥃 BarMaster: open Chrome, Slack or Ghostty"
            let item = button(identifier, title: title, action: nil)
            (item.view as? NSButton)?.bezelColor = Theme.touchBarGreen
            return item
        default:
            return nil
        }
    }

    @objc private func escape() {
        KeyPress.escape()
    }

    private func button(_ identifier: NSTouchBarItem.Identifier, title: String, action: Selector?) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = NSButton(title: title, target: action == nil ? nil : self, action: action)
        return item
    }
}
