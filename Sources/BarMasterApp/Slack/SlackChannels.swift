import Foundation

/// Your favourite Slack channels and people for the switcher, from
/// ~/Library/Application Support/BarMaster/Slack.json:
/// { "channels": ["#general", "#dev", "Sam Example"] }
/// Reloaded when the file is saved.
final class SlackChannels {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/BarMaster/Slack.json")

    private(set) var favourites: [String] = []
    var onChange: (() -> Void)?
    private let folder = FileWatcher()

    init() {
        load()
        watch()
    }

    /// Creates the file with an example if needed and returns its URL, for the menu's "Edit…".
    func ensureFile() -> URL {
        if !FileManager.default.fileExists(atPath: Self.url.path) {
            try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? ##"{ "channels": ["#general"] }"##.appending("\n").write(to: Self.url, atomically: true, encoding: .utf8)
            watch()
            reload()
        }
        return Self.url
    }

    private func watch() {
        folder.watch(Self.url.deletingLastPathComponent().path) { [weak self] in self?.reload() }
    }

    private func reload() {
        let old = favourites
        load()
        if favourites != old { onChange?() }
    }

    private func load() {
        struct File: Decodable { var channels: [String] }
        guard let data = try? Data(contentsOf: Self.url) else {
            favourites = []
            return
        }
        do {
            favourites = try JSONDecoder().decode(File.self, from: data).channels
        } catch {
            NSLog("BarMaster: Slack.json is invalid: %@", String(describing: error))
        }
    }
}
