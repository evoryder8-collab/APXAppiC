import Foundation

/// The live player records one prescribed set only after both sides. As on
/// the web, its per-side count is the lower completed count, never their sum.
struct GuidedSetExecution: Codable, Equatable, Sendable {
    enum Side: String, Codable, Sendable { case left, right }
    enum Completion: Equatable {
        case switchSide
        case record(work: Int, skipped: Bool)
    }

    private(set) var side: Side?
    private var firstSideWork: Int?

    init(perSide: Bool) {
        side = perSide ? .left : nil
    }

    mutating func beginRightSide() {
        guard side == .left, firstSideWork != nil else { return }
        side = .right
    }

    mutating func finish(work: Int, skipped: Bool) -> Completion {
        guard !skipped else { return .record(work: 0, skipped: true) }
        let completed = max(0, work)
        if side == .left {
            firstSideWork = completed
            return .switchSide
        }
        if side == .right {
            guard let firstSideWork else { return .record(work: 0, skipped: true) }
            return .record(work: min(firstSideWork, completed), skipped: false)
        }
        return .record(work: completed, skipped: false)
    }
}

/// Speech completion and its bounded fallback share a token. A callback from
/// an interrupted announcement must never start a different set's cadence.
struct GuidedCadenceGate: Sendable {
    private var pending: UUID?

    mutating func begin(voiceEnabled: Bool) -> UUID? {
        pending = voiceEnabled ? UUID() : nil
        return pending
    }

    mutating func finish(_ token: UUID) -> Bool {
        guard pending == token else { return false }
        pending = nil
        return true
    }

    mutating func cancel() { pending = nil }

    func allowsTick(paused: Bool, foreground: Bool) -> Bool {
        !paused && foreground && pending == nil
    }
}
