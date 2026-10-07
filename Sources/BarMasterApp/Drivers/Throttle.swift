import Foundation

/// Coalesces bursts of events into one call `delay` seconds after the first.
/// The work reads state when it runs, so it always sees the latest.
final class Throttle {
    private let delay: TimeInterval
    private var pending = false

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func schedule(_ work: @escaping () -> Void) {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pending = false
            work()
        }
    }
}
