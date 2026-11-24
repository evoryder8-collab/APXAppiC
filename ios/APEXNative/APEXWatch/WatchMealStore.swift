import Foundation
import WatchKit

/// Meals on this Watch for the account the phone last connected. Additions are kept here until the
/// phone confirms them, so meals can be logged away from the phone.
@MainActor
final class WatchMealStore: ObservableObject {
    @Published private(set) var state = WatchMealState()
    private(set) var ownerID: UUID?
    private let defaults: UserDefaults
    private let connectivity: WatchHydrationConnectivity
    /// The wearer's confirmation-haptics setting, which the water page already honours.
    private let haptics: () -> Bool
    var hapticsEnabled: Bool { haptics() }

    init(
        defaults: UserDefaults,
        connectivity: WatchHydrationConnectivity,
        ownerID: UUID?,
        haptics: @escaping () -> Bool
    ) {
        self.defaults = defaults
        self.connectivity = connectivity
        self.haptics = haptics
        #if DEBUG
        if ProcessInfo.processInfo.environment["APEX_WATCH_PREVIEW_MEALS"] != nil {
            let preview = Self.previewSnapshot()
            self.ownerID = preview.ownerID
            state.accept(preview, ownerID: preview.ownerID)
            return
        }
        #endif
        if let ownerID { restore(ownerID: ownerID) }
    }

    /// The phone's snapshot. The caller has already checked it belongs to the connected account.
    func accept(_ snapshot: WatchMealSnapshot) {
        restore(ownerID: snapshot.ownerID)
        guard state.accept(snapshot, ownerID: snapshot.ownerID) else { return }
        persist()
        replayPending()
    }

    /// Another account, or none, on the phone. This account's unsent additions stay stored for its return.
    func disconnect() {
        ownerID = nil
        state = WatchMealState()
    }

    func replayPending() {
        guard let ownerID else { return }
        for mutation in state.pending where mutation.ownerID == ownerID {
            connectivity.send(mutation)
        }
    }

    /// Adds foods to a block on the day the page shows. Returns false when nothing could be recorded.
    @discardableResult
    func add(
        _ additions: [(food: WatchMealFood, portion: WatchMealPortion)],
        block: String,
        day: String
    ) -> Bool {
        guard let ownerID, state.snapshot?.ownerID == ownerID,
              let mutation = state.add(additions, block: block, day: day) else { return false }
        persist()
        connectivity.send(mutation)
        if haptics() { WKInterfaceDevice.current().play(.success) }
        return true
    }

    /// The account the phone connected; its stored meals and unsent additions come back with it.
    func follow(_ ownerID: UUID) {
        restore(ownerID: ownerID)
    }

    private func restore(ownerID: UUID) {
        guard self.ownerID != ownerID else { return }
        self.ownerID = ownerID
        state = defaults.data(forKey: WatchMealKeys.state(ownerID: ownerID))
            .flatMap { try? JSONDecoder().decode(WatchMealState.self, from: $0) }
            .flatMap { $0.snapshot?.ownerID == ownerID ? $0 : nil } ?? WatchMealState()
    }

    private func persist() {
        guard let ownerID, state.snapshot?.ownerID == ownerID,
              let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: WatchMealKeys.state(ownerID: ownerID))
    }

    #if DEBUG
    /// Launch with APEX_WATCH_PREVIEW_MEALS to see the meal pages without a phone.
    private static func previewSnapshot() -> WatchMealSnapshot {
        let today = Date().apexDateKey
        let yesterday = WatchMealState.previousDay(today)
        func food(_ id: String, _ name: String, _ kcal: Double, _ protein: Double) -> WatchMealFood {
            WatchMealFood(id: id, name: name, kcal100: kcal, protein100: protein, carbs100: 0, fat100: 0,
                          basis: "per_100g", preparation: "as_eaten")
        }
        let foods = [
            food("oats", "Rolled oats", 372, 13), food("skyr", "Skyr natural", 63, 11),
            food("berries", "Blueberries", 57, 0.7), food("eggs", "Eggs", 143, 12.6),
            food("chicken", "Chicken breast", 120, 23), food("rice", "Basmati rice, cooked", 130, 2.7),
            food("banana", "Banana", 89, 1.1), food("whey", "Whey protein", 380, 78),
        ]
        func portion(_ id: String, _ quantity: Double, _ unit: String = "g", _ grams: Double = 1) -> WatchMealPortion {
            WatchMealPortion(foodID: id, quantity: quantity, unit: unit, gramsPerUnit: grams)
        }
        func log(_ day: String, _ block: String, _ portion: WatchMealPortion) -> WatchMealLog {
            let kcal = foods.first { $0.id == portion.foodID }.map { portion.kcal($0) } ?? 0
            return WatchMealLog(day: day, block: block, portion: portion, kcal: kcal)
        }
        return WatchMealSnapshot(
            ownerID: UUID(uuidString: "D9A4729D-E301-4CED-A027-81AD3F7B94AB")!,
            revision: 1,
            blocks: [
                WatchMealBlock(id: "breakfast", label: "Breakfast", time: "07:00"),
                WatchMealBlock(id: "lunch", label: "Lunch", time: "13:00"),
                WatchMealBlock(id: "snack", label: "Snack", time: "16:00"),
                WatchMealBlock(id: "dinner", label: "Dinner", time: "19:00"),
                WatchMealBlock(id: "post_workout", label: "Evening recovery", time: "21:00"),
            ],
            foods: foods,
            logs: [
                log(yesterday, "breakfast", portion("oats", 60)), log(yesterday, "breakfast", portion("skyr", 250)),
                log(yesterday, "breakfast", portion("berries", 100)),
                log(yesterday, "lunch", portion("chicken", 150)), log(yesterday, "lunch", portion("rice", 200)),
                log(today, "breakfast", portion("eggs", 2, "piece", 55)),
            ],
            favourites: [portion("banana", 1, "piece", 120), portion("whey", 30), portion("skyr", 170)],
            memory: ["snack": [portion("banana", 1, "piece", 120)], "post_workout": [portion("whey", 30)]],
            acknowledgedIDs: []
        )
    }
    #endif
}
