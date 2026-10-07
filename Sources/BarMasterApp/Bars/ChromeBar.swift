import AppKit
import Carbon.HIToolbox

/// Chrome through its AppleScript dictionary: exact, and no focus tricks.
/// After the fixed controls come the buttons the user defined for the current
/// website in Chrome.json (see ChromeButtons).
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

    private static let configError = NSTouchBarItem.Identifier.barMaster("chrome.config-error")

    private let tabStrip = TabScrubberItem(identifier: ChromeBar.tabs, width: 200)
    private let throttle = Throttle(delay: 0.25)
    let siteButtons = ChromeButtons()
    private var activeURL: URL?
    private var activeTitle = ""
    /// The current site's buttons, keyed by Touch Bar identifier. The identifier
    /// includes the button's content, because NSTouchBar caches items by identifier.
    private var siteItems: [(id: NSTouchBarItem.Identifier, button: ChromeButtons.Button)] = []

    override init() {
        super.init()
        tabStrip.onSelect = { [weak self] index in
            self?.run("set active tab index of front window to \(index + 1)", cache: false)
        }
        siteButtons.onChange = { [weak self] in self?.updateSiteButtons() }
    }

    override var appItems: [NSTouchBarItem.Identifier] {
        var items: [NSTouchBarItem.Identifier] = [
            Self.back, Self.forward, Self.reload, .fixedSpaceSmall,
            Self.previousTab, Self.tabs, Self.nextTab, .fixedSpaceSmall,
            Self.newTab, Self.closeTab, Self.reopenTab,
        ]
        if case .invalid = siteButtons.state {
            items += [.fixedSpaceSmall, Self.configError]
        } else if !siteItems.isEmpty {
            items += [.fixedSpaceSmall] + siteItems.map(\.id)
        }
        return items
    }

    override func makeAppItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if let site = siteItems.first(where: { $0.id == identifier }) {
            return siteItem(identifier, site.button)
        }
        switch identifier {
        case Self.tabs: return tabStrip
        case Self.configError:
            return button(identifier, symbol: "exclamationmark.triangle", label: "Chrome.json has an error",
                          title: "Chrome.json", action: #selector(editButtons))
        case Self.previousTab: return button(identifier, symbol: "chevron.left", label: "Previous tab", action: #selector(previousTab))
        case Self.nextTab: return button(identifier, symbol: "chevron.right", label: "Next tab", action: #selector(nextTab))
        case Self.closeTab: return button(identifier, symbol: "xmark", label: "Close tab", action: #selector(closeTab))
        case Self.newTab: return button(identifier, symbol: "plus", label: "New tab", action: #selector(newTab))
        case Self.reopenTab:
            let item = button(identifier, symbol: "arrow.uturn.backward", label: "Reopen closed tab", action: #selector(reopenTab))
            item.visibilityPriority = .low  // first to go when site buttons need the room
            return item
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
                set w to front window
                return {active tab index of w, URL of active tab of w} & (title of every tab of w)
            end tell
            """) { [weak self] result in
            guard let self, let result, result.numberOfItems >= 2 else { return }
            let titles = stride(from: 3, through: result.numberOfItems, by: 1).map { result.atIndex($0)?.stringValue ?? "" }
            let selected = Int(result.atIndex(1)?.int32Value ?? 0) - 1
            self.tabStrip.update(titles: titles, selected: selected)
            self.activeURL = result.atIndex(2)?.stringValue.flatMap(URL.init(string:))
            self.activeTitle = titles.indices.contains(selected) ? titles[selected] : ""
            self.updateSiteButtons()
        }
    }

    /// Swaps in the buttons for the active tab's website when they differ.
    private func updateSiteButtons() {
        let buttons = siteButtons.buttons(for: activeURL)
        guard buttons != siteItems.map(\.button) || isShowingStaleError else { return }
        siteItems = buttons.enumerated().map { index, button in
            (.barMaster("chrome.site.\(index).\(button.hashValue)"), button)
        }
        reloadItems()
    }

    private var isShowingStaleError: Bool {
        if case .invalid = siteButtons.state { return !touchBar.defaultItemIdentifiers.contains(Self.configError) }
        return touchBar.defaultItemIdentifiers.contains(Self.configError)
    }

    private func siteItem(_ identifier: NSTouchBarItem.Identifier, _ site: ChromeButtons.Button) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let image = site.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: site.title) }
        let button: NSButton
        switch (site.title, image) {
        case let (title?, image?): button = NSButton(title: title, image: image, target: self, action: #selector(runSiteButton))
        case let (nil, image?): button = NSButton(image: image, target: self, action: #selector(runSiteButton))
        default: button = NSButton(title: site.title ?? "?", target: self, action: #selector(runSiteButton))
        }
        button.imagePosition = site.title == nil ? .imageOnly : .imageLeading
        button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        item.view = button
        item.customizationLabel = site.title ?? site.symbol ?? "Site button"
        return item
    }

    @objc private func runSiteButton(_ sender: NSButton) {
        guard let site = siteItems.first(where: { $0.id.rawValue == sender.identifier?.rawValue })?.button else { return }
        let page = activeURL?.absoluteString ?? ""
        if let js = site.js {
            // Needs Chrome → View → Developer → Allow JavaScript from Apple Events.
            run("execute active tab of front window javascript \(AppleScript.quoted(js))", cache: false, refreshing: false)
        } else if let url = site.url {
            let encoded = page.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            var target = url.replacingOccurrences(of: "{url}", with: encoded)
                .replacingOccurrences(of: "{host}", with: activeURL?.host ?? "")
            for (index, segment) in ChromeButtons.pathSegments(of: activeURL).enumerated() {
                target = target.replacingOccurrences(of: "{\(index + 1)}", with: segment)
            }
            run("set URL of active tab of front window to \(AppleScript.quoted(target))", cache: false, refreshing: false)
        } else if let keys = site.keys, let combo = KeyCombo(keys) {
            KeyPress.post(combo.key, flags: combo.flags)
        } else if let shell = site.shell {
            Self.runShell(shell, environment: [
                "BARMASTER_URL": page, "BARMASTER_HOST": activeURL?.host ?? "", "BARMASTER_TITLE": activeTitle,
            ])
        } else {
            NSLog("BarMaster: Chrome.json button %@ has no usable action", site.title ?? "")
        }
    }

    @objc private func editButtons() {
        NSWorkspace.shared.open(siteButtons.ensureFile())
    }

    /// Runs a user command through the login shell, so their PATH applies.
    private static func runShell(_ command: String, environment: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { NSLog("BarMaster: shell button failed: %@", error.localizedDescription) }
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
