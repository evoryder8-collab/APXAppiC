import Foundation

enum WatchSupplementKeys {
    static let snapshot = "fitr.supplements.snapshot.v1"
    static let mutation = "fitr.supplements.mutation.v1"
    static let request = "fitr.supplements.request.v1"

    static func state(ownerID: UUID) -> String {
        "fitr.watch.supplements.state.\(ownerID.uuidString.lowercased()).v1"
    }

    static let activeOwner = "fitr.watch.supplements.active-owner.v1"

    static func journal(ownerID: UUID) -> String {
        "fitr.phone.supplements.journal.\(ownerID.uuidString.lowercased()).v1"
    }
}

struct WatchSupplementItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let dose: String
}

struct WatchSupplementSnapshot: Codable, Equatable, Sendable {
    let ownerID: UUID
    var day: String
    var revision: UInt64
    var items: [WatchSupplementItem]
    var checkedIDs: Set<UUID>
    var acknowledgedIDs: Set<UUID>
}

struct WatchSupplementMutation: Codable, Equatable, Sendable {
    var id = UUID()
    let ownerID: UUID
    let day: String
    let itemID: UUID
    let taken: Bool
    let baseRevision: UInt64
    let sequence: UInt64
}

struct WatchSupplementPreferences: Codable, Equatable, Sendable {
    var isVisible = true
    var hiddenIDs: Set<UUID> = []
}

/// One account's local checklist, including durable, explicit (never toggle) intents.
struct WatchSupplementState: Codable, Equatable, Sendable {
    var snapshot: WatchSupplementSnapshot?
    var preferences = WatchSupplementPreferences()
    var pending: [WatchSupplementMutation] = []
    var lastSequence: UInt64 = 0

    var visibleItems: [WatchSupplementItem] {
        guard preferences.isVisible else { return [] }
        return (snapshot?.items ?? []).filter { !preferences.hiddenIDs.contains($0.id) }
    }

    @discardableResult
    mutating func accept(_ incoming: WatchSupplementSnapshot, ownerID: UUID) -> Bool {
        guard incoming.ownerID == ownerID else { return false }
        if let snapshot {
            guard snapshot.ownerID == ownerID, incoming.revision > snapshot.revision else { return false }
        }
        snapshot = incoming
        pending.removeAll { incoming.acknowledgedIDs.contains($0.id) }
        return true
    }

    func isTaken(itemID: UUID, day: String) -> Bool {
        if let mutation = pending.last(where: { $0.itemID == itemID && $0.day == day }) {
            return mutation.taken
        }
        return snapshot?.day == day && snapshot?.checkedIDs.contains(itemID) == true
    }

    mutating func setTaken(
        itemID: UUID, taken: Bool, day: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> WatchSupplementMutation? {
        guard let snapshot, snapshot.items.contains(where: { $0.id == itemID }), now.isFinite else { return nil }
        lastSequence = max(lastSequence + 1, UInt64(min(max(0, now) * 1_000, Double(Int64.max))))
        let mutation = WatchSupplementMutation(ownerID: snapshot.ownerID, day: day, itemID: itemID,
            taken: taken, baseRevision: snapshot.revision, sequence: lastSequence)
        pending.removeAll { $0.itemID == itemID && $0.day == day }
        pending.append(mutation)
        return mutation
    }
}

/// Stored separately for each phone account. A newer phone edit beats an offline Watch intent.
struct WatchSupplementJournal: Codable, Sendable {
    var revision: UInt64 = 0
    var phoneEdits: [String: UInt64] = [:]
    var watchSequences: [String: UInt64] = [:]
    var acknowledgedIDs: [UUID] = []
    var knownChecks: [String: Bool] = [:]
    var localEdits: [String: UInt64] = [:]

    mutating func recordPhoneEdit(itemID: UUID, day: String, taken: Bool? = nil) {
        revision += 1
        let scope = key(itemID, day)
        phoneEdits[scope] = revision
        localEdits[scope] = revision
        if let taken { knownChecks[scope] = taken }
    }

    /// Realtime/dashboard changes also count as phone edits. Recording the
    /// accepted Watch value first avoids treating its own echo as a conflict.
    mutating func observePhoneValue(itemID: UUID, day: String, taken: Bool) {
        let scope = key(itemID, day)
        if let previous = knownChecks[scope], previous != taken {
            recordPhoneEdit(itemID: itemID, day: day, taken: taken)
        } else {
            knownChecks[scope] = taken
        }
    }

    mutating func recordWatchValue(_ mutation: WatchSupplementMutation) {
        revision += 1
        let scope = key(mutation.itemID, mutation.day)
        knownChecks[scope] = mutation.taken
        localEdits[scope] = revision
    }

    mutating func nextSnapshotRevision(now: TimeInterval = Date().timeIntervalSince1970) -> UInt64 {
        let clock = now.isFinite ? UInt64(min(max(0, now) * 1_000, Double(Int64.max))) : 0
        revision = max(revision + 1, clock)
        return revision
    }

    func permits(_ mutation: WatchSupplementMutation) -> Bool {
        let scope = key(mutation.itemID, mutation.day)
        return !acknowledgedIDs.contains(mutation.id)
            && mutation.sequence > (watchSequences[scope] ?? 0)
            && mutation.baseRevision >= (phoneEdits[scope] ?? 0)
    }

    mutating func acknowledge(_ mutation: WatchSupplementMutation) {
        let scope = key(mutation.itemID, mutation.day)
        watchSequences[scope] = max(watchSequences[scope] ?? 0, mutation.sequence)
        if !acknowledgedIDs.contains(mutation.id) { acknowledgedIDs.append(mutation.id) }
        acknowledgedIDs = Array(acknowledgedIDs.suffix(256))
    }

    static func scope(itemID: UUID, day: String) -> String { "\(day)/\(itemID.uuidString)" }

    private func key(_ id: UUID, _ day: String) -> String { Self.scope(itemID: id, day: day) }
}
