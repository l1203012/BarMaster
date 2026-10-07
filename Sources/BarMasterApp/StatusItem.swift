import AppKit
import ServiceManagement

/// The green bottle in the menu bar.
final class StatusItem: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let touchBar: BarController
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")

    init(touchBar: BarController) {
        self.touchBar = touchBar
        super.init()
        item.button?.image = Theme.bottleImage()
        item.button?.toolTip = "BarMaster"
        item.button?.appearsDisabled = !touchBar.isEnabled

        let menu = NSMenu()
        menu.delegate = self
        enabledItem.target = self
        menu.addItem(enabledItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit BarMaster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        enabledItem.state = touchBar.isEnabled ? .on : .off
        enabledItem.isEnabled = SystemTouchBar.isAvailable
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleOpenAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("BarMaster: Open at Login failed: %@", error.localizedDescription)
        }
    }

    @objc private func toggleEnabled() {
        touchBar.isEnabled.toggle()
        item.button?.appearsDisabled = !touchBar.isEnabled
    }
}
