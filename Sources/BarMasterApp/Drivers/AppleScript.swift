import Foundation

/// Runs AppleScript off the main thread, one script at a time, so a slow app
/// never stalls the Touch Bar. Fixed scripts are compiled once and reused.
enum AppleScript {
    private static let queue = DispatchQueue(label: "io.github.l1203012.barmaster.applescript", qos: .userInitiated)
    /// Only touched on `queue`.
    private static var compiled: [String: NSAppleScript] = [:]

    /// Runs `source`; `completion` gets the result on the main thread, or nil on error.
    /// Pass `cache: false` for one-off sources (e.g. with an index baked in).
    static func run(_ source: String, cache: Bool = true, then completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            guard let script = compiled[source] ?? NSAppleScript(source: source) else { return }
            if cache { compiled[source] = script }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error { NSLog("BarMaster AppleScript error: %@", error) }
            if let completion {
                DispatchQueue.main.async { completion(error == nil ? result : nil) }
            }
        }
    }

    /// `text` as an AppleScript string literal.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
