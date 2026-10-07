import AppKit
import Carbon.HIToolbox

/// Synthesized key presses. Posting events needs the Accessibility permission;
/// without it macOS drops them silently, so we ask on first use.
enum KeyPress {
    static func escape() {
        post(CGKeyCode(kVK_Escape))
    }

    static func post(_ key: CGKeyCode, flags: CGEventFlags = []) {
        guard ensureTrusted() else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// True when BarMaster may post events; otherwise shows the system prompt once.
    @discardableResult
    static func ensureTrusted() -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }
}
