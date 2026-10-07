import Foundation

/// Calls back when a file or directory is written, renamed or deleted, using
/// a kqueue source: the kernel wakes us, nothing polls.
final class FileWatcher {
    private(set) var path: String?
    private var source: DispatchSourceFileSystemObject?

    /// Watches `path` (nil stops). After a rename or delete the watch ends,
    /// since the path may now be a different file; `onChange` still fires so
    /// the caller can look again.
    func watch(_ path: String?, onChange: @escaping () -> Void) {
        guard path != self.path else { return }
        source?.cancel()
        source = nil
        self.path = path
        guard let path else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            self.path = nil
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, unowned source] in
            if !source.data.isDisjoint(with: [.delete, .rename]) { self?.watch(nil, onChange: onChange) }
            onChange()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}
