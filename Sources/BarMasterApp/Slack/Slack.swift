import AppKit

/// BarMaster's connection to Slack: your channels for the switcher, and your
/// mentions as they happen. New messages arrive over a Socket Mode WebSocket
/// that Slack pushes to, so nothing polls. The tokens live in the Keychain;
/// without them Slack works through keyboard shortcuts only.
@MainActor
final class Slack {
    struct Mention {
        let channel: String
        let ts: String
        let sender: String
        let text: String
    }

    struct Channel: Equatable {
        let id: String
        let name: String
    }

    enum Status: Equatable {
        case notConfigured, connecting, connected
        case failed(String)
    }

    static let userTokenAccount = "slack-user-token"
    static let appTokenAccount = "slack-app-token"

    private(set) var status: Status = .notConfigured
    /// Unopened mentions, newest last.
    private(set) var mentions: [Mention] = []
    /// Where you talked most recently first, then every other channel you're in.
    private(set) var channels: [Channel] = []
    /// Called after any of the above change.
    var onChange: (() -> Void)?

    private var api: SlackAPI?
    private var appToken: String?
    private var me = ""
    private var team = ""
    private var socket: URLSessionWebSocketTask?
    private var retryDelay: TimeInterval = 5
    private var names: [String: String] = [:]
    private var channelsLoadedAt: Date?

    var isConfigured: Bool { api != nil }

    /// Connects with the tokens in the Keychain, if there are any.
    func connect() {
        disconnect()
        guard let user = Keychain.get(Self.userTokenAccount), let app = Keychain.get(Self.appTokenAccount) else {
            setStatus(.notConfigured)
            return
        }
        api = SlackAPI(userToken: user)
        appToken = app
        setStatus(.connecting)
        Task {
            do {
                let auth = try await call("auth.test")
                me = auth["user_id"] as? String ?? ""
                team = auth["team_id"] as? String ?? ""
                await openSocket()
                refreshChannels()
            } catch {
                setStatus(.failed(error.localizedDescription))
            }
        }
    }

    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        api = nil
        appToken = nil
        mentions = []
        channels = []
        channelsLoadedAt = nil
        setStatus(.notConfigured)
    }

    // MARK: Opening things in Slack

    /// Opens the newest mention's message in Slack and drops it from the list.
    func openLatestMention() {
        guard let mention = mentions.popLast() else { return }
        onChange?()
        Task {
            let permalink = try? await call("chat.getPermalink", ["channel": mention.channel, "message_ts": mention.ts])
            if let link = permalink?["permalink"] as? String, let url = URL(string: link) {
                openInSlack(url)
            } else {
                open(channel: mention.channel)
            }
        }
    }

    func open(channel id: String) {
        guard let url = URL(string: "slack://channel?team=\(team)&id=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Hands a message permalink to the Slack app itself rather than the browser.
    private func openInSlack(_ url: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SupportedApp.slack.rawValue) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Channels

    /// Reloads the switcher's channels, at most every two minutes.
    func refreshChannels() {
        guard api != nil, !me.isEmpty, channelsLoadedAt.map({ -$0.timeIntervalSinceNow > 120 }) ?? true else { return }
        channelsLoadedAt = Date()
        Task {
            var ordered: [Channel] = []
            // Search your own recent messages: their channels are the ones you use.
            if let found = try? await call("search.messages", ["query": "from:<@\(me)>", "sort": "timestamp", "count": "100"]),
               let matches = (found["messages"] as? [String: Any])?["matches"] as? [[String: Any]] {
                for match in matches {
                    guard let channel = match["channel"] as? [String: Any], let id = channel["id"] as? String,
                          !ordered.contains(where: { $0.id == id }) else { continue }
                    ordered.append(Channel(id: id, name: await displayName(of: channel)))
                }
            }
            if let joined = try? await call("users.conversations", [
                "types": "public_channel,private_channel", "exclude_archived": "true", "limit": "200",
            ]), let list = joined["channels"] as? [[String: Any]] {
                let rest = list.compactMap { channel -> Channel? in
                    guard let id = channel["id"] as? String, let name = channel["name"] as? String,
                          !ordered.contains(where: { $0.id == id }) else { return nil }
                    return Channel(id: id, name: "#" + name)
                }
                ordered += rest.sorted { $0.name < $1.name }
            }
            if ordered != channels {
                channels = ordered
                onChange?()
            }
        }
    }

    private func displayName(of channel: [String: Any]) async -> String {
        let name = channel["name"] as? String ?? "?"
        if channel["is_im"] as? Bool == true { return await userName(name) }
        if channel["is_mpim"] as? Bool == true {
            // "mpdm-ann--bob--cat-1" → "ann, bob, cat"
            let people = String(name.dropFirst("mpdm-".count)).split(separator: "-").map(String.init).filter { $0.count > 1 }
            return people.joined(separator: ", ")
        }
        return "#" + name
    }

    private func userName(_ id: String) async -> String {
        if let cached = names[id] { return cached }
        guard let info = try? await call("users.info", ["user": id]),
              let user = info["user"] as? [String: Any] else { return id }
        let profile = user["profile"] as? [String: Any]
        let name = [profile?["display_name"], profile?["real_name"], user["name"]]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? id
        names[id] = name
        return name
    }

    // MARK: Socket Mode

    private func openSocket() async {
        guard let appToken else { return }
        do {
            let connection = try await call("apps.connections.open", token: appToken)
            guard let url = (connection["url"] as? String).flatMap(URL.init(string:)) else { return }
            let task = URLSession.shared.webSocketTask(with: url)
            socket = task
            task.resume()
            receive(on: task)
            retryDelay = 5
            setStatus(.connected)
        } catch {
            setStatus(.failed(error.localizedDescription))
            reconnect()
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, task === self.socket else { return }
                switch result {
                case .failure:
                    self.reconnect()
                case .success(.string(let text)):
                    self.handle(text, on: task)
                    self.receive(on: task)
                case .success:
                    self.receive(on: task)
                }
            }
        }
    }

    /// Reconnects with backoff (5 s doubling to 5 min) after a drop or Slack's routine "disconnect".
    private func reconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        guard api != nil else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 300)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.api != nil, self.socket == nil else { return }
            Task { await self.openSocket() }
        }
    }

    private func handle(_ text: String, on task: URLSessionWebSocketTask) {
        guard let envelope = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return }
        // Every envelope must be acknowledged or Slack redelivers it.
        if let id = envelope["envelope_id"] as? String {
            task.send(.string(#"{"envelope_id":"\#(id)"}"#)) { _ in }
        }
        switch envelope["type"] as? String {
        case "disconnect":
            retryDelay = 1
            reconnect()
        case "events_api":
            if let event = (envelope["payload"] as? [String: Any])?["event"] as? [String: Any] {
                handle(event: event)
            }
        default:
            break
        }
    }

    /// A message mentioning you, or any message in a DM, becomes a mention.
    /// Once you write in a channel yourself, its mentions count as seen.
    private func handle(event: [String: Any]) {
        guard event["type"] as? String == "message",
              let channel = event["channel"] as? String, let ts = event["ts"] as? String else { return }
        let subtype = event["subtype"] as? String
        guard subtype == nil || subtype == "thread_broadcast" || subtype == "file_share" else { return }
        let sender = event["user"] as? String ?? ""
        let text = event["text"] as? String ?? ""
        if sender == me {
            let before = mentions.count
            mentions.removeAll { $0.channel == channel }
            if mentions.count != before { onChange?() }
            return
        }
        guard text.contains("<@\(me)>") || event["channel_type"] as? String == "im" else { return }
        Task {
            let name = await userName(sender)
            mentions.append(Mention(channel: channel, ts: ts, sender: name, text: readable(text)))
            if mentions.count > 20 { mentions.removeFirst(mentions.count - 20) }
            onChange?()
        }
    }

    /// Slack markup to plain text: "<@ME>" → "@you", "<url|label>" → "label", "<url>" → "url".
    private func readable(_ text: String) -> String {
        text.replacingOccurrences(of: "<@\(me)>", with: "@you")
            .replacingOccurrences(of: #"<[^>|]*\|([^>]*)>"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"<([^>]*)>"#, with: "$1", options: .regularExpression)
    }

    private func call(_ method: String, _ parameters: [String: String] = [:], token: String? = nil) async throws -> [String: Any] {
        guard let api else { throw SlackAPI.Failure(method: method, message: "not connected") }
        return try await api.call(method, parameters, token: token)
    }

    private func setStatus(_ status: Status) {
        guard status != self.status else { return }
        self.status = status
        if case .failed(let message) = status { NSLog("BarMaster Slack: %@", message) }
        onChange?()
    }
}
