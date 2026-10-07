import AppKit
import ServiceManagement

/// The green bottle in the menu bar.
@MainActor
final class StatusItem: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let touchBar: BarController
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let slackItem = NSMenuItem(title: "Connect Slack…", action: #selector(slackAction), keyEquivalent: "")
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
        let editItem = NSMenuItem(title: "Edit Chrome Buttons…", action: #selector(editChromeButtons), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)
        slackItem.target = self
        menu.addItem(slackItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit BarMaster", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        enabledItem.state = touchBar.isEnabled ? .on : .off
        enabledItem.isEnabled = SystemTouchBar.isAvailable
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        switch touchBar.slack.status {
        case .notConfigured: slackItem.title = "Connect Slack…"
        case .connecting: slackItem.title = "Disconnect Slack (connecting…)"
        case .connected: slackItem.title = "Disconnect Slack"
        case .failed(let message): slackItem.title = "Disconnect Slack (\(message))"
        }
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

    @objc private func slackAction() {
        if touchBar.slack.status == .notConfigured {
            SlackSetup.run(touchBar.slack)
        } else {
            SlackSetup.disconnect(touchBar.slack)
        }
    }

    @objc private func editChromeButtons() {
        touchBar.editChromeButtons()
    }

    @objc private func toggleEnabled() {
        touchBar.isEnabled.toggle()
        item.button?.appearsDisabled = !touchBar.isEnabled
    }
}
