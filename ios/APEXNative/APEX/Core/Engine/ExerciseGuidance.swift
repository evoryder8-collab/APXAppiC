import Foundation

/*
 * Port of src/lib/exerciseGuidance.ts.
 *
 * One execution cue per exercise, matched by name. The list is ordered and
 * first match wins, so a specific movement must always be tested before the
 * generic one it contains: "leg curl" contains "curl", "bulgarian split
 * squat" contains "squat".
 */
enum ExerciseGuidance {
    struct Cue: Sendable {
        let pattern: String
        let en: String

        func text(_ language: AppLanguage) -> String {
            guard language != .english,
                  let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
                  let languageBundle = Bundle(path: path)
            else { return en }

            return languageBundle.localizedString(forKey: en, value: en, table: nil)
        }
    }

    static let cues: [Cue] = [
        Cue(
            pattern: "focus\\s*t25",
            en: "Follow the episode on screen. Choose the modifier whenever form or breathing starts to break down. A completed modifier version still counts as a completed session.",
        ),
        Cue(
            pattern: "bulgarian|split[\\s-]?squat|fandare.*bulgar",
            en: "Set the rear foot comfortably, keep the front foot fully planted and lower under control. Drive through the whole front foot without letting the knee collapse inward.",
        ),
        Cue(
            pattern: "romanian deadlift|\\brdl\\b|îndreptări românești|ยกเดดลิฟต์โรมาเนีย",
            en: "Keep the weight close, soften the knees and push the hips back until the hamstrings are loaded. Keep the spine long and finish by standing tall, not by leaning back.",
        ),
        Cue(
            pattern: "hip thrust|glute bridge|frog pump|împins.*șold|สะพานก้น|ฮิปทรัสต์",
            en: "Brace the ribs down, drive through the feet and finish with the glutes. Stop when the hips are fully extended without arching the lower back.",
        ),
        Cue(
            pattern: "lunge|fandare|ก้าวย่อ",
            en: "Step to a stable stance, lower with control and keep the working knee tracking over the toes. Push the floor away to return.",
        ),
        Cue(
            pattern: "calf|gambe|น่อง",
            en: "Use the full comfortable ankle range. Pause briefly at the top and lower slowly without bouncing.",
        ),
        Cue(
            pattern: "pull[\\s-]?up|chin[\\s-]?up|dead hang|tracți|โหน|ดึงข้อ",
            en: "Start from a controlled shoulder position, keep the ribs stacked and pull without swinging. Stop before grip or shoulder position becomes unsafe.",
        ),
        Cue(
            pattern: "row|ramat|ดึง.*พาย|แมชชีนโรว์",
            en: "Brace the torso, lead with the elbows and pull toward the lower ribs. Let the shoulder blades move naturally without shrugging.",
        ),
        Cue(
            pattern: "push[\\s-]?up|press|împins|flotări|วิดพื้น|เพรส",
            en: "Keep the body braced, lower through a pain-free range and press while keeping the shoulders away from the ears. Maintain steady wrist and elbow alignment.",
        ),
        Cue(
            pattern: "face pull|band pull|pull-apart|tragere.*band|ยางยืด",
            en: "Keep the ribs quiet and pull with the upper back. Finish with the hands apart and shoulders down rather than forcing extra range.",
        ),
        Cue(
            pattern: "leg curl|flexii femurali|งอขา",
            en: "Keep the hips anchored, curl smoothly and squeeze briefly without lifting the pelvis. Return slowly.",
        ),
        Cue(
            pattern: "curl|flexii|ciocan|ไบเซป|เคิร์ล",
            en: "Keep the upper arm stable and curl without using momentum. Lower under control through the comfortable elbow range.",
        ),
        Cue(
            pattern: "bird dog|side plank|plank|wall slide|mobil|stretch|posture|planș|แพลงก์|ยืด",
            en: "Move only through the range you can control while breathing normally. Keep the trunk quiet and stop if the movement causes sharp pain.",
        ),
        Cue(
            pattern: "squat|genuflex|สควอต",
            en: "Set a stable foot position, brace before descending and keep the knees tracking with the toes. Use the deepest pain-free range you can control.",
        ),
    ]

    static let fallback = Cue(
        pattern: "",
        en: "Use a controlled, pain-free range with stable alignment. Follow the prescribed tempo, stop on sharp pain and leave the planned repetitions in reserve.",
    )

    /// The cue for an exercise, or the general one when nothing matches.
    static func executionCue(_ name: String, language: AppLanguage) -> String {
        let match = cues.first { cue in
            name.range(of: cue.pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return (match ?? fallback).text(language)
    }
}
