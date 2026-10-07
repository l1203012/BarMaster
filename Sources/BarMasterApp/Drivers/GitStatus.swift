import Foundation

/// Branch and commit count for one directory's repository. Updates when the
/// directory changes or when the repo's reflog is written (commit, checkout,
/// reset…), watched with a kqueue file source rather than polling.
final class GitStatus {
    struct Info: Equatable {
        let branch: String
        let commits: Int
    }

    var onChange: ((Info?) -> Void)?
    private var directory: String?
    private var watchedLog: String?
    private var watcher: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "io.github.l1203012.barmaster.git", qos: .utility)
    private let throttle = Throttle(delay: 0.3)

    func track(directory: String?) {
        guard directory != self.directory else { return }
        self.directory = directory
        reload()
    }

    func reload() {
        guard let directory else {
            watch(nil)
            onChange?(nil)
            return
        }
        queue.async { [weak self] in
            var info: Info?
            var log: String?
            if let lines = Self.git(["rev-parse", "--absolute-git-dir", "--abbrev-ref", "HEAD"], in: directory),
               lines.count == 2,
               let count = Self.git(["rev-list", "--count", "HEAD"], in: directory)?.first.flatMap(Int.init) {
                info = Info(branch: lines[1], commits: count)
                log = lines[0] + "/logs/HEAD"
            }
            DispatchQueue.main.async {
                guard let self, directory == self.directory else { return }
                self.watch(log)
                self.onChange?(info)
            }
        }
    }

    private func watch(_ log: String?) {
        guard log != watchedLog else { return }
        watcher?.cancel()
        watcher = nil
        watchedLog = log
        guard let log else { return }
        let fd = open(log, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // A replaced file needs a fresh descriptor.
            if !source.data.isDisjoint(with: [.delete, .rename]) { self.watch(nil) }
            self.throttle.schedule { self.reload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private static func git(_ arguments: [String], in directory: String) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
