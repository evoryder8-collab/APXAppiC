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
        /// How the movement is dosed: timed reps, a hold, a carry, ground
        /// contacts, breath-paced work, and so on.
        let prescriptionMode: String
        let loadable: Bool
        let entityType: String
        let disciplines: [String]
        let prescription: String

        private enum CodingKeys: String, CodingKey {
            case id, name, unilateral, repositioning, loadable
            case setupSeconds = "setup_seconds"
            case fatigueCost = "fatigue_cost"
            case prescriptionMode = "prescription_mode"
            case entityType = "entity_type"
            case disciplines, prescription
        }

        /// Whether counting a rep cadence means anything here. A stretch flow,
        /// a plank, a carry and a jump are all dosed by something other than
        /// the tempo of a repetition.
        var countsReps: Bool { prescriptionMode == "tempo_reps" }

        /// Whether asking what was lifted makes sense afterwards. A mobility
        /// drill has no weight, and asking for one is noise at best.
        var recordsLoad: Bool { loadable && prescriptionMode != "breath" }

        /// What the unit of work is called, so the whole player can say it
        /// rather than calling everything a set. A stretch flow is held once,
        /// a carry is walked once, a jump is a round of ground contacts.
        var setNoun: String {
            switch prescriptionMode {
            case "hold", "carry": return "hold"
            case "breath", "quality": return "exercise"
            case "contacts", "interval": return "round"
            default: return "set"
            }
        }

        var setNounPlural: String {
            switch setNoun {
            case "hold": return "holds"
            case "exercise": return "exercises"
            case "round": return "rounds"
            default: return "sets"
            }
        }

        /// Whether the total is worth stating at all. "1 of 1" on something
        /// performed once is noise dressed as progress.
        var showsSetCount: Bool { prescriptionMode != "breath" }
    }

    /// The noun for an exercise the library does not know, falling back to how
    /// the row itself is written rather than assuming repetitions.
    static func fallbackNoun(repUnit: String) -> String {
        switch repUnit {
        case "seconds", "minutes": return "hold"
        default: return "set"
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

    static var cataloguedMovements: [Movement] { payload.movements }

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

    private static let byNormalisedAlias: [String: Movement] = {
        var map: [String: Movement] = [:]
        for (alias, movementID) in payload.aliases {
            if let movement = byID[movementID] { map[normalise(alias)] = movement }
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
        let key = normalise(name)
        return byNormalisedAlias[key] ?? byNormalisedName[key]
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
    /// Explicit zero never becomes a default recovery. Positive rest retains
    /// the existing high-fatigue safety floor. The next movement may still
    /// require setup; setup and recovery overlap, so the longer one wins.
    static func transitionSeconds(
        finished: Movement?,
        next: Movement?,
        authoredRest: Int
    ) -> Int {
        let setup = next?.setupSeconds ?? 30
        var recovery = max(0, authoredRest)
        if authoredRest > 0, let finished, finished.fatigueCost >= 4 {
            recovery = max(recovery, 90)
        }
        return max(recovery, setup)
    }
}
