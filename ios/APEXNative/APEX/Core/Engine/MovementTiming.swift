import Foundation

/// The timings a guided session actually runs on.
///
/// The native player inherited the web player's defect verbatim, comment and
/// all: side switches fired only for exercises whose *name* matched a regular
/// expression for split squats, and lasted a fixed three seconds. Everything
/// else single-sided -- single-arm rows, lunges, single-leg deadlifts, Pallof
/// presses, carries -- sent the follower straight from one side to the other
/// with no pause at all.
///
/// Each interval here is derived from the movement instead. The facts come from
/// the same library the web app uses, exported by
/// `Tools/generate-movement-timing.mts`, so neither side can drift.
enum MovementTiming {
    struct Movement: Decodable {
        let id: String
        let name: String
        let setupSeconds: Int
        let fatigueCost: Int
        let unilateral: Bool
        /// Kit that has to be moved, re-pinned or walked around before the
        /// second side can start.
        let repositioning: Bool

        private enum CodingKeys: String, CodingKey {
            case id, name, unilateral, repositioning
            case setupSeconds = "setup_seconds"
            case fatigueCost = "fatigue_cost"
        }
    }

    private struct Payload: Decodable {
        let movements: [Movement]
        let aliases: [String: String]
    }

    private static let payload: Payload = {
        guard let url = Bundle.main.url(forResource: "movement-timing", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return Payload(movements: [], aliases: [:])
        }
        return decoded
    }()

    private static let byID: [String: Movement] = Dictionary(
        uniqueKeysWithValues: payload.movements.map { ($0.id, $0) }
    )

    /// Programme rows carry their own authored names -- "Pull-Ups (different
    /// grip than Wed)", "Bulgarian Split Squat (backpack)" -- so resolving one
    /// has to survive the parenthetical.
    private static let byNormalisedName: [String: Movement] = {
        var map: [String: Movement] = [:]
        for movement in payload.movements {
            map[normalise(movement.name)] = movement
            map[normalise(movement.id)] = movement
        }
        return map
    }()

    private static func normalise(_ value: String) -> String {
        var stripped = value
        while let open = stripped.firstIndex(of: "("),
              let close = stripped[open...].firstIndex(of: ")") {
            stripped.removeSubrange(open...close)
        }
        return stripped.lowercased().filter { $0.isLetter }
    }

    static func movement(named name: String, movementID: String? = nil) -> Movement? {
        if let movementID, let hit = byID[movementID] { return hit }
        if let aliased = payload.aliases[name], let hit = byID[aliased] { return hit }
        return byNormalisedName[normalise(name)]
    }

    /// How long switching sides genuinely takes.
    ///
    /// Two things happen and only one of them is transition. The working limb
    /// has to be swapped over, which takes as long as the equipment makes it
    /// take -- resetting a rear foot on a bench is not the same as moving a
    /// dumbbell to the other hand. But on anything systemically hard the
    /// limiter is breathing rather than the limb, and a split squat leaves most
    /// people needing a moment before the second leg is worth training. Three
    /// seconds covered neither.
    static func sideSwitchSeconds(for movement: Movement?) -> Int {
        guard let movement else { return 10 }
        let repositioning = movement.repositioning ? 12 : 4
        let breather = movement.fatigueCost >= 4 ? 15 : movement.fatigueCost >= 3 ? 8 : 0
        return min(30, repositioning + breather)
    }

    /// How long the gap between two exercises should be.
    ///
    /// The finished exercise still needs its recovery -- the last set is not
    /// free just because it was the last -- and the next one needs setting up.
    /// Those overlap rather than stack, because setting up is what you do while
    /// resting, so this is the longer of the two rather than their sum.
    static func transitionSeconds(
        finished: Movement?,
        next: Movement?,
        authoredRest: Int
    ) -> Int {
        let setup = next?.setupSeconds ?? 30
        var recovery = authoredRest > 0 ? authoredRest : 60
        // Walking away from a heavy hinge into the next exercise is where
        // sessions quietly become harder than they were written to be.
        if let finished, finished.fatigueCost >= 4 { recovery = max(recovery, 90) }
        return max(recovery, setup)
    }
}
