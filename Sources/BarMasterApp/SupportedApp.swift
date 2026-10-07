/// The apps BarMaster has a layout for, keyed by bundle identifier.
enum SupportedApp: String, CaseIterable {
    case chrome = "com.google.Chrome"
    case slack = "com.tinyspeck.slackmacgap"
    case ghostty = "com.mitchellh.ghostty"

    var name: String {
        switch self {
        case .chrome: return "Chrome"
        case .slack: return "Slack"
        case .ghostty: return "Ghostty"
        }
    }
}
