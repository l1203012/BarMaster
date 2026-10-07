import Foundation

/// User-defined Chrome buttons per website, from
/// ~/Library/Application Support/BarMaster/Chrome.json. Reloaded when the
/// file is saved (the folder is kqueue-watched, which also catches editors
/// that save by replacing the file).
final class ChromeButtons {
    struct Button: Decodable, Hashable {
        var title: String?
        /// An SF Symbol name, e.g. "play.fill".
        var symbol: String?
        /// Exactly one action:
        var js: String?
        var url: String?
        var keys: String?
        var shell: String?
    }

    private struct File: Decodable {
        var domains: [String: [Button]]
    }

    enum State: Equatable {
        case loaded([String: [Button]])
        case invalid(String)
    }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/BarMaster/Chrome.json")

    private(set) var state: State = .loaded([:])
    var onChange: (() -> Void)?
    private let folder = FileWatcher()

    init() {
        load()
        folder.watch(Self.url.deletingLastPathComponent().path) { [weak self] in self?.reload() }
    }

    /// Buttons for `host`: the entry for the host itself or its nearest parent
    /// domain ("github.com" also covers "gist.github.com"), plus any "*" buttons.
    func buttons(for host: String?) -> [Button] {
        guard case .loaded(let domains) = state else { return [] }
        var matched: [Button] = []
        if var labels = host?.lowercased().split(separator: ".").map(String.init) {
            if labels.first == "www" { labels.removeFirst() }
            while labels.count >= 2 {
                if let buttons = domains[labels.joined(separator: ".")] {
                    matched = buttons
                    break
                }
                labels.removeFirst()
            }
        }
        return matched + (domains["*"] ?? [])
    }

    /// Creates the file with examples if needed and returns its URL, for the menu's "Edit…".
    func ensureFile() -> URL {
        if !FileManager.default.fileExists(atPath: Self.url.path) {
            try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? Self.example.write(to: Self.url, atomically: true, encoding: .utf8)
            folder.watch(Self.url.deletingLastPathComponent().path) { [weak self] in self?.reload() }
            reload()
        }
        return Self.url
    }

    private func reload() {
        let old = state
        load()
        if state != old { onChange?() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.url) else {
            state = .loaded([:])
            return
        }
        do {
            let file = try JSONDecoder().decode(File.self, from: data)
            let domains = Dictionary(file.domains.map { ($0.key.lowercased(), $0.value) }) { first, _ in first }
            state = .loaded(domains)
        } catch {
            state = .invalid(String(describing: error))
            NSLog("BarMaster: Chrome.json is invalid: %@", String(describing: error))
        }
    }

    private static let example = """
        {
          "domains": {
            "github.com": [
              { "title": "PRs", "symbol": "arrow.triangle.pull", "url": "https://github.com/pulls" },
              { "title": "Copy URL", "shell": "printf %s \\"$BARMASTER_URL\\" | pbcopy" }
            ],
            "youtube.com": [
              { "symbol": "playpause.fill", "keys": "k" },
              { "title": "2×", "js": "document.querySelector('video').playbackRate = 2" }
            ],
            "*": []
          }
        }

        """
}
