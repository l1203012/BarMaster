import AppKit

/// The green bottle in the menu bar.
final class StatusItem: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let touchBar: BarController
    private let toggleItem = NSMenuItem(title: "Show on Touch Bar", action: #selector(toggle), keyEquivalent: "")

    init(touchBar: BarController) {
        self.touchBar = touchBar
        super.init()
        item.button?.image = Theme.bottleImage()
        item.button?.toolTip = "BarMaster"

        let menu = NSMenu()
        menu.delegate = self
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit BarMaster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        toggleItem.state = touchBar.isShown ? .on : .off
        toggleItem.isEnabled = SystemTouchBar.isAvailable
    }

    @objc private func toggle() {
        touchBar.toggle()
    }
}
