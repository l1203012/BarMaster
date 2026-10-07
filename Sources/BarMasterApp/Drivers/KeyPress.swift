import AppKit
import Carbon.HIToolbox

/// Synthesized key presses. Posting events needs the Accessibility permission;
/// without it macOS drops them silently, so we ask on first use.
enum KeyPress {
    static func escape() {
        post(CGKeyCode(kVK_Escape))
    }

    /// Posts `key` with `flags` to the frontmost app.
    static func post(_ key: Int, flags: CGEventFlags = []) {
        post(CGKeyCode(key), flags: flags)
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

    /// The special keys from <IOKit/hidsystem/ev_keymap.h> (NX_KEYTYPE_*).
    enum MediaKey: Int {
        case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    }

    /// Presses a media key the way the keyboard does, so macOS shows its own volume/brightness HUD.
    static func post(_ key: MediaKey) {
        guard ensureTrusted() else { return }
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: (key.rawValue << 16) | (state << 8), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// True when BarMaster may post events; otherwise shows the system prompt once.
    @discardableResult
    static func ensureTrusted() -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }
}
