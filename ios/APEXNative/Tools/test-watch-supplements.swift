import Foundation

@main
struct WatchSupplementChecks {
    @MainActor
    static func main() async throws {
        let owner = UUID(), other = UUID(), item = UUID()
        let day = "2026-11-02"
        let snapshot = WatchSupplementSnapshot(ownerID: owner, day: day, revision: 10,
            items: [.init(id: item, name: "Creatine", dose: "5 g")], checkedIDs: [], acknowledgedIDs: [])
        var state = WatchSupplementState()
        precondition(state.accept(snapshot, ownerID: owner))
        precondition(state.visibleItems.count == 1)
        let first = state.setTaken(itemID: item, taken: true, day: day, now: 100)!
        precondition(state.isTaken(itemID: item, day: day))
        precondition(!state.isTaken(itemID: item, day: "2026-11-03"))
        precondition(state.pending.count == 1)
        state = try JSONDecoder().decode(WatchSupplementState.self, from: JSONEncoder().encode(state))
        precondition(state.isTaken(itemID: item, day: day), "Offline tick survives relaunch")
        let second = state.setTaken(itemID: item, taken: false, day: day, now: 99)!
        precondition(second.sequence > first.sequence, "Clock changes cannot reverse intent order")
        precondition(state.pending.count == 1 && !state.isTaken(itemID: item, day: day))
        var acknowledged = snapshot
        acknowledged.revision = 11
        acknowledged.checkedIDs = [item]
        acknowledged.acknowledgedIDs = [first.id]
        precondition(state.accept(acknowledged, ownerID: owner))
        precondition(!state.isTaken(itemID: item, day: day), "Old acknowledgment preserves a newer untick")
        acknowledged.revision = 12
        acknowledged.checkedIDs = []
        acknowledged.acknowledgedIDs = [second.id]
        precondition(state.accept(acknowledged, ownerID: owner) && state.pending.isEmpty)
        precondition(!state.accept(snapshot, ownerID: owner), "Delayed snapshot must not replace current state")
        precondition(!state.accept(snapshot, ownerID: other), "Another account cannot receive these items")
        state.preferences.hiddenIDs = [item]
        precondition(state.visibleItems.isEmpty)
        state.preferences.hiddenIDs = []
        state.preferences.isVisible = false
        precondition(state.visibleItems.isEmpty)
        precondition(state.setTaken(itemID: UUID(), taken: true, day: day) == nil)

        var journal = WatchSupplementJournal()
        precondition(journal.permits(first))
        journal.acknowledge(first)
        precondition(!journal.permits(first), "Immediate and queued delivery are idempotent")
        precondition(journal.permits(second))
        journal.acknowledge(second)
        precondition(!journal.permits(first), "Older tick cannot undo a newer untick")
        journal.revision = 20
        journal.recordPhoneEdit(itemID: item, day: day)
        precondition(!journal.permits(.init(ownerID: owner, day: day, itemID: item,
            taken: true, baseRevision: 10, sequence: second.sequence + 1)), "Newer phone edit wins over delayed Watch transfer")
        precondition(journal.permits(.init(ownerID: owner, day: day, itemID: item,
            taken: true, baseRevision: journal.revision, sequence: second.sequence + 2)))
        let nextDay = WatchSupplementMutation(ownerID: owner, day: "2026-11-03", itemID: item,
            taken: true, baseRevision: 0, sequence: second.sequence + 3)
        precondition(journal.permits(nextDay), "Yesterday's edit cannot block a new day's log")
        var observed = WatchSupplementJournal()
        observed.observePhoneValue(itemID: item, day: day, taken: false)
        let initialRevision = observed.revision
        observed.observePhoneValue(itemID: item, day: day, taken: false)
        precondition(observed.revision == initialRevision, "An unchanged dashboard is not a phone edit")
        observed.observePhoneValue(itemID: item, day: day, taken: true)
        precondition(observed.revision > initialRevision, "A phone/realtime change revokes older Watch intents")
        precondition(!observed.permits(.init(ownerID: owner, day: day, itemID: item,
            taken: false, baseRevision: initialRevision, sequence: 1)))
        observed.recordWatchValue(second)
        let watchRevision = observed.revision
        observed.observePhoneValue(itemID: item, day: day, taken: false)
        precondition(observed.revision == watchRevision, "A Watch write echo is not a conflicting phone edit")
        let rebuiltRevision = observed.nextSnapshotRevision(now: 10_000)
        precondition(rebuiltRevision >= 10_000_000)
        precondition(observed.nextSnapshotRevision(now: 9_000) > rebuiltRevision,
            "A backwards phone clock cannot make a snapshot older")
        let decodedJournal = try JSONDecoder().decode(WatchSupplementJournal.self,
            from: JSONEncoder().encode(observed))
        precondition(decodedJournal.knownChecks == observed.knownChecks)
        precondition(WatchSupplementKeys.state(ownerID: owner) != WatchSupplementKeys.state(ownerID: other))
        precondition(WatchSupplementKeys.journal(ownerID: owner) != WatchSupplementKeys.journal(ownerID: other))

        var offline = WatchSupplementState()
        precondition(offline.accept(snapshot, ownerID: owner))
        _ = offline.setTaken(itemID: item, taken: true, day: day, now: 100)
        offline.preferences.hiddenIDs = [item]
        let defaults = UserDefaults(suiteName: "fitr.watch.supplements.test.\(UUID().uuidString)")!
        let ownerKey = WatchSupplementKeys.state(ownerID: owner)
        defer { defaults.removeObject(forKey: ownerKey) }
        defaults.set(try JSONEncoder().encode(offline), forKey: ownerKey)
        precondition(defaults.data(forKey: WatchSupplementKeys.state(ownerID: other)) == nil)
        let restored = try JSONDecoder().decode(WatchSupplementState.self, from: defaults.data(forKey: ownerKey)!)
        precondition(restored.preferences.hiddenIDs == [item] && restored.pending.count == 1)
        precondition(!restored.isTaken(itemID: item, day: "2026-11-03"), "New days do not inherit old ticks")
        precondition(offline.setTaken(itemID: item, taken: true, day: day, now: .infinity) == nil)

        enum QueueFailure: Error { case expected }
        let queue = SupplementMutationQueue()
        var order: [Int] = []
        let firstWrite = queue.enqueue {
            order.append(1)
            await Task.yield()
            order.append(2)
        }
        let failedWrite = queue.enqueue {
            order.append(3)
            throw QueueFailure.expected
        }
        let lastWrite = queue.enqueue { order.append(4) }
        try await firstWrite.value
        do {
            try await failedWrite.value
            preconditionFailure("The caller must receive persistence failures")
        } catch QueueFailure.expected {}
        try await lastWrite.value
        precondition(order == [1, 2, 3, 4], "Phone and Watch writes stay ordered across suspension and failure")

        var accountGeneration = 1
        var staleWriteRan = false
        let oldGeneration = accountGeneration
        let staleWrite = queue.enqueue(requireCurrent: {
            guard accountGeneration == oldGeneration else { throw CancellationError() }
        }) { staleWriteRan = true }
        accountGeneration = 2
        do {
            try await staleWrite.value
            preconditionFailure("A queued edit from a signed-out account must be rejected")
        } catch is CancellationError {}
        precondition(!staleWriteRan)
        let currentGeneration = accountGeneration
        let lateCallback = queue.enqueue(requireCurrent: {
            guard accountGeneration == currentGeneration else { throw CancellationError() }
        }) {
            await Task.yield()
            accountGeneration = 3
        }
        do {
            try await lateCallback.value
            preconditionFailure("A late callback must not acknowledge an expired account lease")
        } catch is CancellationError {}

        let otherItem = UUID()
        var otherState = WatchSupplementState()
        precondition(otherState.accept(.init(ownerID: other, day: day, revision: 1,
            items: [.init(id: otherItem, name: "Vitamin D", dose: "As configured on iPhone")],
            checkedIDs: [], acknowledgedIDs: []), ownerID: other))
        precondition(!otherState.accept(snapshot, ownerID: other), "A delayed old-account snapshot cannot switch owners")
        precondition(otherState.visibleItems.map(\.id) == [otherItem] && otherState.pending.isEmpty)
        precondition(!otherState.preferences.hiddenIDs.contains(item), "Watch choices are owner scoped")
        var returnedOwner = restored
        returnedOwner.preferences.hiddenIDs = []
        let dayTwo = "2026-11-03"
        let newDayTick = returnedOwner.setTaken(itemID: item, taken: true, day: dayTwo, now: 200)!
        precondition(returnedOwner.pending.count == 2 && returnedOwner.isTaken(itemID: item, day: dayTwo))
        let oldDayAcknowledgment = returnedOwner.pending.first { $0.day == day }!
        precondition(returnedOwner.accept(.init(ownerID: owner, day: dayTwo, revision: 11,
            items: snapshot.items, checkedIDs: [], acknowledgedIDs: [oldDayAcknowledgment.id]), ownerID: owner))
        precondition(returnedOwner.pending == [newDayTick] && returnedOwner.isTaken(itemID: item, day: dayTwo),
            "Yesterday's acknowledgment cannot clear today's offline tick")
        precondition(returnedOwner.accept(.init(ownerID: owner, day: dayTwo, revision: 12,
            items: snapshot.items, checkedIDs: [item], acknowledgedIDs: [newDayTick.id]), ownerID: owner))
        precondition(returnedOwner.pending.isEmpty && returnedOwner.isTaken(itemID: item, day: dayTwo))
        precondition(!returnedOwner.isTaken(itemID: item, day: "2026-11-04"))
        print("Watch supplements: 52 checks passed")
    }
}
