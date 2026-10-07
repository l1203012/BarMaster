import AppKit

private extension NSTouchBarItem.Identifier {
    static let tray = Self("io.github.l1203012.barmaster.tray")
    static let escape = Self("io.github.l1203012.barmaster.escape")
    static let hello = Self("io.github.l1203012.barmaster.hello")
}

/// Owns the Control Strip bottle and BarMaster's system-modal bar.
/// Milestone 2: the bar is Esc + a hello button; per-app layouts come next.
/// Nothing here runs on a timer: work happens only on taps and menu actions.
final class BarController: NSObject, NSTouchBarDelegate {
    /// Read from the bar itself: the system × close box can minimize it behind our back.
    var isShown: Bool { bar.isVisible }
    private lazy var trayItem: NSCustomTouchBarItem = {
        let item = NSCustomTouchBarItem(identifier: .tray)
        // The tray button is only on screen while our bar is collapsed, so it always shows.
        item.view = NSButton(image: Theme.bottleImage(), target: self, action: #selector(show))
        return item
    }()
    private lazy var bar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [.escape, .fixedSpaceLarge, .hello]
        return bar
    }()

    func install() {
        guard SystemTouchBar.isAvailable else {
            NSLog("BarMaster: DFRFoundation unavailable; Touch Bar features disabled")
            return
        }
        SystemTouchBar.addToControlStrip(trayItem)
    }

    func uninstall() {
        SystemTouchBar.dismiss(bar)
        SystemTouchBar.removeFromControlStrip(trayItem)
    }

    @objc func toggle() {
        isShown ? hide() : show()
    }

    @objc func show() {
        SystemTouchBar.present(bar, trayItem: .tray)
    }

    @objc func hide() {
        SystemTouchBar.minimize(bar)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .escape:
            // System-modal bars hide the virtual Esc key, and Touch Bar MacBooks have no real one.
            return button(identifier, title: "esc", action: #selector(escape))
        case .hello:
            let item = button(identifier, title: "🥃 Hello from BarMaster", action: #selector(hide))
            (item.view as? NSButton)?.bezelColor = Theme.touchBarGreen
            return item
        default:
            return nil
        }
    }

    @objc private func escape() {
        KeyPress.escape()
    }

    private func button(_ identifier: NSTouchBarItem.Identifier, title: String, action: Selector) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = NSButton(title: title, target: self, action: action)
        return item
    }
}
