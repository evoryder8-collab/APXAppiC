import Foundation

/// What today's session is actually for, at a glance.
///
/// The figure shows which muscles light up but never says why they were chosen,
/// so the model reads as decoration. This is the missing half: what the session
/// trains, what it is trying to produce, and the one piece of reasoning behind
/// the shape it takes. Written to be read in about fifteen seconds, standing up,
/// before starting.
enum SessionBriefing {

    /// What a session is trying to produce. A day is rarely one thing, so this
    /// is the dominant intent rather than the only one.
    enum Intent: String, Sendable {
        case hypertrophy
        case strength
        case endurance
        case mobility
        case conditioning
        case restoration

        var label: String {
            switch self {
            case .hypertrophy: "Muscle growth"
            case .strength: "Strength"
            case .endurance: "Endurance"
            case .mobility: "Range of motion"
            case .conditioning: "Conditioning"
            case .restoration: "Restoration"
            }
        }
    }

    struct Briefing: Sendable, Equatable {
        let title: String
        let intent: Intent
        /// Muscles doing the work, in plain words.
        let primary: [String]
        /// Muscles helping, which is why they may feel it tomorrow.
        let secondary: [String]
        /// Why the session is shaped this way. One idea, not a lecture.
        let rationale: String
        /// The single thing that most changes the result today.
        let focus: String
    }

    static func briefing(dayType: String, exercises: [String] = []) -> Briefing {
        let groups = MuscleMapView.groups(for: dayType, exercises: exercises)
        let primary = groups.primary.map(muscleName)
        let secondary = groups.secondary.map(muscleName)

        switch dayType {
        case "legs_a":
            return Briefing(
                title: "Lower body, heavy base",
                intent: .hypertrophy,
                primary: primary, secondary: secondary,
                rationale: "Hinging and squatting on the same day covers the whole leg: the hinge loads the hamstrings and glutes at long muscle lengths, which builds more than working them short does.",
                focus: "Control the lowering. That is the half of the rep that does most of the building."
            )
        case "legs_b":
            return Briefing(
                title: "Lower body, single leg",
                intent: .strength,
                primary: primary, secondary: secondary,
                rationale: "One leg at a time exposes the side that has been quietly doing less, and asks the hip to stabilise rather than just extend. Both sides get the same work regardless of which is stronger.",
                focus: "Match the weaker side. The stronger leg does the reps the weaker one can hold form for."
            )
        case "push":
            return Briefing(
                title: "Pushing day",
                intent: .hypertrophy,
                primary: primary, secondary: secondary,
                rationale: "Chest, shoulders and triceps share every pressing movement, so they are trained together rather than on three separate days competing for the same recovery.",
                focus: "Full range at the bottom. Cutting depth to add weight trades away most of the growth."
            )
        case "pull":
            return Briefing(
                title: "Pulling day",
                intent: .hypertrophy,
                primary: primary, secondary: secondary,
                rationale: "Pulling balances the pressing you already do, in life as much as in training. The upper back is what holds posture together when everything else pulls you forward.",
                focus: "Lead with the elbow, not the hand, so the back works instead of the arms."
            )
        case "upper":
            return Briefing(
                title: "Upper body",
                intent: .hypertrophy,
                primary: primary, secondary: secondary,
                rationale: "Push and pull in one session, so the whole upper body gets trained twice a week without needing four separate days to do it.",
                focus: "Keep the rest honest. Short rest here costs you the later sets."
            )
        case "mobility":
            return Briefing(
                title: "Mobility and reset",
                intent: .mobility,
                primary: primary, secondary: secondary,
                rationale: "Range you can control is the range you keep. This works the hips and the upper back through positions that sitting takes away, holding them long enough for the nervous system to accept them.",
                focus: "Breathe out at the end of each position. Holding your breath keeps the tension you came to release."
            )
        case "fix":
            return Briefing(
                title: "Postural work",
                intent: .restoration,
                primary: primary, secondary: secondary,
                rationale: "Small muscles that hold position rather than move weight. They respond to frequency and control, not load, which is why the weights look light.",
                focus: "Slow and exact beats heavy. If you can feel it in the wrong place, take weight off."
            )
        case "t25":
            return Briefing(
                title: "Conditioning",
                intent: .conditioning,
                primary: primary, secondary: secondary,
                rationale: "Whole body, led by the trunk, at a pace that keeps the heart rate up. This trains how long you can work rather than how much you can lift.",
                focus: "Keep moving at a pace you could hold to the end, not one that needs a rescue halfway."
            )
        case "rest":
            return Briefing(
                title: "Rest day",
                intent: .restoration,
                primary: [], secondary: [],
                rationale: "No muscle group is prescribed today. Recovery is where the work you already completed becomes adaptation.",
                focus: "Rest, hydrate and let the next hard session stay productive."
            )
        default:
            return Briefing(
                title: "Your session",
                intent: .hypertrophy,
                primary: primary, secondary: secondary,
                rationale: "Built from the movements you chose, so the muscles shown are the ones your own exercises actually load.",
                focus: "Log the weight you used. Next week's session is built from it."
            )
        }
    }

    /// Model identifiers into words people use.
    static func muscleName(_ identifier: String) -> String {
        switch identifier {
        case "glutes": "Glutes"
        case "hamstrings": "Hamstrings"
        case "quads": "Quads"
        case "calves": "Calves"
        case "lowerback": "Lower back"
        case "upperback": "Upper back"
        case "adductors": "Inner thigh"
        case "abductors": "Outer hip"
        case "hipflexors": "Hip flexors"
        case "chest": "Chest"
        case "shoulders": "Shoulders"
        case "triceps": "Triceps"
        case "biceps": "Biceps"
        case "forearms": "Forearms"
        case "lats": "Lats"
        case "traps": "Traps"
        case "abs": "Abs"
        case "obliques": "Obliques"
        case "neck": "Neck"
        default: identifier.capitalized
        }
    }
}
