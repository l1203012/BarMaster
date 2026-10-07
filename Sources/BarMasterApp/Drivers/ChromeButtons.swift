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
        /// Exactly one action. In `url`, {url} and {host} are the current page's,
        /// and {1}, {2}… its path segments (on github.com/owner/repo: owner, repo).
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

    /// Buttons for a page: the most specific matching entry, plus any "*" buttons.
    /// A key is a domain, optionally followed by a path pattern where "*" is
    /// any one segment: "github.com/*/*" (a repo) beats "github.com". A domain
    /// also covers its subdomains, and "www." is ignored.
    func buttons(for url: URL?) -> [Button] {
        guard case .loaded(let domains) = state else { return [] }
        var host = url?.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = Self.pathSegments(of: url)
        var best: (score: Int, buttons: [Button])?
        for (key, buttons) in domains where key != "*" {
            let parts = key.split(separator: "/").map(String.init)
            guard let domain = parts.first, host == domain || host.hasSuffix("." + domain) else { continue }
            let pattern = parts.dropFirst()
            guard pattern.count <= path.count,
                  zip(pattern, path).allSatisfy({ $0 == "*" || $0 == $1.lowercased() }) else { continue }
            let score = pattern.count * 1_000 + domain.count
            if score > best?.score ?? -1 { best = (score, buttons) }
        }
        return (best?.buttons ?? []) + (domains["*"] ?? [])
    }

    static func pathSegments(of url: URL?) -> [String] {
        url?.pathComponents.filter { $0 != "/" } ?? []
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
