import AppKit
import Carbon.HIToolbox

/// Slack has no AppleScript dictionary, so this bar presses Slack's own shortcuts.
final class SlackBar: AppBar {
    private static let mentions = NSTouchBarItem.Identifier.barMaster("slack.mentions")
    private static let unreads = NSTouchBarItem.Identifier.barMaster("slack.unreads")
    private static let threads = NSTouchBarItem.Identifier.barMaster("slack.threads")
    private static let directMessages = NSTouchBarItem.Identifier.barMaster("slack.dms")
    private static let previousUnread = NSTouchBarItem.Identifier.barMaster("slack.previous-unread")
    private static let nextUnread = NSTouchBarItem.Identifier.barMaster("slack.next-unread")
    private static let jump = NSTouchBarItem.Identifier.barMaster("slack.jump")
    private static let back = NSTouchBarItem.Identifier.barMaster("slack.back")
    private static let forward = NSTouchBarItem.Identifier.barMaster("slack.forward")

    override var appItems: [NSTouchBarItem.Identifier] {
        [Self.back, Self.forward, .fixedSpaceSmall,
         Self.mentions, Self.unreads, Self.threads, Self.directMessages, .fixedSpaceSmall,
         Self.previousUnread, Self.nextUnread, Self.jump]
    }

    override func makeAppItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.mentions: return button(identifier, symbol: "at", label: "Latest mentions", title: "Mentions", action: #selector(mentions))
        case Self.unreads: return button(identifier, symbol: "tray.full", label: "All unreads", action: #selector(unreads))
        case Self.threads: return button(identifier, symbol: "bubble.left.and.bubble.right", label: "Threads", action: #selector(threads))
        case Self.directMessages: return button(identifier, symbol: "person.2", label: "Direct messages", action: #selector(directMessages))
        case Self.previousUnread: return button(identifier, symbol: "chevron.up", label: "Previous unread channel", action: #selector(previousUnread))
        case Self.nextUnread: return button(identifier, symbol: "chevron.down", label: "Next unread channel", action: #selector(nextUnread))
        case Self.jump: return button(identifier, symbol: "magnifyingglass", label: "Jump to…", action: #selector(jump))
        case Self.back: return button(identifier, symbol: "arrow.left", label: "Back", action: #selector(back))
        case Self.forward: return button(identifier, symbol: "arrow.right", label: "Forward", action: #selector(forward))
        default: return nil
        }
    }

    // Activity → Mentions; the newest mention is at the top. (Plan v2: jump straight to it via the Web API.)
    @objc private func mentions() { KeyPress.post(kVK_ANSI_M, flags: [.maskCommand, .maskShift]) }
    @objc private func unreads() { KeyPress.post(kVK_ANSI_A, flags: [.maskCommand, .maskShift]) }
    @objc private func threads() { KeyPress.post(kVK_ANSI_T, flags: [.maskCommand, .maskShift]) }
    @objc private func directMessages() { KeyPress.post(kVK_ANSI_K, flags: [.maskCommand, .maskShift]) }
    @objc private func previousUnread() { KeyPress.post(kVK_UpArrow, flags: [.maskAlternate, .maskShift]) }
    @objc private func nextUnread() { KeyPress.post(kVK_DownArrow, flags: [.maskAlternate, .maskShift]) }
    @objc private func jump() { KeyPress.post(kVK_ANSI_K, flags: .maskCommand) }
    @objc private func back() { KeyPress.post(kVK_ANSI_LeftBracket, flags: .maskCommand) }
    @objc private func forward() { KeyPress.post(kVK_ANSI_RightBracket, flags: .maskCommand) }
}
