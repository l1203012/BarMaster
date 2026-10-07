import AppKit

/// The private DFRFoundation / NSTouchBar calls that let BarMaster show its own
/// bar while another app is frontmost, and put a button in the Control Strip.
/// This is the only file that touches private API (see Docs/PLAN.md §1); it is
/// resolved at runtime, so a missing symbol degrades to "no Touch Bar" instead
/// of a crash.
enum SystemTouchBar {
    private static let dfr = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    private typealias SetPresence = @convention(c) (CFString, Bool) -> Void
    private typealias ShowsCloseBox = @convention(c) (Bool) -> Void
    private typealias Present = @convention(c) (AnyClass, Selector, NSTouchBar, NSString) -> Void
    private typealias TakeBar = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
    private typealias TakeItem = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void

    static var isAvailable: Bool {
        dfr != nil && classMethod(NSTouchBar.self, "presentSystemModalTouchBar:systemTrayItemIdentifier:") != nil
    }

    /// Adds `item` to the Control Strip (the right-hand group next to brightness/volume).
    static func addToControlStrip(_ item: NSTouchBarItem) {
        if let (sel, imp) = classMethod(NSTouchBarItem.self, "addSystemTrayItem:") {
            unsafeBitCast(imp, to: TakeItem.self)(NSTouchBarItem.self, sel, item)
        }
        setControlStripPresence(item.identifier, true)
    }

    static func removeFromControlStrip(_ item: NSTouchBarItem) {
        setControlStripPresence(item.identifier, false)
        if let (sel, imp) = classMethod(NSTouchBarItem.self, "removeSystemTrayItem:") {
            unsafeBitCast(imp, to: TakeItem.self)(NSTouchBarItem.self, sel, item)
        }
    }

    /// Shows `bar` over whatever app is frontmost, attached to the Control Strip item.
    static func present(_ bar: NSTouchBar, trayItem: NSTouchBarItem.Identifier) {
        if let showsCloseBox = function("DFRSystemModalShowsCloseBoxWhenFrontMost", as: ShowsCloseBox.self) {
            showsCloseBox(false)
        }
        guard let (sel, imp) = classMethod(NSTouchBar.self, "presentSystemModalTouchBar:systemTrayItemIdentifier:")
        else { return }
        unsafeBitCast(imp, to: Present.self)(NSTouchBar.self, sel, bar, trayItem.rawValue as NSString)
    }

    /// Collapses `bar` back into its Control Strip button; the frontmost app's own bar returns.
    static func minimize(_ bar: NSTouchBar) {
        call(NSTouchBar.self, "minimizeSystemModalTouchBar:", bar)
    }

    static func dismiss(_ bar: NSTouchBar) {
        call(NSTouchBar.self, "dismissSystemModalTouchBar:", bar)
    }

    private static func setControlStripPresence(_ identifier: NSTouchBarItem.Identifier, _ present: Bool) {
        function("DFRElementSetControlStripPresenceForIdentifier", as: SetPresence.self)?(
            identifier.rawValue as CFString, present)
    }

    private static func call(_ cls: AnyClass, _ name: String, _ bar: NSTouchBar) {
        guard let (sel, imp) = classMethod(cls, name) else { return }
        unsafeBitCast(imp, to: TakeBar.self)(cls, sel, bar)
    }

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let dfr, let symbol = dlsym(dfr, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private static func classMethod(_ cls: AnyClass, _ name: String) -> (Selector, IMP)? {
        let sel = NSSelectorFromString(name)
        guard let method = class_getClassMethod(cls, sel) else { return nil }
        return (sel, method_getImplementation(method))
    }
}
