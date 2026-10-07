import CoreGraphics
import Carbon.HIToolbox

/// A shortcut written as text, e.g. "cmd+shift+t", "k", "alt+left".
struct KeyCombo {
    let key: CGKeyCode
    let flags: CGEventFlags

    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "shift": .maskShift,
        "alt": .maskAlternate, "opt": .maskAlternate, "option": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl,
    ]

    private static let keys: [String: Int] = {
        var keys: [String: Int] = [
            "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space,
            "escape": kVK_Escape, "esc": kVK_Escape, "delete": kVK_Delete, "backspace": kVK_Delete,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal,
            ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, ";": kVK_ANSI_Semicolon,
            "'": kVK_ANSI_Quote, "`": kVK_ANSI_Grave, "\\": kVK_ANSI_Backslash,
        ]
        let letters = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
                       kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
                       kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
                       kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z]
        for (offset, code) in letters.enumerated() {
            keys[String(UnicodeScalar(UInt8(ascii: "a") + UInt8(offset)))] = code
        }
        let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                      kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (digit, code) in digits.enumerated() { keys[String(digit)] = code }
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (index, code) in functionKeys.enumerated() { keys["f\(index + 1)"] = code }
        return keys
    }()

    init?(_ text: String) {
        var flags: CGEventFlags = []
        var key: Int?
        for part in text.lowercased().split(separator: "+").map(String.init) {
            if let modifier = Self.modifiers[part] {
                flags.insert(modifier)
            } else if key == nil, let code = Self.keys[part] {
                key = code
            } else {
                return nil
            }
        }
        guard let key else { return nil }
        self.key = CGKeyCode(key)
        self.flags = flags
    }
}
