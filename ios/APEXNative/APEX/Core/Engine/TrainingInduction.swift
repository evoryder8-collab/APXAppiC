import Foundation

/*
 * Building a starter programme from a few answers.
 *
 * A port of src/lib/trainingInduction.ts. The answers decide a caution level,
 * which decides how many sessions a week and which template set is used, and
 * the generated ids are byte-compatible with the web so the same person's plan
 * is one plan on both platforms rather than two.
 */
enum TrainingInduction {
    // MARK: - Answers

    struct Input: Equatable, Sendable {
        var startDate: String
        var inactivity: String = "under_three_months"
        var venue: String = "home"
        var equipment: [String] = []
        var painAreas: [String] = []
        var recentOperation = false
        var chronicLowerBackPain = false
        var sessionsPerWeek = 3
        var goal: String = "general"
    }

    struct Assessment: Equatable, Sendable {
        let caution: String
        let sessionsPerWeek: Int
        let reasons: [String]
    }

    /// A recent operation stops loaded training until a clinician says otherwise;
    /// a long layoff, back pain or current joint discomfort softens the plan.
    static func assess(_ input: Input) -> Assessment {
        if input.recentOperation {
            return Assessment(
                caution: "clearance",
                sessionsPerWeek: 2,
                reasons: ["Recent operation reported", "Loaded training waits for clinician clearance"]
            )
        }
        let longLayoff = input.inactivity == "six_to_twelve_months" || input.inactivity == "over_one_year"
        let cautious = longLayoff || input.chronicLowerBackPain || !input.painAreas.isEmpty
        var reasons: [String] = []
        if longLayoff { reasons.append("Long training gap reported") }
        if input.chronicLowerBackPain { reasons.append("Chronic lower-back pain reported") }
        if !input.painAreas.isEmpty { reasons.append("Current joint discomfort reported") }
        return Assessment(
            caution: cautious ? "cautious" : "standard",
            sessionsPerWeek: cautious && input.sessionsPerWeek == 4 ? 3 : input.sessionsPerWeek,
            reasons: reasons
        )
    }

    /// Which nutrition goal a training answer implies.
    ///
    /// The questionnaire asks what someone trains for; the profile stores how
    /// they eat. Only losing fat and building muscle actually pin the calories,
    /// so everything else maintains rather than guessing at a surplus nobody
    /// asked for.
    static func goalColumn(for trainingGoal: String) -> String {
        switch trainingGoal {
        case "fat_loss": "recomp"
        case "muscle": "bulk"
        default: "maintain"
        }
    }

    // MARK: - Equipment

    struct EquipmentOption: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
    }

    static let equipmentCatalog: [EquipmentOption] = [
        EquipmentOption(id: "adjustable_dumbbells", label: "Adjustable dumbbells"),
        EquipmentOption(id: "fixed_dumbbells", label: "Fixed dumbbells"),
        EquipmentOption(id: "resistance_bands", label: "Resistance bands"),
        EquipmentOption(id: "bench", label: "Training bench"),
        EquipmentOption(id: "pullup_bar", label: "Pull-up bar"),
        EquipmentOption(id: "kettlebell", label: "Kettlebell"),
        EquipmentOption(id: "suspension_trainer", label: "Suspension trainer"),
        EquipmentOption(id: "barbell_plates", label: "Barbell and plates"),
        EquipmentOption(id: "rack", label: "Squat rack"),
        EquipmentOption(id: "cable_machine", label: "Cable machine"),
        EquipmentOption(id: "cardio_machine", label: "Cardio machine"),
        EquipmentOption(id: "mat", label: "Exercise mat"),
    ]

    // MARK: - Templates

    private struct ExerciseSpec {
        let name: String
        var sets: Int = 2
        let repMin: Int
        let repMax: Int
        var unit: String = "reps"
        var perSide = false
        var rest: Int = 60
        var increment: Double = 0
        var notes: String?
        var optional = false
    }

    private struct SessionSpec {
        let name: String
        let type: String
        let minutes: Int
        let warmup: String
        let exercises: [ExerciseSpec]
    }

    private static func homeNames(_ equipment: [String]) -> [String: String] {
        let dumbbells = equipment.contains("adjustable_dumbbells") || equipment.contains("fixed_dumbbells")
        let bands = equipment.contains("resistance_bands")
        let pullup = equipment.contains("pullup_bar")
        return [
            "squat": dumbbells ? "Goblet Squat" : "Controlled Chair Squat",
            "hinge": dumbbells ? "Dumbbell Romanian Deadlift" : (bands ? "Band Hip Hinge" : "Bodyweight Hip Hinge"),
            "push": dumbbells ? "Dumbbell Floor Press" : "Incline Push-Up",
            "row": dumbbells ? "One-Arm Dumbbell Row" : (bands ? "Band Row" : "Towel Isometric Row"),
            "press": dumbbells ? "Seated Dumbbell Press" : (bands ? "Band Overhead Press" : "Incline Pike Press"),
            "pull": pullup ? "Assisted Pull-Up" : (bands ? "Band Lat Pulldown" : "Prone Lat Sweep"),
            "carry": dumbbells ? "Suitcase Carry" : "Backpack Carry",
        ]
    }

    private static func clearanceSessions() -> [SessionSpec] {
        let warmup = "Begin only after the clinician managing the operation has cleared these movements. Use a pain-free range."
        return [
            SessionSpec(
                name: "Clearance Reset A", type: "mobility", minutes: 18, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Diaphragmatic Breathing", repMin: 60, repMax: 90, unit: "seconds"),
                    ExerciseSpec(name: "Pain-Free Joint Circles", repMin: 5, repMax: 8, perSide: true),
                    ExerciseSpec(name: "Supported Sit-to-Stand", repMin: 6, repMax: 10, rest: 60,
                                 notes: "Stop with pain, instability or unusual symptoms."),
                    ExerciseSpec(name: "Easy Walk", sets: 1, repMin: 8, repMax: 12, unit: "minutes"),
                ]
            ),
            SessionSpec(
                name: "Clearance Reset B", type: "mobility", minutes: 18, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Easy Walk", sets: 1, repMin: 10, repMax: 15, unit: "minutes"),
                    ExerciseSpec(name: "Wall Shoulder Slide", repMin: 6, repMax: 10, rest: 45),
                    ExerciseSpec(name: "Supported Calf Raise", repMin: 8, repMax: 12, rest: 45),
                    ExerciseSpec(name: "Gentle Mobility Flow", sets: 1, repMin: 4, repMax: 6, unit: "minutes"),
                ]
            ),
        ]
    }

    private static func gymSessions(phase: String, count: Int) -> [SessionSpec] {
        let main = phase == "main"
        let sets = main ? 3 : 2
        let warmup = "Five minutes easy cardio, then two gradual practice sets for the first loaded movement."
        let fullBody = [
            SessionSpec(
                name: "Full Body A", type: "upper", minutes: main ? 52 : 38, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Leg Press", sets: sets, repMin: 8, repMax: 12, rest: 105, increment: 5),
                    ExerciseSpec(name: "Machine Chest Press", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5),
                    ExerciseSpec(name: "Seated Cable Row", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5),
                    ExerciseSpec(name: "Seated Leg Curl", sets: sets, repMin: 10, repMax: 15, rest: 75, increment: 2.5),
                    ExerciseSpec(name: "Pallof Press", repMin: 8, repMax: 12, perSide: true, rest: 45),
                ]
            ),
            SessionSpec(
                name: "Full Body B", type: "legs_b", minutes: main ? 54 : 40, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Dumbbell Romanian Deadlift", sets: sets, repMin: 8, repMax: 12, rest: 105, increment: 2.5),
                    ExerciseSpec(name: "Lat Pulldown", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5),
                    ExerciseSpec(name: "Machine Shoulder Press", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5),
                    ExerciseSpec(name: "Supported Split Squat", sets: sets, repMin: 8, repMax: 10, perSide: true, rest: 90, increment: 2.5),
                    ExerciseSpec(name: "Farmer Carry", sets: 3, repMin: 30, repMax: 45, unit: "seconds", rest: 60, increment: 2.5),
                ]
            ),
            SessionSpec(
                name: "Full Body C", type: "upper", minutes: main ? 52 : 38, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Hack Squat", sets: sets, repMin: 8, repMax: 12, rest: 105, increment: 5),
                    ExerciseSpec(name: "Incline Dumbbell Press", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5),
                    ExerciseSpec(name: "Chest-Supported Row", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2.5),
                    ExerciseSpec(name: "Cable Lateral Raise", repMin: 12, repMax: 18, rest: 45, increment: 1),
                    ExerciseSpec(name: "Dead Bug", repMin: 8, repMax: 12, perSide: true, rest: 45),
                ]
            ),
        ]
        if count < 4 { return Array(fullBody.prefix(count)) }
        return [
            SessionSpec(name: "Upper A", type: "upper", minutes: fullBody[0].minutes, warmup: warmup,
                        exercises: Array(fullBody[0].exercises.dropFirst())),
            SessionSpec(name: "Lower A", type: "legs_a", minutes: main ? 50 : 36, warmup: warmup,
                        exercises: [fullBody[0].exercises[0], fullBody[0].exercises[3], fullBody[1].exercises[3], fullBody[2].exercises[4]]),
            SessionSpec(name: "Upper B", type: "upper", minutes: fullBody[2].minutes, warmup: warmup,
                        exercises: Array(fullBody[2].exercises.dropFirst())),
            SessionSpec(name: "Lower B", type: "legs_b", minutes: main ? 50 : 36, warmup: warmup,
                        exercises: [fullBody[2].exercises[0], fullBody[1].exercises[0], fullBody[0].exercises[3], fullBody[1].exercises[4]]),
        ]
    }

    private static func homeSessions(phase: String, count: Int, equipment: [String]) -> [SessionSpec] {
        let main = phase == "main"
        let sets = main ? 3 : 2
        let names = homeNames(equipment)
        let warmup = "Five minutes of pain-free joint preparation, then one easy practice set."
        let row = names["row"] ?? "Band Row"
        let fullBody = [
            SessionSpec(
                name: "Home Full Body A", type: "upper", minutes: main ? 44 : 30, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: names["squat"] ?? "", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2),
                    ExerciseSpec(name: names["push"] ?? "", sets: sets, repMin: 8, repMax: 15, rest: 75, increment: 2),
                    ExerciseSpec(name: row, sets: sets, repMin: 8, repMax: 15, perSide: row.contains("One-Arm"), rest: 75, increment: 2),
                    ExerciseSpec(name: "Dead Bug", repMin: 8, repMax: 12, perSide: true, rest: 30),
                    ExerciseSpec(name: names["carry"] ?? "", sets: 3, repMin: 30, repMax: 45, unit: "seconds", perSide: true, rest: 45, increment: 2),
                ]
            ),
            SessionSpec(
                name: "Home Full Body B", type: "legs_b", minutes: main ? 46 : 32, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: names["hinge"] ?? "", sets: sets, repMin: 8, repMax: 12, rest: 90, increment: 2),
                    ExerciseSpec(name: names["press"] ?? "", sets: sets, repMin: 8, repMax: 12, rest: 75, increment: 2),
                    ExerciseSpec(name: names["pull"] ?? "", sets: sets, repMin: 6, repMax: 12, rest: 90, increment: 1),
                    ExerciseSpec(name: "Supported Reverse Lunge", repMin: 8, repMax: 10, perSide: true, rest: 75),
                    ExerciseSpec(name: "Side Plank", repMin: 20, repMax: 35, unit: "seconds", perSide: true, rest: 30),
                ]
            ),
            SessionSpec(
                name: "Home Full Body C", type: "upper", minutes: main ? 44 : 30, warmup: warmup,
                exercises: [
                    ExerciseSpec(name: "Step-Up", sets: sets, repMin: 8, repMax: 12, perSide: true, rest: 75, increment: 2),
                    ExerciseSpec(name: names["push"] ?? "", sets: sets, repMin: 8, repMax: 15, rest: 75, increment: 2),
                    ExerciseSpec(name: row, sets: sets, repMin: 8, repMax: 15, perSide: row.contains("One-Arm"), rest: 75, increment: 2),
                    ExerciseSpec(name: "Hip Thrust", sets: sets, repMin: 10, repMax: 15, rest: 75, increment: 2),
                    ExerciseSpec(name: "Bird-Dog", repMin: 6, repMax: 10, perSide: true, rest: 30),
                ]
            ),
        ]
        if count < 4 { return Array(fullBody.prefix(count)) }
        return [
            SessionSpec(name: "Home Upper A", type: "upper", minutes: fullBody[0].minutes, warmup: warmup,
                        exercises: Array(fullBody[0].exercises.dropFirst())),
            SessionSpec(name: "Home Lower A", type: "legs_a", minutes: fullBody[0].minutes, warmup: warmup,
                        exercises: [fullBody[0].exercises[0], fullBody[1].exercises[0], fullBody[1].exercises[3], fullBody[0].exercises[3]]),
            SessionSpec(name: "Home Upper B", type: "upper", minutes: fullBody[2].minutes, warmup: warmup,
                        exercises: [fullBody[2].exercises[1], fullBody[2].exercises[2], fullBody[1].exercises[1], fullBody[2].exercises[4]]),
            SessionSpec(name: "Home Lower B", type: "legs_b", minutes: fullBody[1].minutes, warmup: warmup,
                        exercises: [fullBody[2].exercises[0], fullBody[2].exercises[3], fullBody[1].exercises[0], fullBody[1].exercises[4]]),
        ]
    }

    private static func weekdays(for count: Int) -> [Int] {
        if count == 2 { return [1, 4] }
        if count == 3 { return [1, 3, 5] }
        return [1, 2, 4, 6]
    }

    // MARK: - Generation

    struct GeneratedPlan: Sendable {
        let programs: [Program]
        let programDays: [ProgramDay]
        let exercises: [Exercise]
        let induction: [String: JSONValue]
    }

    static func generate(
        userID: UUID,
        input: Input,
        existingPrograms: [Program] = [],
        completedAt: String = ISO8601DateFormatter().string(from: .now)
    ) -> GeneratedPlan {
        let assessment = assess(input)
        let count = assessment.sessionsPerWeek
        let mainStart = APEXDateMath.adding(days: 84, to: input.startDate)
        let venue = input.venue == "gym" ? "Gym" : "Home"

        func program(_ slug: String) -> Program {
            let existing = existingPrograms.first { $0.slug == slug }
            return Program(
                id: existing?.id ?? APEXStableID.inductionUUID(userID: userID, label: "program:\(slug)"),
                userID: userID,
                slug: slug,
                name: slug == "transition" ? "12-Week \(venue) Foundation" : "Personal \(venue) Main Phase",
                description: slug == "transition"
                    ? "Weeks 1-4 restore, weeks 5-8 build, weeks 9-12 progress. A simple schedule built from your answers."
                    : "Your follow-on strength and muscle phase, using the same equipment, recovery limits and weekly rhythm."
            )
        }

        let programs = [program("transition"), program("main")]
        var programDays: [ProgramDay] = []
        var exercises: [Exercise] = []
        var dayIDs: [String: [String]] = ["transition": [], "main": []]

        for slug in ["transition", "main"] {
            guard let programme = programs.first(where: { $0.slug == slug }) else { continue }
            let sessions = assessment.caution == "clearance"
                ? clearanceSessions()
                : (input.venue == "gym"
                    ? gymSessions(phase: slug, count: count)
                    : homeSessions(phase: slug, count: count, equipment: input.equipment))
            let days = weekdays(for: count)

            for (sessionIndex, spec) in sessions.enumerated() {
                let weekday = days[min(sessionIndex, days.count - 1)]
                let dayID = APEXStableID.inductionUUID(userID: userID, label: "\(slug):day:\(weekday)")
                dayIDs[slug]?.append(dayID.uuidString.lowercased())
                programDays.append(
                    ProgramDay(
                        id: dayID,
                        userID: userID,
                        programID: programme.id,
                        weekday: weekday,
                        name: spec.name,
                        dayType: spec.type,
                        estimatedMinutes: spec.minutes,
                        warmupNote: assessment.caution == "cautious"
                            ? "\(spec.warmup) Start with 3-4 reps in reserve and keep every movement pain-free."
                            : spec.warmup,
                        sortOrder: sessionIndex
                    )
                )

                func add(_ spec: ExerciseSpec, index: Int, lite: Bool) {
                    exercises.append(
                        Exercise(
                            id: APEXStableID.inductionUUID(
                                userID: userID,
                                label: "\(slug):day:\(weekday):\(lite ? "lite" : "full"):\(index)"
                            ),
                            userID: userID,
                            programDayID: dayID,
                            name: spec.name,
                            sets: max(1, spec.sets - (lite ? 1 : 0)),
                            repMin: spec.repMin,
                            repMax: spec.repMax,
                            repUnit: spec.unit,
                            perSide: spec.perSide,
                            restSeconds: spec.rest,
                            tempoUp: 1,
                            tempoDown: assessment.caution == "standard" ? 2 : 3,
                            tempoPause: 0,
                            tempoNote: "",
                            notes: spec.notes ?? (assessment.caution == "cautious"
                                ? "Pain-free range. Stop with at least 3 reps in reserve."
                                : "Progress only after every rep is controlled."),
                            incrementKG: spec.increment,
                            isLite: lite,
                            optional: spec.optional,
                            sortOrder: index
                        )
                    )
                }

                for (index, exercise) in spec.exercises.enumerated() { add(exercise, index: index, lite: false) }
                for (index, exercise) in spec.exercises.prefix(3).enumerated() { add(exercise, index: index, lite: true) }
            }
        }

        let induction: [String: JSONValue] = [
            "version": .number(1),
            "completed_at": .string(completedAt),
            "start_date": .string(input.startDate),
            "main_start_date": .string(mainStart),
            "transition_weeks": .number(12),
            "inactivity": .string(input.inactivity),
            "venue": .string(input.venue),
            "equipment": .array(input.equipment.map { .string($0) }),
            "pain_areas": .array(input.painAreas.map { .string($0) }),
            "recent_operation": .bool(input.recentOperation),
            "chronic_lower_back_pain": .bool(input.chronicLowerBackPain),
            "sessions_per_week": .number(Double(count)),
            "goal": .string(input.goal),
            "caution": .string(assessment.caution),
            "transition_day_ids": .array((dayIDs["transition"] ?? []).map { .string($0) }),
            "main_day_ids": .array((dayIDs["main"] ?? []).map { .string($0) }),
        ]

        return GeneratedPlan(
            programs: programs,
            programDays: programDays,
            exercises: exercises,
            induction: induction
        )
    }
}
