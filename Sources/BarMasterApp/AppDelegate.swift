import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItem?
    private var touchBar: BarController?

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
