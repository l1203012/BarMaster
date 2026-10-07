import AppKit

private extension NSTouchBarItem.Identifier {
    static let tray = Self("io.github.l1203012.barmaster.tray")
}

/// Owns the Control Strip bottle and decides which bar is on the Touch Bar.
/// When a supported app comes to the front its bar is presented; any other app
/// gets its own Touch Bar back. Nothing here runs on a timer.
final class BarController: NSObject {
    private let watcher = FrontmostAppWatcher()
    private let home = AppBar(app: nil)
    private lazy var bars = Dictionary(uniqueKeysWithValues: SupportedApp.allCases.map { ($0, AppBar(app: $0)) })
    private var frontmost: SupportedApp?
    /// The bar last handed to the system; it may since have been minimized.
    private var presented: AppBar?
    private lazy var trayItem: NSCustomTouchBarItem = {
        let item = NSCustomTouchBarItem(identifier: .tray)
        // The tray button is only on screen while our bar is collapsed, so it always shows.
        item.view = NSButton(image: Theme.bottleImage(), target: self, action: #selector(show))
        return item
    }()

    /// Read from the bar itself: the system × close box can minimize it behind our back.
    var isShown: Bool { presented?.touchBar.isVisible ?? false }

    func install() {
        guard SystemTouchBar.isAvailable else {
            NSLog("BarMaster: DFRFoundation unavailable; Touch Bar features disabled")
            return
        }
        SystemTouchBar.addToControlStrip(trayItem)
        watcher.start { [weak self] app in self?.frontmostChanged(app) }
    }

    func uninstall() {
        if let presented { SystemTouchBar.dismiss(presented.touchBar) }
        SystemTouchBar.removeFromControlStrip(trayItem)
    }

    @objc func toggle() {
        isShown ? hide() : show()
    }

    /// Shows the bar for the frontmost app, or the home bar elsewhere.
    @objc func show() {
        present(frontmost.flatMap { bars[$0] } ?? home)
    }

    @objc func hide() {
        if let presented { SystemTouchBar.minimize(presented.touchBar) }
    }

    private func frontmostChanged(_ running: NSRunningApplication?) {
        // Our own menu opening activates BarMaster; that shouldn't change the bar.
        if running?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        frontmost = running?.bundleIdentifier.flatMap(SupportedApp.init(rawValue:))
        if let app = frontmost, let bar = bars[app] {
            present(bar)
        } else {
            hide()
        }
    }

    private func present(_ bar: AppBar) {
        if let presented, presented !== bar { SystemTouchBar.dismiss(presented.touchBar) }
        SystemTouchBar.present(bar.touchBar, trayItem: .tray)
        presented = bar
    }
}
