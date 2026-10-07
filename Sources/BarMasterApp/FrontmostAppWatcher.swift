import AppKit

/// Tells BarMaster when another app comes to the front. Purely event-driven:
/// one NSWorkspace notification, no polling.
final class FrontmostAppWatcher {
    private var observer: NSObjectProtocol?

    /// Calls `onChange` now with the current frontmost app, then on every switch.
    func start(_ onChange: @escaping (NSRunningApplication?) -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            onChange(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        onChange(NSWorkspace.shared.frontmostApplication)
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
