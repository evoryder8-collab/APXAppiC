import Foundation

/*
 * Meals on the Watch: the dayline's blocks, what each one already holds, and
 * the foods to add to it, ranked by what went into the same block yesterday,
 * then favourites, then the phone's Food Memory for that block.
 *
 * The phone publishes a snapshot. The Watch keeps it with its own additions,
 * so it works away from the phone. An addition is an intent with its own ID:
 * the phone adds it to that block's meal once and acknowledges it in a later
 * snapshot, and only then does the Watch let go of it.
 */
enum WatchMealKeys {
    static let snapshot = "fitr.meals.snapshot.v1"
    static let mutation = "fitr.meals.mutation.v1"

    static func state(ownerID: UUID) -> String {
        "fitr.watch.meals.state.\(ownerID.uuidString.lowercased()).v1"
    }

    static func journal(ownerID: UUID) -> String {
        "fitr.phone.meals.journal.\(ownerID.uuidString.lowercased()).v1"
    }
}

/// A food as the Watch shows and counts it. `id` is Food Memory's: the catalogue food's ID, or
/// "history:<snapshot>" for a food only logged history knows.
struct WatchMealFood: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let kcal100: Double
    let protein100: Double
    let carbs100: Double
    let fat100: Double
    /// The meal snapshot's basis and state, so the phone can rebuild a food it no longer holds.
    let basis: String
    let preparation: String
}

/// An amount of one food: the quantity in its unit and what one unit weighs.
struct WatchMealPortion: Codable, Equatable, Hashable, Sendable {
    let foodID: String
    var quantity: Double
    /// "g", "ml", "piece" or "serving".
    let unit: String
    /// Grams (or millilitres) in one unit; 1 for g and ml.
    let gramsPerUnit: Double
    /// The logged entry this amount was read from: the phone copies its snapshot, as Same as yesterday does.
    var entryID: UUID? = nil

    var equivalentAmount: Double { quantity * gramsPerUnit }

    var isLoggable: Bool {
        quantity.isFinite && quantity > 0 && gramsPerUnit.isFinite && gramsPerUnit > 0
            && equivalentAmount <= 100_000
    }

    /// Rounded per food, as the phone stores each logged entry.
    func kcal(_ food: WatchMealFood) -> Double {
        (food.kcal100 * equivalentAmount / 100).rounded()
    }

    func protein(_ food: WatchMealFood) -> Double {
        (food.protein100 * equivalentAmount / 100).rounded()
    }

    private var isMeasured: Bool { unit == "g" || unit == "ml" }

    /// One turn of the crown: 5 or 10 g, half a serving, a whole piece unless the amount is already a half.
    var step: Double {
        if isMeasured { return quantity < 50 ? 5 : 10 }
        if unit == "serving" { return 0.5 }
        return quantity.rounded() == quantity ? 1 : 0.5
    }

    var maximum: Double { max(quantity * 4, isMeasured ? 1_000 : 12) }
}

/// One food logged into a dayline block.
struct WatchMealLog: Codable, Equatable, Sendable {
    let day: String
    let block: String
    let portion: WatchMealPortion
    let kcal: Double
    /// A planned prescription written as a meal: it counts, but nobody chose it, so it is never suggested.
    var planned = false
}

struct WatchMealBlock: Codable, Equatable, Identifiable, Sendable {
    /// The dayline block's kind: breakfast, lunch, dinner, snack, post_workout.
    let id: String
    /// The dayline's own name for it, in the app's language.
    let label: String
    /// "HH:mm"
    let time: String

    var minute: Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

struct WatchMealSnapshot: Codable, Equatable, Sendable {
    let ownerID: UUID
    var revision: UInt64
    /// The day's enabled blocks in time order.
    var blocks: [WatchMealBlock]
    /// Every food the lists below refer to.
    var foods: [WatchMealFood]
    /// Everything logged on the phone's today and the day before, in each block's order.
    var logs: [WatchMealLog]
    var favourites: [WatchMealPortion]
    /// Per block, the phone's Food Memory ranking for it, at the amounts last used there.
    var memory: [String: [WatchMealPortion]]
    var acknowledgedIDs: [UUID]

    /// Compressed for the trip: it shares the phone's one application context with water and supplements,
    /// and a busy history repeats the same keys and IDs many times over.
    func encoded() throws -> Data {
        try (JSONEncoder().encode(self) as NSData).compressed(using: .lzfse) as Data
    }

    static func decode(_ data: Data) throws -> WatchMealSnapshot {
        try JSONDecoder().decode(Self.self, from: (data as NSData).decompressed(using: .lzfse) as Data)
    }
}

struct WatchMealItem: Codable, Equatable, Identifiable, Sendable {
    /// Becomes the logged entry's ID, which is how a replay is recognised.
    let id: UUID
    let food: WatchMealFood
    let portion: WatchMealPortion
}

struct WatchMealMutation: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let ownerID: UUID
    let day: String
    let block: String
    let addedAt: Date
    let items: [WatchMealItem]
}

/// One account's meals on the Watch: the phone's last snapshot and the additions it has not yet confirmed.
struct WatchMealState: Codable, Equatable, Sendable {
    var snapshot: WatchMealSnapshot?
    var pending: [WatchMealMutation] = []

    enum Reason: Equatable, Sendable {
        case yesterday
        case favourite
        case recent
    }

    struct Line: Identifiable, Equatable, Sendable {
        let id: String
        let food: WatchMealFood
        let portion: WatchMealPortion
        let kcal: Double
        var planned = false
        var isPending = false
    }

    struct Suggestion: Identifiable, Equatable, Sendable {
        let food: WatchMealFood
        let portion: WatchMealPortion
        let reason: Reason

        var id: String { food.id }
        var kcal: Double { portion.kcal(food) }
    }

    @discardableResult
    mutating func accept(_ incoming: WatchMealSnapshot, ownerID: UUID) -> Bool {
        guard incoming.ownerID == ownerID else { return false }
        if let snapshot, snapshot.ownerID == ownerID, incoming.revision <= snapshot.revision { return false }
        snapshot = incoming
        // Only the phone's acknowledgement lets go: a copy in its snapshot may not have reached the server yet.
        let acknowledged = Set(incoming.acknowledgedIDs)
        pending.removeAll { acknowledged.contains($0.id) }
        return true
    }

    /// Records foods added to a block on this Watch. Nothing is sent unless every portion can be logged.
    mutating func add(
        _ additions: [(food: WatchMealFood, portion: WatchMealPortion)],
        block: String,
        day: String,
        at date: Date = Date()
    ) -> WatchMealMutation? {
        guard let snapshot, snapshot.blocks.contains(where: { $0.id == block }),
              !additions.isEmpty, additions.allSatisfy({ $0.portion.isLoggable }) else { return nil }
        let mutation = WatchMealMutation(
            ownerID: snapshot.ownerID, day: day, block: block, addedAt: date,
            items: additions.map { WatchMealItem(id: UUID(), food: $0.food, portion: $0.portion) }
        )
        pending.append(mutation)
        return mutation
    }

    /// What a block holds on a day: the phone's record, then this Watch's unconfirmed additions.
    func logged(day: String, block: String) -> [Line] {
        let foods = foodsByID
        var lines: [Line] = []
        for (index, log) in (snapshot?.logs ?? []).enumerated() where log.day == day && log.block == block {
            guard let food = foods[log.portion.foodID] else { continue }
            // A saved Watch addition keeps its ID, so its row stays the same row from pending to confirmed.
            let id = log.portion.entryID?.uuidString ?? "log-\(index)"
            lines.append(Line(id: id, food: food, portion: log.portion, kcal: log.kcal, planned: log.planned))
        }
        for mutation in pending where mutation.day == day && mutation.block == block {
            for item in mutation.items where !savedIDs.contains(item.id) {
                lines.append(Line(id: item.id.uuidString, food: item.food, portion: item.portion,
                                  kcal: item.portion.kcal(item.food), isPending: true))
            }
        }
        return lines
    }

    /// The day's energy across every block, the same sum of stored entries the phone shows.
    func kcal(day: String) -> Double {
        let logged = (snapshot?.logs ?? []).filter { $0.day == day }.reduce(0) { $0 + $1.kcal }
        let added = pending.filter { $0.day == day }.flatMap(\.items)
            .filter { !savedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.portion.kcal($1.food) }
        return logged + added
    }

    /// Foods to add to a block: yesterday's, at yesterday's amounts and in its order; then favourites,
    /// those this block uses most first; then the rest of the block's Food Memory. A food already in
    /// today's meal is not offered again.
    func suggestions(day: String, block: String, limit: Int = 16) -> [Suggestion] {
        guard let snapshot else { return [] }
        let foods = foodsByID
        var seen = Set(logged(day: day, block: block).map(\.food.id))
        var result: [Suggestion] = []
        func take(_ food: WatchMealFood?, _ portion: WatchMealPortion, _ reason: Reason) {
            guard result.count < limit, let food, portion.isLoggable, seen.insert(food.id).inserted else { return }
            result.append(Suggestion(food: food, portion: portion, reason: reason))
        }
        for line in logged(day: Self.previousDay(day), block: block) where !line.planned {
            take(line.food, line.portion, .yesterday)
        }
        let memory = snapshot.memory[block] ?? []
        let rank = Dictionary(memory.enumerated().map { ($1.foodID, $0) }, uniquingKeysWith: { first, _ in first })
        let favourites = snapshot.favourites.enumerated().sorted {
            (rank[$0.element.foodID] ?? Int.max, $0.offset) < (rank[$1.element.foodID] ?? Int.max, $1.offset)
        }
        for (_, favourite) in favourites {
            // The amount this block last used beats the favourite's general one.
            let portion = rank[favourite.foodID].map { memory[$0] } ?? favourite
            take(foods[favourite.foodID], portion, .favourite)
        }
        for portion in memory { take(foods[portion.foodID], portion, .recent) }
        return result
    }

    /// The block nearest the clock, the one most likely being eaten; a tie goes to the earlier one.
    static func currentBlock(_ blocks: [WatchMealBlock], minute: Int) -> String? {
        blocks.compactMap { block in block.minute.map { (block.id, $0) } }
            .min { left, right in
                func distance(_ value: Int) -> Int { min(abs(value - minute), 1440 - abs(value - minute)) }
                let (leftDistance, rightDistance) = (distance(left.1), distance(right.1))
                return leftDistance == rightDistance ? left.1 < right.1 : leftDistance < rightDistance
            }?.0
    }

    /// "2026-11-22" → "2026-11-21", by the calendar rather than by 24 hours, so a clock change cannot skip a day.
    static func previousDay(_ day: String) -> String {
        guard let date = ISO8601DateFormatter.apexDateOnly.date(from: day),
              let previous = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: date) else { return "" }
        return previous.apexDateKey
    }

    /// Additions the phone has logged already: they keep the Watch's IDs, so they are counted once, in its record.
    private var savedIDs: Set<UUID> {
        Set((snapshot?.logs ?? []).compactMap(\.portion.entryID))
    }

    private var foodsByID: [String: WatchMealFood] {
        var foods: [String: WatchMealFood] = [:]
        for food in snapshot?.foods ?? [] { foods[food.id] = food }
        return foods
    }
}
