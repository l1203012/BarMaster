import AppKit
import Carbon.HIToolbox

/// Slack has no AppleScript dictionary, so this bar drives the Slack client
/// with its own shortcuts. The switcher lists your favourites (Slack.json) and
/// the conversations you were recently mentioned in; mentions themselves show
/// on every bar (see AppBar and Slack).
final class SlackBar: AppBar {
    private static let channels = NSTouchBarItem.Identifier.barMaster("slack.channels")
    private static let mentions = NSTouchBarItem.Identifier.barMaster("slack.mentions")
    private static let unreads = NSTouchBarItem.Identifier.barMaster("slack.unreads")
    private static let threads = NSTouchBarItem.Identifier.barMaster("slack.threads")
    private static let previousUnread = NSTouchBarItem.Identifier.barMaster("slack.previous-unread")
    private static let nextUnread = NSTouchBarItem.Identifier.barMaster("slack.next-unread")
    private static let jump = NSTouchBarItem.Identifier.barMaster("slack.jump")
    private static let back = NSTouchBarItem.Identifier.barMaster("slack.back")
    private static let forward = NSTouchBarItem.Identifier.barMaster("slack.forward")

    private let slack: Slack
    let favourites = SlackChannels()
    private let channelStrip = TabScrubberItem(identifier: SlackBar.channels, width: 330)
    private var shown: [String] = []

    init(slack: Slack) {
        self.slack = slack
        super.init()
        channelStrip.onSelect = { [weak self] index in
            guard let self, self.shown.indices.contains(index) else { return }
            self.slack.open(conversation: self.shown[index])
        }
        favourites.onChange = { [weak self] in self?.slackChanged() }
        slackChanged()
    }

    override var appItems: [NSTouchBarItem.Identifier] {
        [Self.back, Self.forward, .fixedSpaceSmall,
         Self.mentions, Self.channels, .fixedSpaceSmall,
         Self.unreads, Self.threads, Self.previousUnread, Self.nextUnread, Self.jump]
    }

    override func makeAppItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.channels: return channelStrip
        case Self.mentions: return button(identifier, symbol: "at", label: "Activity: mentions", action: #selector(mentions))
        case Self.unreads: return button(identifier, symbol: "tray.full", label: "All unreads", action: #selector(unreads))
        case Self.threads: return button(identifier, symbol: "bubble.left.and.bubble.right", label: "Threads", action: #selector(threads))
        case Self.previousUnread: return button(identifier, symbol: "chevron.up", label: "Previous unread channel", action: #selector(previousUnread))
        case Self.nextUnread: return button(identifier, symbol: "chevron.down", label: "Next unread channel", action: #selector(nextUnread))
        case Self.jump: return button(identifier, symbol: "magnifyingglass", label: "Jump to…", action: #selector(jump))
        case Self.back: return button(identifier, symbol: "arrow.left", label: "Back", action: #selector(back))
        case Self.forward: return button(identifier, symbol: "arrow.right", label: "Forward", action: #selector(forward))
        default: return nil
        }
    }

    /// Favourites first, then recent mention conversations not already listed.
    func slackChanged() {
        let list = favourites.favourites + slack.recent.filter { !favourites.favourites.contains($0) }
        guard list != shown else { return }
        shown = list
        channelStrip.update(titles: list, selected: -1)
    }

    @objc private func mentions() { KeyPress.post(kVK_ANSI_M, flags: [.maskCommand, .maskShift]) }
    @objc private func unreads() { KeyPress.post(kVK_ANSI_A, flags: [.maskCommand, .maskShift]) }
    @objc private func threads() { KeyPress.post(kVK_ANSI_T, flags: [.maskCommand, .maskShift]) }
    @objc private func previousUnread() { KeyPress.post(kVK_UpArrow, flags: [.maskAlternate, .maskShift]) }
    @objc private func nextUnread() { KeyPress.post(kVK_DownArrow, flags: [.maskAlternate, .maskShift]) }
    @objc private func jump() { KeyPress.post(kVK_ANSI_K, flags: .maskCommand) }
    @objc private func back() { KeyPress.post(kVK_ANSI_LeftBracket, flags: .maskCommand) }
    @objc private func forward() { KeyPress.post(kVK_ANSI_RightBracket, flags: .maskCommand) }
}
