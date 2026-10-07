import AppKit

private extension NSTouchBarItem.Identifier {
    static let tray = barMaster("tray")
}

/// Owns the Control Strip bottle and decides which bar is on the Touch Bar.
/// When a supported app comes to the front its bar is presented; any other app
/// gets its own Touch Bar back. While that app shows a sheet or dialog, BarMaster
/// steps aside so the dialog's own Touch Bar buttons are reachable, and comes back
/// when it closes. Everything is driven by notifications; nothing runs on a timer.
final class BarController: NSObject {
    private let watcher = FrontmostAppWatcher()
    private let home = HomeBar()
    private let bars: [SupportedApp: AppBar] = [.chrome: ChromeBar(), .slack: SlackBar(), .ghostty: GhosttyBar()]
    private var frontmost: SupportedApp?
    private var events: AppEvents?
    /// The bar last handed to the system; it may since have been minimized.
    private var presented: AppBar?
    /// The user handed the Touch Bar back; don't take it again until they switch apps.
    private var handedBack = false
    /// Minimized because the app is showing a dialog.
    private var steppedAsideForDialog = false
    private let dialogThrottle = Throttle(delay: 0.1)
    private lazy var trayItem: NSCustomTouchBarItem = {
        let item = NSCustomTouchBarItem(identifier: .tray)
        // The tray button is only on screen while our bar is collapsed, so it always shows.
        item.view = NSButton(image: Theme.bottleImage(), target: self, action: #selector(show))
        return item
    }()

    /// Off from the menu bar: no bar, no Control Strip bottle, app switches ignored.
    var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "disabled") }
        set {
            guard newValue != isEnabled else { return }
            UserDefaults.standard.set(!newValue, forKey: "disabled")
            newValue ? enable() : disable()
        }
    }

    func install() {
        guard SystemTouchBar.isAvailable else {
            NSLog("BarMaster: DFRFoundation unavailable; Touch Bar features disabled")
            return
        }
        for bar in [home] + Array(bars.values) {
            bar.onHandBack = { [weak self] in
                self?.handedBack = true
                self?.hide()
            }
        }
        // Asks once; tab tracking, dialogs and key presses all need it.
        KeyPress.ensureTrusted()
        watcher.start { [weak self] app in
            guard let self, self.isEnabled else { return }
            self.frontmostChanged(app)
        }
        if isEnabled { SystemTouchBar.addToControlStrip(trayItem) }
    }

    func uninstall() {
        disable()
    }

    private func enable() {
        SystemTouchBar.addToControlStrip(trayItem)
        frontmostChanged(NSWorkspace.shared.frontmostApplication)
    }

    private func disable() {
        if let presented { SystemTouchBar.dismiss(presented.touchBar) }
        presented = nil
        events = nil
        currentBar?.appElement = nil
        frontmost = nil
        SystemTouchBar.removeFromControlStrip(trayItem)
    }

    /// Shows the bar for the frontmost app, or the home bar elsewhere.
    @objc func show() {
        handedBack = false
        steppedAsideForDialog = false
        present(currentBar ?? home)
    }

    @objc func hide() {
        if let presented { SystemTouchBar.minimize(presented.touchBar) }
    }

    private var currentBar: AppBar? {
        frontmost.flatMap { bars[$0] }
    }

    private func frontmostChanged(_ running: NSRunningApplication?) {
        // Our own menu opening activates BarMaster; that shouldn't change the bar.
        if running?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        currentBar?.appElement = nil
        frontmost = running?.bundleIdentifier.flatMap(SupportedApp.init(rawValue:))
        handedBack = false
        steppedAsideForDialog = false
        events = nil
        guard let running, let bar = currentBar else {
            hide()
            return
        }
        events = AppEvents(pid: running.processIdentifier) { [weak self] name in self?.appEvent(name) }
        bar.appElement = events?.app
        present(bar)
        updateForDialogs()
    }

    private func appEvent(_ name: String) {
        currentBar?.appEvent(name)
        switch name {
        case kAXSheetCreatedNotification, kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
             kAXUIElementDestroyedNotification:
            // Let the sheet finish attaching before reading the window.
            dialogThrottle.schedule { [weak self] in self?.updateForDialogs() }
        default:
            break
        }
    }

    private func updateForDialogs() {
        guard let events, let bar = currentBar else { return }
        if let dialog = AX.blockingDialog(in: events.app) {
            events.watchDestruction(of: dialog)
            guard !steppedAsideForDialog else { return }
            steppedAsideForDialog = true
            hide()
        } else if steppedAsideForDialog {
            steppedAsideForDialog = false
            if !handedBack { present(bar) }
        }
    }

    private func present(_ bar: AppBar) {
        if let presented, presented !== bar { SystemTouchBar.dismiss(presented.touchBar) }
        bar.refresh()
        SystemTouchBar.present(bar.touchBar, trayItem: .tray)
        presented = bar
    }
}
