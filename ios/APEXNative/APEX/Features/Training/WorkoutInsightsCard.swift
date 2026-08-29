import SwiftUI

private enum WorkoutInsightRangeMode: String, CaseIterable, Identifiable {
    case day
    case week
    case year
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .year: "Year"
        case .custom: "Custom"
        }
    }
}

private struct WorkoutInsightMetric: Identifiable {
    let id: String
    let label: String
    let value: String
}

struct WorkoutInsightsCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var mode: WorkoutInsightRangeMode = .week
    @State private var customFrom = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var renderedURL: URL?
    @State private var rendering = false
    @State private var errorMessage: String?

    let anchorDate: String
    var accent: Color = APEXColor.violet

    private var ownerID: UUID? {
        session.profile?.userID ?? session.data.settings?.userID
    }

    private var range: (from: String, to: String) {
        switch mode {
        case .day:
            return (anchorDate, anchorDate)
        case .week:
            return (APEXDateMath.adding(days: -6, to: anchorDate), anchorDate)
        case .year:
            return (movingAnchorByYears(-1), anchorDate)
        case .custom:
            return (min(customFrom.apexDateKey, customTo.apexDateKey), max(customFrom.apexDateKey, customTo.apexDateKey))
        }
    }

    private var summary: WorkoutInsights.Summary {
        guard let ownerID else {
            return WorkoutInsights.summarize(
                ownerID: UUID(), from: range.from, to: range.to,
                sessions: [], logs: [], importedActivities: []
            )
        }
        return WorkoutInsights.summarize(
            ownerID: ownerID,
            from: range.from,
            to: range.to,
            sessions: session.data.workoutSessions,
            logs: session.data.workoutLogs,
            importedActivities: session.data.importedActivities
        )
    }

    private var metrics: [WorkoutInsightMetric] {
        [
            .init(id: "workouts", label: language.text("Workouts"), value: integer(summary.workouts)),
            .init(id: "days", label: language.text("Active days"), value: integer(summary.activeDays)),
            .init(id: "time", label: language.text("Recorded time"), value: duration(summary.durationMinutes)),
            .init(id: "energy", label: language.text("Active energy"), value: optional(summary.activeEnergyKcal, unit: "kcal")),
            .init(id: "reps", label: language.text("Reps"), value: integer(summary.reps)),
            .init(id: "sets", label: language.text("Sets / efforts"), value: integer(summary.sets)),
            .init(id: "volume", label: language.text("Recorded volume"), value: optional(summary.volumeKG, unit: "kg")),
            .init(id: "distance", label: language.text("Distance"), value: optional(summary.distanceKM, unit: "km", digits: 2)),
        ]
    }

    var body: some View {
        GlassCard(radius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("APEX WORKOUT INSIGHTS"))
                            .font(APEXFont.mono(9, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(accent)
                        Text(language.text("Workout insights"))
                            .font(APEXFont.display(23))
                        Text(localizedRange(summary.from, summary.to))
                            .font(APEXFont.body(11, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    if let renderedURL {
                        ShareLink(item: renderedURL) {
                            Label(language.shortText("Share PNG"), systemImage: "square.and.arrow.up")
                                .font(APEXFont.body(11, weight: .bold))
                                .frame(minHeight: 42)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .accessibilityIdentifier("workout-insights-share")
                    } else {
                        Button {
                            renderPNG()
                        } label: {
                            if rendering {
                                ProgressView().tint(.white)
                            } else {
                                Label(language.shortText("Export PNG"), systemImage: "photo.on.rectangle.angled")
                                    .font(APEXFont.body(11, weight: .bold))
                            }
                        }
                        .frame(minHeight: 42)
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .disabled(rendering)
                        .accessibilityIdentifier("workout-insights-export")
                    }
                }

                HStack(spacing: 4) {
                    ForEach(WorkoutInsightRangeMode.allCases) { option in
                        rangeButton(option)
                    }
                }
                .padding(4)
                .background(APEXColor.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .contain)

                if mode == .custom {
                    HStack(spacing: 10) {
                        customDatePicker("From", selection: $customFrom, range: Date.distantPast...customTo)
                        customDatePicker("To", selection: $customTo, range: customFrom...Date.now)
                    }
                }

                if let years = summary.anniversaryYears {
                    Text("\(years) \(language.text(years == 1 ? "YEAR ANNIVERSARY" : "YEARS ANNIVERSARY"))")
                        .font(APEXFont.mono(11, weight: .bold))
                        .tracking(1.1)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(.white)
                        .background(accent.gradient, in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityIdentifier("workout-insights-anniversary")
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.label.uppercased(with: language.language.locale))
                                .font(APEXFont.mono(8, weight: .bold))
                                .tracking(0.7)
                                .foregroundStyle(APEXColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(metric.value)
                                .font(APEXFont.display(18))
                                .foregroundStyle(APEXColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .padding(12)
                        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 17))
                    }
                }

                Text(language.text("Only recorded workout facts. Linked wearable energy is counted once."))
                    .font(APEXFont.body(10, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage {
                    Text(errorMessage)
                        .font(APEXFont.body(11, weight: .semibold))
                        .foregroundStyle(APEXColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("workout-insights-card")
        .onAppear(perform: useOldestEvidenceForCustomRange)
        .onChange(of: customFrom) { _, _ in renderedURL = nil }
        .onChange(of: customTo) { _, _ in renderedURL = nil }
    }

    private func rangeButton(_ option: WorkoutInsightRangeMode) -> some View {
        let isSelected = mode == option
        let foreground = isSelected ? Color.white : APEXColor.secondaryInk
        return Button {
            mode = option
            renderedURL = nil
        } label: {
            Text(language.shortText(option.title))
                .font(APEXFont.body(10, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(foreground)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(accent.gradient)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier("workout-insights-range-\(option.rawValue)")
    }

    private func customDatePicker(_ title: String, selection: Binding<Date>, range: ClosedRange<Date>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(language.text(title))
                .font(APEXFont.mono(8, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
            DatePicker("", selection: selection, in: range, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.locale, language.language.locale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func movingAnchorByYears(_ years: Int) -> String {
        guard let date = ISO8601DateFormatter.apexDateOnly.date(from: anchorDate),
              let moved = Calendar.current.date(byAdding: .year, value: years, to: date) else { return anchorDate }
        return moved.apexDateKey
    }

    private func useOldestEvidenceForCustomRange() {
        guard let ownerID else { return }
        let dates = session.data.workoutSessions
            .filter { $0.userID == ownerID && $0.completed }
            .map(\.date)
            + session.data.importedActivities
                .filter { $0.userID == ownerID && $0.hiddenAt == nil }
                .map(\.date)
        if let oldest = dates.min(), let date = ISO8601DateFormatter.apexDateOnly.date(from: oldest) {
            customFrom = date
        }
        if let date = ISO8601DateFormatter.apexDateOnly.date(from: anchorDate) { customTo = date }
    }

    private func integer(_ value: Int) -> String {
        value.formatted(.number.locale(language.language.locale))
    }

    private func optional(_ value: Double?, unit: String, digits: Int = 0) -> String {
        guard let value else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)).locale(language.language.locale))) \(unit)"
    }

    private func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        let hourUnit = language.shortText("h")
        let minuteUnit = language.shortText("min")
        if hours == 0 { return "\(integer(remainder)) \(minuteUnit)" }
        if remainder == 0 { return "\(integer(hours)) \(hourUnit)" }
        return "\(integer(hours)) \(hourUnit) \(integer(remainder)) \(minuteUnit)"
    }

    private func localizedRange(_ from: String, _ to: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        guard let start = ISO8601DateFormatter.apexDateOnly.date(from: from),
              let end = ISO8601DateFormatter.apexDateOnly.date(from: to) else { return "\(from) - \(to)" }
        return from == to ? formatter.string(from: start) : "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    @MainActor
    private func renderPNG() {
        rendering = true
        defer { rendering = false }
        do {
            renderedURL = try WorkoutInsightsPoster.render(
                summary: summary,
                athleteName: session.profile?.displayName ?? language.text("APEX athlete"),
                rangeLabel: localizedRange(summary.from, summary.to),
                accent: accent,
                labels: .init(language: language)
            )
            errorMessage = nil
        } catch {
            errorMessage = language.text("The workout card could not be rendered.")
        }
    }
}

private struct WorkoutInsightsPosterLabels {
    let title: String
    let workouts: String
    let activeDays: String
    let time: String
    let energy: String
    let reps: String
    let sets: String
    let volume: String
    let distance: String
    let anniversary: String
    let verified: String
    let hourUnit: String
    let minuteUnit: String

    @MainActor
    init(language: LanguageState) {
        title = language.text("Workout insights")
        workouts = language.text("Workouts")
        activeDays = language.text("Active days")
        time = language.text("Recorded time")
        energy = language.text("Active energy")
        reps = language.text("Reps")
        sets = language.text("Sets / efforts")
        volume = language.text("Recorded volume")
        distance = language.text("Distance")
        anniversary = language.text("Anniversary")
        verified = language.text("Only recorded workout facts. Linked wearable energy is counted once.")
        hourUnit = language.shortText("h")
        minuteUnit = language.shortText("min")
    }
}

private struct WorkoutInsightsArtwork: View {
    let summary: WorkoutInsights.Summary
    let athleteName: String
    let rangeLabel: String
    let accent: Color
    let labels: WorkoutInsightsPosterLabels

    private var values: [(String, String)] {
        [
            (labels.workouts, "\(summary.workouts)"),
            (labels.activeDays, "\(summary.activeDays)"),
            (labels.time, posterDuration(summary.durationMinutes)),
            (labels.energy, summary.activeEnergyKcal.map { "\(Int($0.rounded())) kcal" } ?? "—"),
            (labels.reps, "\(summary.reps)"),
            (labels.sets, "\(summary.sets)"),
            (labels.volume, summary.volumeKG.map { "\(Int($0.rounded())) kg" } ?? "—"),
            (labels.distance, summary.distanceKM.map { String(format: "%.2f km", $0) } ?? "—"),
        ]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.025, green: 0.067, blue: 0.122), Color(red: 0.067, green: 0.094, blue: 0.15), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(accent.opacity(0.42)).frame(width: 280).blur(radius: 70).offset(x: 150, y: -180)
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("APEX").font(.system(size: 10, weight: .black, design: .monospaced)).tracking(3).foregroundStyle(accent)
                        Text(labels.title).font(.system(size: 27, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text(athleteName).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.76))
                        Text(rangeLabel).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.66))
                    }
                    Spacer()
                    if let years = summary.anniversaryYears {
                        VStack(spacing: 2) {
                            Text("\(years) \(years == 1 ? "YEAR" : "YEARS")").font(.system(size: 14, weight: .black, design: .rounded))
                            Text(labels.anniversary.uppercased()).font(.system(size: 6, weight: .black, design: .monospaced)).tracking(0.8)
                        }
                        .foregroundStyle(Color.black.opacity(0.8))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(accent.gradient, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.0.uppercased()).font(.system(size: 6, weight: .black, design: .monospaced)).tracking(0.5).foregroundStyle(.white.opacity(0.6))
                            Text(item.1).font(.system(size: 14, weight: .black, design: .rounded)).foregroundStyle(index < 3 ? accent : .white).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 51, alignment: .leading)
                        .padding(10)
                        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 0.7))
                    }
                }
                Spacer(minLength: 0)
                Text(labels.verified).font(.system(size: 7, weight: .semibold)).foregroundStyle(.white.opacity(0.58)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(26)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
    }

    private func posterDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) \(labels.minuteUnit)" }
        if remainder == 0 { return "\(hours) \(labels.hourUnit)" }
        return "\(hours) \(labels.hourUnit) \(remainder) \(labels.minuteUnit)"
    }
}

private enum WorkoutInsightsPoster {
    @MainActor
    static func render(
        summary: WorkoutInsights.Summary,
        athleteName: String,
        rangeLabel: String,
        accent: Color,
        labels: WorkoutInsightsPosterLabels
    ) throws -> URL {
        let artwork = WorkoutInsightsArtwork(summary: summary, athleteName: athleteName, rangeLabel: rangeLabel, accent: accent, labels: labels)
            .frame(width: 360, height: 450)
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let url = FileManager.default.temporaryDirectory.appending(path: "apex-workout-insights-\(summary.from)-\(summary.to).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}
