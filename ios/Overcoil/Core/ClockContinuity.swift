import Foundation

// A continuity token is deliberately NOT a boot identifier. Comparisons stop at
// backgrounding and process exit; clock corrections outside that window may be missed.
final class ClockContinuity: @unchecked Sendable {
    static let shared = ClockContinuity()
    private let lock = NSLock()
    private var id = UUID()
    private var previous: ClockAnchor?
    func reset() { lock.lock(); defer { lock.unlock() }; id = UUID(); previous = nil }
    func isCurrent(_ token: UUID) -> Bool { lock.lock(); defer { lock.unlock() }; return token == id }
    func inspect(_ anchor: ClockAnchor) -> (UUID, Bool) {
        lock.lock(); defer { lock.unlock() }
        let changed = previous.map { abs($0.residual(to: anchor)) > 0.5 } ?? false
        previous = anchor
        return (id, changed)
    }
}
