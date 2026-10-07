import AppKit
import Carbon.HIToolbox

/// Chrome through its AppleScript dictionary: exact, and no focus tricks.
final class ChromeBar: AppBar {
    private static let previousTab = NSTouchBarItem.Identifier.barMaster("chrome.previous-tab")
    private static let nextTab = NSTouchBarItem.Identifier.barMaster("chrome.next-tab")
    private static let tabs = NSTouchBarItem.Identifier.barMaster("chrome.tabs")
    private static let closeTab = NSTouchBarItem.Identifier.barMaster("chrome.close-tab")
    private static let newTab = NSTouchBarItem.Identifier.barMaster("chrome.new-tab")
    private static let reopenTab = NSTouchBarItem.Identifier.barMaster("chrome.reopen-tab")
    private static let back = NSTouchBarItem.Identifier.barMaster("chrome.back")
    private static let forward = NSTouchBarItem.Identifier.barMaster("chrome.forward")
    private static let reload = NSTouchBarItem.Identifier.barMaster("chrome.reload")

    private let tabStrip = TabScrubberItem(identifier: ChromeBar.tabs)
    private let throttle = Throttle(delay: 0.25)

    override init() {
        super.init()
        tabStrip.onSelect = { [weak self] index in
            self?.run("set active tab index of front window to \(index + 1)", cache: false)
        }
    }

    override var appItems: [NSTouchBarItem.Identifier] {
        [Self.back, Self.forward, Self.reload, .fixedSpaceSmall,
         Self.previousTab, Self.tabs, Self.nextTab, .fixedSpaceSmall,
         Self.newTab, Self.closeTab, Self.reopenTab]
    }

    override func makeAppItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.tabs: return tabStrip
        case Self.previousTab: return button(identifier, symbol: "chevron.left", label: "Previous tab", action: #selector(previousTab))
        case Self.nextTab: return button(identifier, symbol: "chevron.right", label: "Next tab", action: #selector(nextTab))
        case Self.closeTab: return button(identifier, symbol: "xmark", label: "Close tab", action: #selector(closeTab))
        case Self.newTab: return button(identifier, symbol: "plus", label: "New tab", action: #selector(newTab))
        case Self.reopenTab: return button(identifier, symbol: "arrow.uturn.backward", label: "Reopen closed tab", action: #selector(reopenTab))
        case Self.back: return button(identifier, symbol: "arrow.left", label: "Back", action: #selector(back))
        case Self.forward: return button(identifier, symbol: "arrow.right", label: "Forward", action: #selector(forward))
        case Self.reload: return button(identifier, symbol: "arrow.clockwise", label: "Reload", action: #selector(reload))
        default: return nil
        }
    }

    override func refresh() {
        AppleScript.run("""
            tell application "Google Chrome"
                if (count of windows) is 0 then return {}
                return {active tab index of front window} & (title of every tab of front window)
            end tell
            """) { [weak self] result in
            guard let (selected, titles) = AppleScript.tabList(result) else { return }
            self?.tabStrip.update(titles: titles, selected: selected)
        }
    }

    /// Chrome's window title follows the active tab, so a title change means
    /// the tab changed (or its page did); either way the strip is re-read.
    override func appEvent(_ name: String) {
        guard name == kAXTitleChangedNotification || name == kAXFocusedWindowChangedNotification else { return }
        throttle.schedule { [weak self] in self?.refresh() }
    }

    @objc private func previousTab() {
        run("tell front window to set active tab index to ((active tab index + (count of tabs) - 2) mod (count of tabs)) + 1")
    }

    @objc private func nextTab() {
        run("tell front window to set active tab index to ((active tab index) mod (count of tabs)) + 1")
    }

    @objc private func closeTab() { run("close active tab of front window") }
    @objc private func back() { run("go back active tab of front window", refreshing: false) }
    @objc private func forward() { run("go forward active tab of front window", refreshing: false) }
    @objc private func reload() { run("reload active tab of front window", refreshing: false) }

    // ⌘T also focuses the address bar, which `make new tab` doesn't; reopening has no AppleScript.
    @objc private func newTab() { keystroke(kVK_ANSI_T, flags: .maskCommand) }
    @objc private func reopenTab() { keystroke(kVK_ANSI_T, flags: [.maskCommand, .maskShift]) }

    /// Runs `command` inside `tell application "Google Chrome"` (when it has a window),
    /// then re-reads the tab titles.
    private func run(_ command: String, cache: Bool = true, refreshing: Bool = true) {
        AppleScript.run("""
            tell application "Google Chrome"
                if (count of windows) > 0 then \(command)
            end tell
            """, cache: cache)
        if refreshing { refresh() }
    }

    private func keystroke(_ key: Int, flags: CGEventFlags) {
        KeyPress.post(key, flags: flags)
        // The key press is handled asynchronously by Chrome; read the tabs once it has.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
    }
}
