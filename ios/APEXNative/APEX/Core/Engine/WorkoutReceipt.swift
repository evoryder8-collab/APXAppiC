import Foundation

/*
 * The numbers behind the end-of-workout receipt, matching the web's
 * WorkoutStatsSheet.
 *
 * Loaded volume is the honest measure of what a session cost: every working
 * set's weight multiplied by its reps. A skipped set contributes nothing, and
 * Focus T25 is excluded because a bodyweight conditioning episode has no load
 * to report and would otherwise read as a session of zero effort.
 */
enum WorkoutReceipt {
    struct Summary: Hashable, Sendable {
        /// Kilograms moved: the sum of weight times reps across working sets.
        let loadedVolumeKG: Double
        let workingSets: Int
        let movements: Int

        var hasLoad: Bool { loadedVolumeKG > 0 }
    }

    static func summarize(_ logs: [WorkoutLog]) -> Summary {
        let strength = logs.filter { !FocusT25.isFocusName($0.exerciseName) }
        let volume = strength.reduce(0.0) { total, log in
            guard !log.skipped else { return total }
            return total + (log.weightKG ?? 0) * Double(log.reps ?? 0)
        }
        /* Movements count every exercise performed, conditioning included,
           because the session did contain them even without a load. */
        var names: [String] = []
        for log in logs where !names.contains(log.exerciseName) { names.append(log.exerciseName) }
        return Summary(
            loadedVolumeKG: volume,
            workingSets: strength.filter { !$0.skipped }.count,
            movements: names.count
        )
    }

    /// One sentence per movement, in the language the app is running in.
    static func insightText(
        _ insight: StrengthProgress.SessionInsight,
        language: AppLanguage
    ) -> String {
        guard insight.reference != nil,
              let loadDelta = insight.loadDelta,
              let days = insight.daysCompared else {
            return firstBaseline(language)
        }
        let delta = formatted(abs(loadDelta))
        let estimated = String(format: "%.1f", abs(insight.estimated1RMDelta ?? 0))
        switch language {
        case .romanian:
            if loadDelta > 0 {
                return "Ai crescut greutatea de lucru pentru \(insight.name) cu \(delta) kg în \(days) zile. Forța estimată a urcat cu \(estimated) kg."
            }
            if loadDelta < 0 {
                return "\(insight.name) a fost cu \(delta) kg sub reperul de acum \(days) zile. Contextul de deload, repetările și RIR-ul contează înainte de următoarea creștere."
            }
            return "\(insight.name) a rămas stabil timp de \(days) zile. Următoarea creștere se câștigă prin repetări curate și RIR controlat."
        case .thai:
            if loadDelta > 0 {
                return "น้ำหนักฝึก \(insight.name) เพิ่มขึ้น \(delta) กก. ใน \(days) วัน ความแข็งแรงโดยประมาณเพิ่ม \(estimated) กก."
            }
            if loadDelta < 0 {
                return "\(insight.name) ต่ำกว่าค่าอ้างอิงเมื่อ \(days) วันก่อน \(delta) กก. ควรดูช่วงลดโหลด จำนวนครั้ง และ RIR ก่อนเพิ่มครั้งถัดไป"
            }
            return "\(insight.name) คงที่ตลอด \(days) วัน เพิ่มระดับเมื่อทำซ้ำได้คมชัดและควบคุม RIR ได้"
        case .english:
            if loadDelta > 0 {
                return "You increased \(insight.name) by \(delta) kg across \(days) days. Estimated strength rose \(estimated) kg."
            }
            if loadDelta < 0 {
                return "\(insight.name) was \(delta) kg below the \(days)-day reference. Deload context, reps and RIR matter before the next increase."
            }
            return "\(insight.name) held steady across \(days) days. The next increase is earned through clean reps and controlled RIR."
        }
    }

    private static func firstBaseline(_ language: AppLanguage) -> String {
        switch language {
        case .romanian: "Primul reper curat a fost înregistrat. Acesta devine comparația pentru următoarea sesiune."
        case .thai: "บันทึกค่าฐานครั้งแรกแล้ว ค่านี้จะใช้เทียบกับการฝึกครั้งถัดไป"
        case .english: "First clean baseline recorded. This becomes the comparison point for your next session."
        }
    }

    /// Whole kilograms read better than 2.5000000001.
    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Grouped in the order the sets were actually performed.
    static func grouped(_ logs: [WorkoutLog]) -> [(name: String, logs: [WorkoutLog])] {
        var order: [String] = []
        var byName: [String: [WorkoutLog]] = [:]
        for log in logs {
            if byName[log.exerciseName] == nil { order.append(log.exerciseName) }
            byName[log.exerciseName, default: []].append(log)
        }
        return order.compactMap { name in
            byName[name].map { (name: name, logs: $0) }
        }
    }
}
