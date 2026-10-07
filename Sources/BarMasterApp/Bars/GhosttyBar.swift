import AppKit

/// Ghostty through its AppleScript dictionary (Ghostty ≥ 1.3). `perform action`
/// runs Ghostty's own keybind actions, so these behave exactly like its shortcuts.
final class GhosttyBar: AppBar {
    private static let previousTab = NSTouchBarItem.Identifier.barMaster("ghostty.previous-tab")
    private static let nextTab = NSTouchBarItem.Identifier.barMaster("ghostty.next-tab")
    private static let tabs = NSTouchBarItem.Identifier.barMaster("ghostty.tabs")
    private static let closeTab = NSTouchBarItem.Identifier.barMaster("ghostty.close-tab")
    private static let newTab = NSTouchBarItem.Identifier.barMaster("ghostty.new-tab")
    private static let splitRight = NSTouchBarItem.Identifier.barMaster("ghostty.split-right")
    private static let splitDown = NSTouchBarItem.Identifier.barMaster("ghostty.split-down")
    private static let nextSplit = NSTouchBarItem.Identifier.barMaster("ghostty.next-split")
    private static let zoomSplit = NSTouchBarItem.Identifier.barMaster("ghostty.zoom-split")
    private static let clear = NSTouchBarItem.Identifier.barMaster("ghostty.clear")
    private static let git = NSTouchBarItem.Identifier.barMaster("ghostty.git")
    private static let claude = NSTouchBarItem.Identifier.barMaster("ghostty.claude")

    private let tabStrip = TabScrubberItem(identifier: GhosttyBar.tabs, width: 200)
    private let gitStatus = GitStatus()
    private let claudeSession = ClaudeSession()
    private lazy var claudeButton = statusButton(symbol: "sparkle", label: "Claude context tokens",
                                                 action: #selector(reloadClaude))
    private lazy var gitButton = statusButton(symbol: "arrow.triangle.branch", label: "Git branch",
                                              action: #selector(reloadGit))
    private var claudeTokens: Int?
    /// The focused terminal is running Claude Code (judged by its title).
    private var isClaudeTerminal = false
    private let tabThrottle = Throttle(delay: 0.15)
    private let titleThrottle = Throttle(delay: 0.5)

    override init() {
        super.init()
        tabStrip.onSelect = { [weak self] index in
            self?.run("select tab (tab \(index + 1) of front window)", cache: false)
        }
        gitStatus.onChange = { [weak self] info in
            guard let self else { return }
            self.gitButton.isHidden = info == nil
            if let info { self.gitButton.title = "\(info.branch) · \(info.commits)" }
        }
        claudeSession.onChange = { [weak self] tokens in
            guard let self else { return }
            self.claudeTokens = tokens
            if let tokens { self.claudeButton.title = Self.compact(tokens) }
            self.updateClaudeVisibility()
        }
    }

    override var appItems: [NSTouchBarItem.Identifier] {
        [Self.previousTab, Self.tabs, Self.nextTab, .fixedSpaceSmall,
         Self.newTab, Self.closeTab, .fixedSpaceSmall,
         Self.splitRight, Self.splitDown, Self.nextSplit, Self.zoomSplit, Self.clear,
         .flexibleSpace, Self.git, Self.claude]
    }

    override func makeAppItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.tabs: return tabStrip
        case Self.git:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = gitButton
            item.customizationLabel = "Git branch and commits"
            return item
        case Self.claude:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = claudeButton
            item.customizationLabel = "Claude context tokens"
            return item
        case Self.previousTab: return button(identifier, symbol: "chevron.left", label: "Previous tab", action: #selector(previousTab))
        case Self.nextTab: return button(identifier, symbol: "chevron.right", label: "Next tab", action: #selector(nextTab))
        case Self.closeTab: return button(identifier, symbol: "xmark", label: "Close tab", action: #selector(closeTab))
        case Self.newTab: return button(identifier, symbol: "plus", label: "New tab", action: #selector(newTab))
        case Self.splitRight: return button(identifier, symbol: "rectangle.split.2x1", label: "Split right", action: #selector(splitRight))
        case Self.splitDown: return button(identifier, symbol: "rectangle.split.1x2", label: "Split down", action: #selector(splitDown))
        case Self.nextSplit: return button(identifier, symbol: "arrow.right.square", label: "Next split", action: #selector(nextSplit))
        case Self.zoomSplit: return button(identifier, symbol: "arrow.up.left.and.arrow.down.right", label: "Zoom split", action: #selector(zoomSplit))
        case Self.clear: return button(identifier, symbol: "eraser", label: "Clear screen", action: #selector(clear))
        default: return nil
        }
    }

    /// Reads the selected tab, the focused terminal's directory and every tab name in one round trip.
    override func refresh() {
        AppleScript.run("""
            tell application "Ghostty"
                if (count of windows) is 0 then return {}
                set selectedTab to selected tab of front window
                return {index of selectedTab, working directory of focused terminal of selectedTab} & (name of every tab of front window)
            end tell
            """) { [weak self] result in
            guard let self, let result, result.numberOfItems >= 2 else { return }
            let titles = stride(from: 3, through: result.numberOfItems, by: 1).map { result.atIndex($0)?.stringValue ?? "" }
            let selected = Int(result.atIndex(1)?.int32Value ?? 0) - 1
            self.tabStrip.update(titles: titles, selected: selected)
            self.track(directory: result.atIndex(2)?.stringValue,
                       title: titles.indices.contains(selected) ? titles[selected] : nil)
        }
    }

    /// Each Ghostty tab is its own window, so switching tabs moves window focus.
    /// Titles change constantly (shell prompts, spinners), so a title change only
    /// re-reads the directory over Accessibility, which is cheap; no AppleScript.
    override func appEvent(_ name: String) {
        switch name {
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXWindowCreatedNotification:
            tabThrottle.schedule { [weak self] in self?.refresh() }
        case kAXTitleChangedNotification:
            titleThrottle.schedule { [weak self] in
                guard let self, let app = self.appElement,
                      let window = AX.element(app, kAXFocusedWindowAttribute) else { return }
                self.track(directory: AX.documentPath(ofFocusedWindowIn: app),
                           title: AX.string(window, kAXTitleAttribute))
            }
        default:
            break
        }
    }

    private func track(directory: String?, title: String?) {
        if let directory {
            gitStatus.track(directory: directory)
            claudeSession.track(directory: directory)
        }
        isClaudeTerminal = title.map(Self.isClaudeTitle) ?? false
        updateClaudeVisibility()
    }

    private func updateClaudeVisibility() {
        claudeButton.isHidden = !(isClaudeTerminal && claudeTokens != nil)
    }

    /// Claude Code titles its terminal "✳ <topic>" when idle and animates a
    /// spinner glyph in front while working; other programs don't.
    private static func isClaudeTitle(_ title: String) -> Bool {
        guard let first = title.unicodeScalars.first else { return false }
        return "✳✢✶✻✽·◐◓◑◒".unicodeScalars.contains(first) || (0x2800...0x28FF).contains(first.value)
    }

    /// 178_342 → "178k", 1_204_000 → "1.2M".
    private static func compact(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return "\(tokens / 1_000)k" }
        return "\(tokens)"
    }

    /// A status readout: icon plus text, hidden until there is something to show.
    private func statusButton(symbol: String, label: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(title: "", image: image, target: self, action: action)
        button.imagePosition = .imageLeading
        button.lineBreakMode = .byTruncatingMiddle
        button.widthAnchor.constraint(lessThanOrEqualToConstant: 190).isActive = true
        button.isHidden = true
        return button
    }

    @objc private func reloadGit() { gitStatus.reload() }
    @objc private func reloadClaude() { claudeSession.reload() }
    @objc private func previousTab() { perform("previous_tab") }
    @objc private func nextTab() { perform("next_tab") }
    @objc private func closeTab() { perform("close_tab") }
    @objc private func newTab() { perform("new_tab") }
    @objc private func splitRight() { perform("new_split:right", refreshing: false) }
    @objc private func splitDown() { perform("new_split:down", refreshing: false) }
    @objc private func nextSplit() { perform("goto_split:next", refreshing: false) }
    @objc private func zoomSplit() { perform("toggle_split_zoom", refreshing: false) }
    @objc private func clear() { perform("clear_screen", refreshing: false) }

    /// Runs one of Ghostty's keybind actions on the focused terminal.
    private func perform(_ action: String, refreshing: Bool = true) {
        run("perform action \"\(action)\" on focused terminal of selected tab of front window")
        if refreshing { refresh() }
    }

    private func run(_ command: String, cache: Bool = true) {
        AppleScript.run("""
            tell application "Ghostty"
                if (count of windows) > 0 then \(command)
            end tell
            """, cache: cache)
    }
}
