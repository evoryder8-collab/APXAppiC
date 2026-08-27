import Foundation
import SwiftUI
import UIKit

enum PortalUIMode: String, CaseIterable, Identifiable, Sendable {
    case simple
    case advanced

    var id: String { rawValue }

    static func current(from settings: UserSettings?) -> PortalUIMode {
        settings?.addons["uiMode"]?.stringValue == PortalUIMode.simple.rawValue ? .simple : .advanced
    }
}

enum SimpleHomeLogic {
    static func guidedProgramSlug(
        persona: Persona?,
        mainIsUsable: Bool,
        transitionIsUsable: Bool
    ) -> String {
        let bespokeMain = persona == .constantine || persona == .june
        if bespokeMain && mainIsUsable { return "main" }
        if transitionIsUsable { return "transition" }
        if mainIsUsable { return "main" }
        return bespokeMain ? "main" : "transition"
    }

    static func completion(completed: Int, total: Int) -> Int {
        guard total > 0 else { return 100 }
        return min(100, max(0, Int((Double(completed) / Double(total) * 100).rounded())))
    }

    static func nextCandidateIndex(times: [Int], nowMinutes: Int) -> Int? {
        let ordered = times.enumerated().sorted { left, right in
            if left.element == right.element { return left.offset < right.offset }
            return left.element < right.element
        }
        return ordered.last(where: { $0.element <= nowMinutes })?.offset ?? ordered.first?.offset
    }

    static func completedSessionID(
        sessions: [WorkoutSession],
        date: String,
        programDayID: UUID
    ) -> UUID? {
        sessions
            .filter {
                $0.completed
                    && $0.date == date
                    && $0.programDayID == programDayID
            }
            .max { left, right in
                let leftTime = left.completedAt ?? left.startedAt ?? ""
                let rightTime = right.completedAt ?? right.startedAt ?? ""
                if leftTime == rightTime {
                    return left.id.uuidString.lowercased() < right.id.uuidString.lowercased()
                }
                return leftTime < rightTime
            }?
            .id
    }
}

enum MorningCheckLogic {
    struct Entry: Equatable {
        let sleepScore: Double?
        let recoveryScore: Double?
        let weightKG: Double?
    }

    static func entry(
        sleep: String,
        recovery: String,
        weight: String,
        source: String,
        weightUnit: WeightUnit
    ) -> Entry? {
        let sleepText = normalized(sleep)
        let recoveryText = normalized(recovery)
        let weightText = normalized(weight)
        let hasScoreInput = !sleepText.isEmpty || (source == "other" && !recoveryText.isEmpty)
        let hasWeightInput = !weightText.isEmpty

        var sleepScore: Double?
        var recoveryScore: Double?
        if hasScoreInput {
            guard let parsedSleep = score(sleepText) else { return nil }
            sleepScore = parsedSleep
            if source == "other" {
                guard let parsedRecovery = score(recoveryText) else { return nil }
                recoveryScore = parsedRecovery
            }
        }

        var weightKG: Double?
        if hasWeightInput {
            guard let value = Double(weightText), value.isFinite else { return nil }
            let kilograms = weightUnit.kilograms(fromValue: value)
            guard (25...350).contains(kilograms) else { return nil }
            weightKG = kilograms
        }

        guard sleepScore != nil || weightKG != nil else { return nil }
        return Entry(sleepScore: sleepScore, recoveryScore: recoveryScore, weightKG: weightKG)
    }

    static func applyingWeight(
        _ weightKG: Double,
        to existing: DailyLog?,
        userID: UUID,
        date: String,
        activityMode: String
    ) -> DailyLog {
        if var existing {
            existing.weightKG = weightKG
            return existing
        }
        return DailyLog(
            id: APEXStableID.scopedUUID(namespace: "daily-log", date: date, userID: userID),
            userID: userID,
            date: date,
            waterL: 0,
            activityMode: activityMode,
            weightKG: weightKG
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
    }

    private static func score(_ value: String) -> Double? {
        guard let parsed = Double(value), parsed.isFinite, (0...100).contains(parsed) else { return nil }
        return parsed
    }
}

struct PortalModeSwitcher: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared

    var body: some View {
        HStack(spacing: 3) {
            ForEach(PortalUIMode.allCases) { mode in
                Button {
                    guard session.interfaceMode != mode else { return }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    session.setInterfaceMode(mode)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode == .simple ? "sparkle" : "slider.horizontal.3")
                            .font(.system(size: 9, weight: .bold))
                        Text(language.shortText(mode == .simple ? "Simple" : "Advanced").uppercased(with: language.language.locale))
                            .font(APEXFont.mono(9))
                            .tracking(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(session.interfaceMode == mode ? .white : APEXColor.secondaryInk)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .frame(minHeight: 38)
                    .background(
                        session.interfaceMode == mode ? APEXColor.ink : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(session.interfaceMode == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.9)))
        .shadow(color: .black.opacity(0.05), radius: 9, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.text("Interface mode"))
    }
}
