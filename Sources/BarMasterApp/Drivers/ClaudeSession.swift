import Foundation

/// How full the context of the newest Claude Code session for a directory is.
/// Claude Code appends every reply, with its token usage, to a transcript at
/// ~/.claude/projects/<directory with non-alphanumerics as "-">/<session>.jsonl.
/// The transcript and its folder are watched with kqueue, so the count follows
/// the session live without polling.
final class ClaudeSession {
    /// Context tokens of the latest reply, or nil when there is no recent session.
    var onChange: ((Int?) -> Void)?
    private var directory: String?
    private var projectFolder: String?
    private let transcript = FileWatcher()
    private let folder = FileWatcher()
    private let throttle = Throttle(delay: 1)
    private let queue = DispatchQueue(label: "io.github.l1203012.barmaster.claude", qos: .utility)
    /// Sessions untouched for longer than this are treated as finished.
    private static let maxAge: TimeInterval = 12 * 60 * 60
    private static let projects = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects").path

    func track(directory: String?) {
        guard directory != self.directory else { return }
        self.directory = directory
        projectFolder = directory.flatMap(Self.projectFolder(for:))
        folder.watch(projectFolder) { [weak self] in
            // A new session file appeared (or one was removed).
            self?.throttle.schedule { self?.reload() }
        }
        reload()
    }

    func reload() {
        guard let projectFolder else {
            transcript.watch(nil) {}
            onChange?(nil)
            return
        }
        queue.async { [weak self] in
            let file = Self.newestTranscript(in: projectFolder)
            let tokens = file.flatMap(Self.contextTokens(in:))
            DispatchQueue.main.async {
                guard let self, projectFolder == self.projectFolder else { return }
                self.transcript.watch(file) { [weak self] in
                    self?.throttle.schedule { self?.reload() }
                }
                self.onChange?(tokens)
            }
        }
    }

    /// The project folder for `directory`, or for the nearest parent that has one
    /// (a session started at the repo root while the shell is in a subfolder).
    private static func projectFolder(for directory: String) -> String? {
        var url = URL(fileURLWithPath: directory)
        while url.path != "/" {
            let encoded = String(url.path.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            let candidate = projects + "/" + encoded
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
            url.deleteLastPathComponent()
        }
        return nil
    }

    private static func newestTranscript(in folder: String) -> String? {
        let url = URL(fileURLWithPath: folder)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { file in
                (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    .map { (file, $0) }
            }
            .max { $0.1 < $1.1 }
        guard let newest, -newest.1.timeIntervalSinceNow < maxAge else { return nil }
        return newest.0.path
    }

    /// Context size after the last main-thread reply: everything sent plus what came back.
    /// Only the file's tail is read; transcripts grow to many megabytes.
    private static func contextTokens(in file: String) -> Int? {
        guard let handle = FileHandle(forReadingAtPath: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 512_000 ? size - 512_000 : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "assistant",
                  object["isSidechain"] as? Bool != true,
                  let usage = (object["message"] as? [String: Any])?["usage"] as? [String: Any]
            else { continue }
            let total = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
                .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
            if total > 0 { return total }
        }
        return nil
    }
}
