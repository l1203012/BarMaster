import AppKit
import Carbon.HIToolbox

/// Slack: a channel switcher fed by the Web API, plus Slack's own shortcuts
/// (it has no AppleScript dictionary). Mentions show on every bar (see AppBar).
final class SlackBar: AppBar {
    private static let channels = NSTouchBarItem.Identifier.barMaster("slack.channels")
    private static let connect = NSTouchBarItem.Identifier.barMaster("slack.connect")
    private static let unreads = NSTouchBarItem.Identifier.barMaster("slack.unreads")
    private static let threads = NSTouchBarItem.Identifier.barMaster("slack.threads")
    private static let previousUnread = NSTouchBarItem.Identifier.barMaster("slack.previous-unread")
    private static let nextUnread = NSTouchBarItem.Identifier.barMaster("slack.next-unread")
    private static let jump = NSTouchBarItem.Identifier.barMaster("slack.jump")
    private static let back = NSTouchBarItem.Identifier.barMaster("slack.back")
    private static let forward = NSTouchBarItem.Identifier.barMaster("slack.forward")

    private let slack: Slack
    private let channelStrip = TabScrubberItem(identifier: SlackBar.channels, width: 330)
    private var shownChannels: [Slack.Channel] = []

    init(slack: Slack) {
        self.slack = slack
        super.init()
        channelStrip.onSelect = { [weak self] index in
            guard let self, self.shownChannels.indices.contains(index) else { return }
            self.slack.open(channel: self.shownChannels[index].id)
        }
    }

    override var appItems: [NSTouchBarItem.Identifier] {
        [Self.back, Self.forward, .fixedSpaceSmall,
         slack.isConfigured ? Self.channels : Self.connect, .fixedSpaceSmall,
         Self.unreads, Self.threads, Self.previousUnread, Self.nextUnread, Self.jump]
    }

    override func makeAppItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.channels: return channelStrip
        case Self.connect: return button(identifier, symbol: "link", label: "Connect Slack", title: "Connect Slack…", action: #selector(connect))
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

    override func refresh() {
        Task { @MainActor in self.slack.refreshChannels() }
        slackChanged()
    }

    /// Called by BarController whenever Slack's channels or connection change.
    func slackChanged() {
        let wantsChannels = slack.isConfigured
        if touchBar.defaultItemIdentifiers.contains(Self.channels) != wantsChannels { reloadItems() }
        guard slack.channels != shownChannels else { return }
        shownChannels = slack.channels
        channelStrip.update(titles: shownChannels.map(\.name), selected: -1)
    }

    @objc private func connect() { SlackSetup.run(slack) }
    @objc private func unreads() { KeyPress.post(kVK_ANSI_A, flags: [.maskCommand, .maskShift]) }
    @objc private func threads() { KeyPress.post(kVK_ANSI_T, flags: [.maskCommand, .maskShift]) }
    @objc private func previousUnread() { KeyPress.post(kVK_UpArrow, flags: [.maskAlternate, .maskShift]) }
    @objc private func nextUnread() { KeyPress.post(kVK_DownArrow, flags: [.maskAlternate, .maskShift]) }
    @objc private func jump() { KeyPress.post(kVK_ANSI_K, flags: .maskCommand) }
    @objc private func back() { KeyPress.post(kVK_ANSI_LeftBracket, flags: .maskCommand) }
    @objc private func forward() { KeyPress.post(kVK_ANSI_RightBracket, flags: .maskCommand) }
}
