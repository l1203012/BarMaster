import AppKit
import Carbon.HIToolbox

/// Slack without a Slack app or token: everything comes from the Slack client
/// itself. Slack already shows a macOS notification for each mention and DM,
/// so BarMaster watches Notification Center (over Accessibility, event-driven)
/// for Slack's banners, and reads Slack's Dock badge to see when you've caught up.
@MainActor
final class Slack {
    struct Mention {
        /// Who wrote, or the channel, as the banner's title shows it.
        let title: String
        let subtitle: String
        let body: String
        /// The on-screen banner while it lasts; pressing it opens the exact message.
        let banner: AXUIElement

        var summary: String {
            body.isEmpty ? title : "\(title): \(body)"
        }

        /// What to type into Slack's ⌘K switcher to reach the conversation:
        /// the "#channel" if the banner names one, otherwise the person.
        var conversation: String {
            [subtitle, title].first { $0.hasPrefix("#") } ?? title
        }
    }

    /// Unopened mentions, newest last.
    private(set) var mentions: [Mention] = []
    /// Conversations from recent mentions, newest first (kept across launches).
    private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "slackRecent") ?? []
    var onChange: (() -> Void)?

    private var notificationCenter: AppEvents?
    private var notificationCenterPID: pid_t = 0
    private var seen: [String: Date] = [:]
    private let throttle = Throttle(delay: 0.3)

    /// Starts (or restarts, if Notification Center relaunched) watching for banners.
    func start() {
        guard let center = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.notificationcenterui").first,
            center.processIdentifier != notificationCenterPID || notificationCenter == nil else { return }
        notificationCenterPID = center.processIdentifier
        notificationCenter = AppEvents(
            pid: center.processIdentifier,
            notifications: [kAXWindowCreatedNotification, kAXCreatedNotification]
        ) { [weak self] _ in
            self?.throttle.schedule { self?.scanBanners() }
        }
    }

    /// Opens the newest mention: the exact message while its banner is still
    /// up, otherwise its conversation through Slack's ⌘K switcher.
    func openLatestMention() {
        guard let mention = mentions.popLast() else { return }
        onChange?()
        if AXUIElementPerformAction(mention.banner, kAXPressAction as CFString) == .success { return }
        open(conversation: mention.conversation)
    }

    /// Jumps to a channel ("#general") or person by typing it into ⌘K.
    func open(conversation: String) {
        let delay: TimeInterval
        if let slack = NSRunningApplication.runningApplications(withBundleIdentifier: SupportedApp.slack.rawValue).first,
           !slack.isActive {
            slack.activate()
            delay = 0.4
        } else {
            delay = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            KeyPress.post(kVK_ANSI_K, flags: .maskCommand)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                KeyPress.type(conversation)
                // Give Slack's switcher a moment to search before choosing the top result.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    KeyPress.post(kVK_Return)
                }
            }
        }
    }

    /// Clears mentions once Slack's Dock badge is gone (you've read them in Slack).
    /// Called on app switches, so it costs nothing while you're idle.
    func checkBadge() {
        guard !mentions.isEmpty, Self.dockBadge() == nil else { return }
        mentions.removeAll()
        onChange?()
    }

    private func scanBanners() {
        guard let center = notificationCenter?.app else { return }
        var found: [Mention] = []
        for window in AX.elements(center, kAXWindowsAttribute) {
            collectBanners(in: window, into: &found)
        }
        // A banner is seen by several scans while it's on screen; take it once.
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 600 }
        let fresh = found.filter { mention in
            let key = mention.title + "\u{1}" + mention.subtitle + "\u{1}" + mention.body
            guard seen[key] == nil else { return false }
            seen[key] = now
            return true
        }
        guard !fresh.isEmpty else { return }
        mentions += fresh
        if mentions.count > 20 { mentions.removeFirst(mentions.count - 20) }
        for mention in fresh {
            recent.removeAll { $0 == mention.conversation }
            recent.insert(mention.conversation, at: 0)
        }
        recent = Array(recent.prefix(12))
        UserDefaults.standard.set(recent, forKey: "slackRecent")
        onChange?()
    }

    private func collectBanners(in element: AXUIElement, into found: inout [Mention]) {
        if AX.string(element, kAXSubroleAttribute) == "AXNotificationCenterBanner" {
            // Which app posted it; Slack's banners carry its bundle identifier.
            guard AX.string(element, "AXStackingIdentifier") == SupportedApp.slack.rawValue else { return }
            let texts = AX.elements(element, kAXChildrenAttribute)
                .filter { AX.string($0, kAXRoleAttribute) == kAXStaticTextRole }
                .compactMap { AX.string($0, kAXValueAttribute) }
            guard let title = texts.first else { return }
            // Two texts are title + body; three are title + subtitle + body.
            let subtitle = texts.count > 2 ? texts[1] : ""
            let body = texts.count > 1 ? texts[texts.count - 1] : ""
            found.append(Mention(title: title, subtitle: subtitle, body: body, banner: element))
            return
        }
        for child in AX.elements(element, kAXChildrenAttribute) {
            collectBanners(in: child, into: &found)
        }
    }

    /// Slack's Dock badge ("3", "•"), or nil when it shows none.
    private static func dockBadge() -> String? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        for list in AX.elements(app, kAXChildrenAttribute) {
            for item in AX.elements(list, kAXChildrenAttribute) where AX.string(item, kAXTitleAttribute) == "Slack" {
                let badge = AX.string(item, "AXStatusLabel")
                return badge?.isEmpty == false ? badge : nil
            }
        }
        return nil
    }
}
