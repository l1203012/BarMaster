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

    private let tabStrip = TabScrubberItem(identifier: GhosttyBar.tabs)

    override init() {
        super.init()
        tabStrip.onSelect = { [weak self] index in
            self?.run("select tab (tab \(index + 1) of front window)", cache: false)
        }
    }

    override var appItems: [NSTouchBarItem.Identifier] {
        [Self.previousTab, Self.tabs, Self.nextTab, .fixedSpaceSmall,
         Self.newTab, Self.closeTab, .fixedSpaceSmall,
         Self.splitRight, Self.splitDown, Self.nextSplit, Self.zoomSplit, Self.clear]
    }

    override func makeAppItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.tabs: return tabStrip
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

    override func refresh() {
        AppleScript.run("""
            tell application "Ghostty"
                if (count of windows) is 0 then return {}
                return {index of selected tab of front window} & (name of every tab of front window)
            end tell
            """) { [weak self] result in
            guard let (selected, titles) = AppleScript.tabList(result) else { return }
            self?.tabStrip.update(titles: titles, selected: selected)
        }
    }

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
