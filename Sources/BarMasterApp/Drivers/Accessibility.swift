import AppKit
import ApplicationServices

/// Small typed readers over the Accessibility C API.
enum AX {
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)  // swiftlint:disable:this force_cast (type checked above)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (value(element, attribute) as? [AnyObject] ?? []).compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil  // swiftlint:disable:this force_cast
        }
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    /// The sheet or dialog blocking `app`'s focused window, if any. Covers:
    /// - a sheet that has taken focus itself (Ghostty's "Close tab?"),
    /// - a sheet attached to the focused window,
    /// - a standard dialog window,
    /// - Chrome's dialogs ("This page says…", permission prompts): a separate
    ///   focused window with no subrole (`AXUnknown`) that isn't the main window.
    static func blockingDialog(in app: AXUIElement) -> AXUIElement? {
        guard let window = element(app, kAXFocusedWindowAttribute) else { return nil }
        if string(window, kAXRoleAttribute) == kAXSheetRole { return window }
        let subrole = string(window, kAXSubroleAttribute)
        if subrole == kAXDialogSubrole || subrole == kAXSystemDialogSubrole { return window }
        if subrole == kAXUnknownSubrole, bool(window, kAXMainAttribute) == false { return window }
        return elements(window, kAXChildrenAttribute).first { string($0, kAXRoleAttribute) == kAXSheetRole }
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (value(element, attribute) as? NSNumber)?.boolValue
    }

    /// The directory a terminal window shows as its title-bar proxy icon.
    static func documentPath(ofFocusedWindowIn app: AXUIElement) -> String? {
        guard let window = element(app, kAXFocusedWindowAttribute),
              let document = string(window, kAXDocumentAttribute) else { return nil }
        return URL(string: document)?.path
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}

/// Accessibility notifications from one running app: window focus and title
/// changes, and sheets/dialogs opening and closing. Delivered on the main run
/// loop by the system, so BarMaster never has to poll.
final class AppEvents {
    let app: AXUIElement
    private var observer: AXObserver?
    private let onEvent: (String) -> Void

    static let appNotifications = [
        kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXTitleChangedNotification,
        kAXWindowCreatedNotification, kAXSheetCreatedNotification,
    ]

    /// Nil when BarMaster lacks the Accessibility permission.
    init?(pid: pid_t, notifications: [String] = AppEvents.appNotifications, onEvent: @escaping (String) -> Void) {
        guard AXIsProcessTrusted() else { return nil }
        app = AXUIElementCreateApplication(pid)
        self.onEvent = onEvent
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, name, refcon in
            guard let refcon else { return }
            Unmanaged<AppEvents>.fromOpaque(refcon).takeUnretainedValue().onEvent(name as String)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return nil }
        self.observer = observer
        for name in notifications {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// Also report when `element` (e.g. a dialog) goes away.
    func watchDestruction(of element: AXUIElement) {
        guard let observer else { return }
        AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
    }

    private var refcon: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    deinit {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }
}
