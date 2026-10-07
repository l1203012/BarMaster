import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItem?
    private var touchBar: BarController?

    /// Created from main.swift's top-level code, before the run loop starts.
    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let touchBar = BarController()
        touchBar.install()
        self.touchBar = touchBar
        statusItem = StatusItem(touchBar: touchBar)
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBar?.uninstall()
    }
}
