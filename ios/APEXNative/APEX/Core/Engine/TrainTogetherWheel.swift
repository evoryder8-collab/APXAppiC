import Foundation

/*
 * The challenge wheel. In a room opened without a workout, everyone ticks the
 * kit they have, the host picks a focus and spins, and every phone shows the
 * same wheel landing on the same challenge at the same moment, because the
 * spin is part of the room's snapshot and its clock is the server's.
 */
extension TrainTogether {
    enum Focus: String, Codable, CaseIterable, Sendable {
        case fullBody = "full_body"
        case push, pull
        case upperBody = "upper_body"
        case lowerBody = "lower_body"
        case hiit

        var label: String {
            switch self {
            case .fullBody: "Full body"
            case .push: "Push"
            case .pull: "Pull"
            case .upperBody: "Upper body"
            case .lowerBody: "Lower body"
            case .hiit: "HIIT"
            }
        }
    }

    /// Kit someone may tick. Bodyweight, floor space and a wall are always
    /// there, and a mat only makes a movement comfortable, so none of those is asked.
    enum Kit: String, Codable, CaseIterable, Sendable {
        case dumbbells, kettlebell, bands
        case pullUpBar = "pull_up_bar"
        case bench, backpack, towel, chair
        case skippingRope = "skipping_rope"

        var label: String {
            switch self {
            case .dumbbells: "Dumbbells"
            case .kettlebell: "Kettlebell"
            case .bands: "Resistance bands"
            case .pullUpBar: "Pull-up bar"
            case .bench: "Bench or step"
            case .backpack: "Backpack"
            case .towel: "Towel"
            case .chair: "Sturdy chair"
            case .skippingRope: "Skipping rope"
            }
        }

        var symbol: String {
            switch self {
            case .dumbbells: "dumbbell.fill"
            case .kettlebell: "scalemass.fill"
            case .bands: "point.topleft.down.to.point.bottomright.curvepath"
            case .pullUpBar: "figure.strengthtraining.functional"
            case .bench: "rectangle.portrait.bottomhalf.filled"
            case .backpack: "backpack.fill"
            case .towel: "rectangle.and.hand.point.up.left.fill"
            case .chair: "chair.fill"
            case .skippingRope: "figure.jumprope"
            }
        }

        /// Catalogue equipment names that need no tick.
        static let alwaysThere: Set<String> = [#"Bodyweight"#, #"Floor Space"#, #"Wall"#, #"Mat"#]

        static func named(_ equipment: String) -> Kit? {
            switch equipment {
            case #"Dumbbells"#: .dumbbells
            case #"Kettlebell"#: .kettlebell
            case #"Bands"#: .bands
            case #"Pull Up Bar"#: .pullUpBar
            case #"Bench"#, #"Adjustable Bench"#, #"Step"#, #"Plyo Box"#: .bench
            case #"Backpack"#: .backpack
            case #"Towel"#, #"Sliders"#: .towel
            case #"Chair"#: .chair
            case #"Skipping Rope"#: .skippingRope
            default: nil
            }
        }

        /// What a catalogue entry such as "Bench or Plyo Box or Step · Dumbbells"
        /// asks for: each inner list is "any one of these". Options the wheel
        /// never asks about (rings, a machine) are dropped; nil when a part
        /// has none left, such as a barbell.
        static func needs(_ equipment: String) -> [[Kit]]? {
            var needs: [[Kit]] = []
            for part in equipment.split(separator: "·") {
                let options = part.components(separatedBy: " or ").map { $0.trimmingCharacters(in: .whitespaces) }
                if options.contains(where: alwaysThere.contains) { continue }
                var kit: [Kit] = []
                for item in options.compactMap(named) where !kit.contains(item) { kit.append(item) }
                guard !kit.isEmpty else { return nil }
                needs.append(kit)
            }
            return needs
        }
    }

    /// A short, written workout the wheel can land on, built only from
    /// catalogue movements so it has their artwork, timing and translations.
    struct Challenge: Identifiable, Equatable, Sendable {
        struct Move: Equatable, Sendable {
            let movementID: String
            let sets: Int
            /// Reps, or seconds for a timed movement.
            let reps: Int
            let rest: Int
        }

        let id: String
        let name: String
        let focus: Focus
        let moves: [Move]

        static let warmupText = "Warm up for 3 minutes: march on the spot, circle your arms and hips, then 10 easy squats."
        static let warmupSeconds = 180

        static func named(_ id: String) -> Challenge? { library.first { $0.id == id } }

        /// The moves as the custom workout builder holds them; one missing from the catalogue is left out.
        var picks: [CustomWorkoutBuilder.Pick] {
            moves.compactMap { move in
                ExerciseCatalog.all.first { $0.movementID == move.movementID }.map {
                    CustomWorkoutBuilder.Pick(item: $0, sets: move.sets, reps: move.reps, rest: move.rest)
                }
            }
        }

        var items: [ExerciseCatalogItem] { picks.map(\.item) }

        /// The kit it needs, each entry "any one of these"; nil if any movement
        /// needs kit the wheel never asks about.
        var kit: [[Kit]]? {
            var needs: [[Kit]] = []
            for item in items {
                guard let more = Kit.needs(item.equipment) else { return nil }
                for options in more where !needs.contains(options) { needs.append(options) }
            }
            return needs
        }

        var matHelps: Bool { items.contains { $0.equipment.contains(#"Mat"#) } }

        func fits(_ common: Set<Kit>) -> Bool {
            guard let kit else { return false }
            return kit.allSatisfy { $0.contains(where: common.contains) }
        }

        func exercises() -> [Exercise] {
            CustomWorkoutBuilder.exerciseRows(userID: UUID(), programDayID: UUID(), picks: picks)
        }

        func plan() -> Plan {
            Plan(
                name: name, warmupText: Self.warmupText, warmupDuration: Self.warmupSeconds,
                exercises: exercises().map(PlanExercise.init)
            )
        }

        /// The builder's estimate, so a workout reads the same length everywhere, plus the warm-up.
        var estimatedMinutes: Int {
            CustomWorkoutBuilder.estimatedMinutes(for: picks) + Self.warmupSeconds / 60
        }
    }

    /// The wheel as the room holds it: the focus the host chose and the last spin.
    struct Wheel: Codable, Equatable, Sendable {
        struct Spin: Codable, Equatable, Sendable {
            /// Server time the spin started; every phone turns the wheel from it.
            var at: Date
            /// Challenge ids round the wheel, in order.
            var slots: [String]
            var landing: Int
        }

        var focus: Focus
        var spin: Spin?

        static let spinSeconds: TimeInterval = 6
        static let fewestSlots = 6
        static let mostSlots = 12

        /// Kit everyone in the room has. Anyone who has not answered, or whose
        /// answer has not arrived, counts as having none, so nobody is handed a
        /// workout they cannot do.
        static func commonKit(_ answers: [[Kit]?], headcount: Int) -> Set<Kit> {
            guard answers.count >= headcount else { return [] }
            return answers.reduce(Set(Kit.allCases)) { $0.intersection(Set($1 ?? [])) }
        }

        static func eligible(focus: Focus, common: Set<Kit>) -> [Challenge] {
            Challenge.library.filter { $0.focus == focus && $0.fits(common) }
        }

        /// The wheel's slots: at most twelve, a short list repeated round it so it still looks full.
        static func slots(for ids: [String]) -> [String] {
            var slots = Array(ids.prefix(mostSlots))
            let distinct = slots
            while !distinct.isEmpty, slots.count < fewestSlots { slots.append(distinct[slots.count % distinct.count]) }
            return slots
        }

        /// The slots a spin shows and where it stops, chosen on the phone that spins.
        static func draw(from eligible: [Challenge], using generator: inout some RandomNumberGenerator) -> (slots: [String], landing: Int)? {
            let slots = slots(for: eligible.shuffled(using: &generator).map(\.id))
            guard !slots.isEmpty else { return nil }
            return (slots, Int.random(in: 0..<slots.count, using: &generator))
        }

        /// The slot under the pointer after the wheel has turned `angle` degrees.
        static func slotUnderPointer(angle: Double, slots: Int) -> Int {
            guard slots > 0 else { return 0 }
            let turned = (-angle).truncatingRemainder(dividingBy: 360) + 360
            return Int(turned.truncatingRemainder(dividingBy: 360) / (360 / Double(slots))) % slots
        }

        /// Degrees turned `elapsed` seconds into a spin: five full turns easing
        /// out, stopping with the landing slot's middle under the pointer at the top.
        static func angle(slots: Int, landing: Int, elapsed: TimeInterval) -> Double {
            guard slots > 0 else { return 0 }
            let segment = 360 / Double(slots)
            let target = 5 * 360 + 360 - (Double(landing) + 0.5) * segment
            let progress = min(max(elapsed / spinSeconds, 0), 1)
            return target * (1 - pow(1 - progress, 3))
        }
    }
}

extension TrainTogether.Wheel.Spin {
    /// A spin whose landing is off its wheel is refused here, so no phone ever
    /// draws or reads a slot that is not there, whoever sent it.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        at = try values.decode(Date.self, forKey: .at)
        slots = try values.decode([String].self, forKey: .slots)
        landing = try values.decode(Int.self, forKey: .landing)
        guard slots.indices.contains(landing), slots.count <= TrainTogether.Wheel.mostSlots else {
            throw DecodingError.dataCorruptedError(forKey: .landing, in: values, debugDescription: #"landing off the wheel"#)
        }
    }
}
