import Foundation

/// Phone taps and Watch intents share one order through local persistence.
/// A failed edit cannot stop later work; each caller still receives its error.
@MainActor
final class SupplementMutationQueue {
    private var tail: Task<Void, Never>?
    private var revision: UInt64 = 0

    func enqueue(
        requireCurrent: @escaping @MainActor @Sendable () throws -> Void = {},
        _ operation: @escaping @MainActor @Sendable () async throws -> Void
    ) -> Task<Void, Error> {
        let previous = tail
        revision &+= 1
        let currentRevision = revision
        let task = Task { @MainActor in
            await previous?.value
            try requireCurrent()
            try await operation()
            try requireCurrent()
        }
        tail = Task { @MainActor [weak self] in
            _ = try? await task.value
            if self?.revision == currentRevision { self?.tail = nil }
        }
        return task
    }
}
