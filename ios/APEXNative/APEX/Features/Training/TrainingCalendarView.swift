import SwiftUI

/*
 * The month at a glance.
 *
 * A port of src/components/Calendar.tsx. Every planned day carries its session
 * type as a colour-coded tile rather than a blank square: completed days fill
 * with the type gradient, deloads take the ice wash, an approaching event ramps
 * amber to crimson and the event itself burns solid. Tap opens the day, a long
 * press toggles a deload the way it does on the web.
 */
struct DayTypeMeta: Sendable {
    let code: String
    let label: String
    let bright: Color
    let deep: Color
    let gradient: [Color]

    static let all: [String: DayTypeMeta] = [
        "legs_a": DayTypeMeta(code: "LA", label: "Legs A", bright: Color(hex: 0x10b981), deep: Color(hex: 0x047857), gradient: [Color(hex: 0x059669), Color(hex: 0x34d399)]),
        "legs_b": DayTypeMeta(code: "LB", label: "Legs B", bright: Color(hex: 0x10b981), deep: Color(hex: 0x047857), gradient: [Color(hex: 0x059669), Color(hex: 0x34d399)]),
        "push": DayTypeMeta(code: "PU", label: "Push", bright: Color(hex: 0xf59e0b), deep: Color(hex: 0xb45309), gradient: [Color(hex: 0xf59e0b), Color(hex: 0xfbbf24)]),
        "pull": DayTypeMeta(code: "PL", label: "Pull", bright: Color(hex: 0x8b5cf6), deep: Color(hex: 0x6d28d9), gradient: [Color(hex: 0x7c3aed), Color(hex: 0xa78bfa)]),
        "upper": DayTypeMeta(code: "UP", label: "Upper", bright: Color(hex: 0x14b8a6), deep: Color(hex: 0x0f766e), gradient: [Color(hex: 0x0d9488), Color(hex: 0x2dd4bf)]),
        "mobility": DayTypeMeta(code: "MO", label: "Mobility", bright: Color(hex: 0x38bdf8), deep: Color(hex: 0x0369a1), gradient: [Color(hex: 0x0ea5e9), Color(hex: 0x7dd3fc)]),
        "fix": DayTypeMeta(code: "FX", label: "Fix", bright: Color(hex: 0x38bdf8), deep: Color(hex: 0x0369a1), gradient: [Color(hex: 0x0ea5e9), Color(hex: 0x7dd3fc)]),
        "t25": DayTypeMeta(code: "T25", label: "Cardio", bright: Color(hex: 0xf43f5e), deep: Color(hex: 0xbe123c), gradient: [Color(hex: 0xe11d48), Color(hex: 0xfb7185)]),
        "custom": DayTypeMeta(code: "MY", label: "Custom", bright: Color(hex: 0xa855f7), deep: Color(hex: 0x7e22ce), gradient: [Color(hex: 0x7c3aed), Color(hex: 0x22d3ee)]),
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

struct TrainingCalendarView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared

    let slug: String
    let accent: Color
    var onSelectDay: (String) -> Void

    @State private var month: Date = Date()

    private static let weekdayCodes = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    /// Six weeks, starting on the Monday on or before the first of the month.
    private var cells: [String] {
        let calendar = APEXDateMath.calendar
        let parts = calendar.dateComponents([.year, .month], from: month)
        guard let first = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1, hour: 12))
        else { return [] }
        let firstKey = APEXDateMath.key(from: first)
        let lead = APEXDateMath.isoWeekday(firstKey) - 1
        return (0..<42).map { APEXDateMath.adding(days: $0 - lead, to: firstKey) }
    }

    private var userID: UUID? { session.data.profile?.userID }

    private var resolvedDays: [TrainingCalendarDay] {
        cells.map { key in
            TrainingCalendarDay.resolve(
                session.data,
                slug: slug,
                date: key,
                userID: userID
            )
        }
    }

    private var waterDates: Set<String> {
        Set(session.data.dailyLogs.filter { row in
            (userID == nil || row.userID == userID) && row.waterL >= 2.5
        }.map(\.date))
    }
    private var importedDates: Set<String> {
        Set(session.data.importedActivities.filter { row in
            userID == nil || row.userID == userID
        }.map(\.date))
    }
    private var events: [EventRecord] {
        session.data.events.filter { event in
            userID == nil || event.userID == userID
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: month)
    }

    private func typeLegend(for days: [TrainingCalendarDay]) -> [DayTypeMeta] {
        var seen: [String: DayTypeMeta] = [:]
        for type in days.compactMap(\.dayType) {
            if let meta = DayTypeMeta.all[type], seen[meta.code] == nil { seen[meta.code] = meta }
        }
        return seen.values.sorted { $0.code < $1.code }
    }

    private func stateLegend(for days: [TrainingCalendarDay]) -> [TrainingCalendarDay.State] {
        let present = Set(days.filter { isInDisplayedMonth($0.date) }.map(\.state))
        return TrainingCalendarDay.State.allCases.filter(present.contains)
    }

    var body: some View {
        let days = resolvedDays
        return VStack(spacing: 12) {
            HStack {
                Button {
                    shiftMonth(-1)
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calendar-previous-month")
                Spacer()
                Text(monthTitle.uppercased(with: language.language.locale))
                    .font(APEXFont.mono(11, weight: .bold))
                    .tracking(1.6)
                Spacer()
                Button {
                    shiftMonth(1)
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("calendar-next-month")
            }
            .foregroundStyle(APEXColor.secondaryInk)

            HStack(spacing: 5) {
                ForEach(Self.weekdayCodes, id: \.self) { code in
                    Text(language.text(code))
                        .font(APEXFont.mono(9, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(days) { day in
                    tile(for: day)
                }
            }

            let types = typeLegend(for: days)
            let states = stateLegend(for: days)
            if !types.isEmpty || !states.isEmpty {
                FlowLegend(items: types, states: states, language: language)
            }
        }
        .accessibilityIdentifier("training-calendar")
    }

    private func shiftMonth(_ delta: Int) {
        if let moved = APEXDateMath.calendar.date(byAdding: .month, value: delta, to: month) {
            month = moved
        }
    }

    @ViewBuilder
    private func tile(for day: TrainingCalendarDay) -> some View {
        let key = day.date
        let inMonth = isInDisplayedMonth(key)
        let ramp = TrainingPlanEngine.approachRamp(for: key, events: events)
        let during = TrainingPlanEngine.eventContext(for: key, events: events)?.isDuring ?? false
        let isToday = key == Date().apexDateKey
        let meta = day.dayType.flatMap { DayTypeMeta.all[$0] }
        let style = tileStyle(
            inMonth: inMonth, meta: meta, day: day, ramp: ramp, during: during
        )
        let darkState = day.state == .completed || day.state == .manuallyLogged || day.state == .custom

        Button {
            if inMonth { onSelectDay(key) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(style.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(style.border, lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(isToday ? (darkState ? .white.opacity(0.85) : accent) : .clear, lineWidth: 2)
                    )

                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 2) {
                        Text(dayNumber(key))
                            .font(APEXFont.mono(10, weight: .bold))
                        Spacer(minLength: 0)
                        if inMonth {
                            Image(systemName: day.state.symbolName)
                                .font(.system(size: 7, weight: .black))
                        }
                        if inMonth, day.isDeload, day.state != .deload {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 6, weight: .black))
                        }
                        if waterDates.contains(key) {
                            Circle()
                                .fill(darkState ? .white.opacity(0.8) : Color(hex: 0x38bdf8))
                                .frame(width: 4, height: 4)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                    if inMonth {
                        Text(day.state.shortLabel)
                            .font(APEXFont.mono(7, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(style.code)
                    }
                }
                .foregroundStyle(style.ink)
                .padding(4)

                if inMonth, importedDates.contains(key), day.state != .completed {
                    Circle()
                        .fill(Color(hex: 0xf59e0b))
                        .frame(width: 4, height: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(5)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(!inMonth)
        .accessibilityLabel(accessibleLabel(for: day))
        .accessibilityIdentifier("calendar-day-\(key)")
        .contextMenu {
            if inMonth {
                Button(isDeloadMarked(key) ? language.text("Clear deload") : language.text("Mark deload")) {
                    Task { await session.toggleDeload(on: APEXDateMath.date(from: key) ?? .now) }
                }
            }
        }
    }

    private struct TileStyle {
        var background: AnyShapeStyle
        var border: Color
        var ink: Color
        var code: Color
    }

    /* Backgrounds are secondary to the icon and status code, so none of these
       states relies on color alone. Event context sits over prescriptions;
       recorded facts sit over event context. */
    private func tileStyle(
        inMonth: Bool,
        meta: DayTypeMeta?,
        day: TrainingCalendarDay,
        ramp: Double?,
        during: Bool
    ) -> TileStyle {
        var style = TileStyle(
            background: AnyShapeStyle(Color.white.opacity(0.5)),
            border: APEXColor.ink.opacity(0.06),
            ink: inMonth ? APEXColor.ink : APEXColor.ink.opacity(0.25),
            code: meta?.deep ?? APEXColor.secondaryInk
        )
        guard inMonth else { return style }

        if let meta {
            style.background = AnyShapeStyle(
                LinearGradient(
                    colors: [meta.bright.opacity(0.13), meta.bright.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            style.border = meta.bright.opacity(0.22)
        }
        switch day.state {
        case .scheduled:
            break
        case .rest:
            style.background = AnyShapeStyle(Color(hex: 0xf1f5f9))
            style.border = Color(hex: 0x94a3b8).opacity(0.35)
            style.ink = Color(hex: 0x475569)
            style.code = style.ink
        case .noPrescription:
            style.background = AnyShapeStyle(Color.white.opacity(0.35))
            style.border = APEXColor.ink.opacity(0.1)
            style.ink = APEXColor.secondaryInk
            style.code = APEXColor.secondaryInk
        case .missed:
            style.background = AnyShapeStyle(Color(hex: 0xfef2f2))
            style.border = Color(hex: 0xef4444).opacity(0.35)
            style.ink = Color(hex: 0x991b1b)
            style.code = style.ink
        case .deload:
            style.background = AnyShapeStyle(
                LinearGradient(colors: [Color(hex: 0x7dd3fc), Color(hex: 0xe0f2fe)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            style.border = Color(hex: 0x38bdf8).opacity(0.4)
            style.ink = Color(hex: 0x075985)
            style.code = Color(hex: 0x075985)
        case .partiallyCompleted, .completed, .manuallyLogged, .custom:
            break
        }
        if let ramp, !during {
            style.background = AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: 0xf59e0b).opacity(0.2 + ramp * 0.55),
                        Color(hex: 0xdc2626).opacity(0.12 + ramp * 0.5),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            style.border = Color(hex: 0xdc2626).opacity(0.25)
            style.ink = ramp > 0.6 ? Color(hex: 0x7f1d1d) : Color(hex: 0x92400e)
            style.code = style.ink
        }
        if during {
            style.background = AnyShapeStyle(
                LinearGradient(colors: [Color(hex: 0xf59e0b), Color(hex: 0xdc2626)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            style.border = .clear
            style.ink = .white
            style.code = .white.opacity(0.9)
        }
        if day.state == .partiallyCompleted {
            style.background = AnyShapeStyle(
                LinearGradient(colors: [Color(hex: 0xfde68a), Color(hex: 0xfef3c7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            style.border = Color(hex: 0xf59e0b).opacity(0.45)
            style.ink = Color(hex: 0x92400e)
            style.code = style.ink
        }
        if day.state == .manuallyLogged {
            style.background = AnyShapeStyle(
                LinearGradient(colors: [Color(hex: 0x14b8a6), Color(hex: 0x0f766e)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            style.border = .clear
            style.ink = .white
            style.code = .white.opacity(0.95)
        }
        if day.state == .custom {
            style.background = AnyShapeStyle(
                LinearGradient(colors: [Color(hex: 0x8b5cf6), Color(hex: 0x6d28d9)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            style.border = .clear
            style.ink = .white
            style.code = .white.opacity(0.95)
        }
        if day.state == .completed {
            let gradient = day.dayType.flatMap { DayTypeMeta.all[$0] }?.gradient ?? [accent, accent]
            style.background = AnyShapeStyle(
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            style.border = .clear
            style.ink = .white
            style.code = .white.opacity(0.95)
        }
        return style
    }

    private func isInDisplayedMonth(_ key: String) -> Bool {
        APEXDateMath.calendar.isDate(
            APEXDateMath.date(from: key) ?? .distantPast,
            equalTo: month,
            toGranularity: .month
        )
    }

    private func isDeloadMarked(_ key: String) -> Bool {
        (session.data.deloadMarks ?? []).contains { mark in
            mark.date == key && (userID == nil || mark.userID == userID)
        }
    }

    private func dayNumber(_ key: String) -> String {
        String(Int(key.split(separator: "-").last.map(String.init) ?? "0") ?? 0)
    }

    private func accessibleDate(_ key: String) -> String {
        guard let date = APEXDateMath.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = language.language.locale
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func accessibleLabel(for day: TrainingCalendarDay) -> String {
        var parts = [
            accessibleDate(day.date),
            language.text(day.title),
            language.text(day.accessibilityStatus),
        ]
        if waterDates.contains(day.date) { parts.append(language.text("Water 2.5L+")) }
        if importedDates.contains(day.date) { parts.append(language.text("Imported activity")) }
        return parts.joined(separator: ", ")
    }
}

private struct FlowLegend: View {
    let items: [DayTypeMeta]
    let states: [TrainingCalendarDay.State]
    let language: LanguageState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            ForEach(items, id: \.code) { meta in
                chip(colors: meta.gradient, text: "\(meta.code) \(language.text(meta.label))")
            }
            ForEach(states, id: \.self) { state in
                Label(language.text(state.label), systemImage: state.symbolName)
                    .font(APEXFont.mono(9, weight: .bold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            chip(colors: [Color(hex: 0x38bdf8), Color(hex: 0x38bdf8)], text: language.text("Water 2.5L+"))
        }
    }

    private func chip(colors: [Color], text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 9, height: 9)
            Text(text)
                .font(APEXFont.mono(9, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
        }
    }
}
