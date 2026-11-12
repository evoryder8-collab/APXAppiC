import SwiftUI
import WatchKit

struct WatchHydrationView: View {
    @EnvironmentObject private var hydration: WatchHydrationStore
    @EnvironmentObject private var workout: WatchWorkoutSessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = WatchPage.initial
    @State private var showsCustomAmount = false
    /// Debug previews only: drinks poured by the `APEX_WATCH_PREVIEW_POUR` demo.
    @State private var previewPoured = 0.0

    private let aqua = WatchTint.aqua
    private let violet = WatchTint.violet

    private var previewLiters: Double? {
        #if DEBUG
        ProcessInfo.processInfo.environment["APEX_WATCH_PREVIEW_LITERS"].flatMap(Double.init)
        #else
        nil
        #endif
    }

    private var displayedLiters: Double { previewLiters.map { $0 + previewPoured } ?? hydration.liters }

    private var fillState: WatchHydrationFillState {
        WatchHydrationFillState(liters: displayedLiters, targetLiters: hydration.targetLiters)
    }

    private var animationIsEnabled: Bool {
        WatchHydrationAnimationPolicy.shouldAnimate(
            sceneIsActive: scenePhase == .active,
            luminanceIsReduced: isLuminanceReduced,
            reduceMotion: reduceMotion || hydration.preferences.motionIntensity == .off
        )
    }

    private var showsSupplements: Bool {
        !hydration.supplements.visibleItems.isEmpty && hydration.supplements.snapshot != nil
    }

    var body: some View {
        // One thing per page, turned with the Digital Crown: water, supplements, then history and settings.
        TabView(selection: $page) {
            waterPage.tag(WatchPage.water)
            if showsSupplements {
                WatchSupplementChecklistView(
                    animates: animationIsEnabled && page == .supplements,
                    motionScale: hydration.preferences.motionIntensity.scale
                )
                .tag(WatchPage.supplements)
            }
            morePage.tag(WatchPage.more)
        }
        .tabViewStyle(.verticalPage)
        .background(.black)
        .task {
            if previewLiters == nil {
                await hydration.start()
            }
            #if DEBUG
            // Lets a recording show a drink landing without Apple Health: one glass every few seconds.
            guard ProcessInfo.processInfo.environment["APEX_WATCH_PREVIEW_POUR"] != nil else { return }
            while !Task.isCancelled, displayedLiters < hydration.targetLiters + 0.2 {
                try? await Task.sleep(for: .seconds(3))
                previewPoured += 0.45
            }
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, previewLiters == nil else { return }
            Task { await hydration.refresh(retryComplicationIfStale: true) }
        }
        .sheet(isPresented: $showsCustomAmount) {
            CustomHydrationAmountView()
                .environmentObject(hydration)
        }
        .onChange(of: fillState.progress >= 1) { _, reached in
            // The drink that completes the day gets a second, different tap after the store's own.
            guard reached, scenePhase == .active, hydration.preferences.confirmationHaptics else { return }
            WKInterfaceDevice.current().play(.notification)
        }
        .onChange(of: showsSupplements) { _, shown in
            // The supplements page can vanish under the user when the phone syncs an empty list.
            if !shown, page == .supplements { page = .water }
        }
    }

    // MARK: Water

    private var waterPage: some View {
        // The outer reader keeps the clock's inset; the inner one is the whole screen, corner to corner.
        GeometryReader { safe in
            GeometryReader { screen in
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        WatchVessel(
                            shape: .figure,
                            progress: fillState.progress,
                            bands: HydrationPalette.vesselBands(for: hydration.composition),
                            animates: animationIsEnabled && page == .water,
                            motionScale: hydration.preferences.motionIntensity.scale
                        )
                        .frame(width: screen.size.width * 0.45)
                        .frame(maxHeight: .infinity)

                        readout
                            .padding(.top, safe.safeAreaInsets.top * 0.6)
                            .padding(.trailing, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    notice
                    drinks
                        .padding(.bottom, 10)
                }
                .frame(width: screen.size.width, height: screen.size.height)
            }
            .ignoresSafeArea()
        }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                amount(size: 36)
                amount(size: 30)
                amount(size: 25)
            }
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .snappy, value: displayedLiters)

            Text("\(percent)% of \(hydration.preferences.formattedTarget.joiningUnit)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HydrationProgressGleam(
                progress: fillState.progress,
                composition: hydration.composition,
                animationIsEnabled: animationIsEnabled && page == .water,
                aqua: aqua,
                violet: violet
            )
            .frame(height: 5)
            .padding(.vertical, 2)
            .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: fillState.progress)

            Text(status)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(fillState.progress >= 1 ? aqua : .white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
                .id(status)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hydration")
        .accessibilityValue(
            "\(hydration.preferences.formattedAmount(liters: displayedLiters)) of "
                + "\(hydration.preferences.formattedTarget), "
                + "\(percent) percent, \(status)"
        )
    }

    /// Whole percent that only reads 100 once the goal is really reached, so it never contradicts the line below it.
    private var percent: Int {
        fillState.progress >= 1 ? 100 : min(99, Int((fillState.progress * 100).rounded(.down)))
    }

    /// Store messages and a running workout get the full width under the figure; the column beside it is too narrow.
    @ViewBuilder
    private var notice: some View {
        if let message = hydration.message {
            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(aqua)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 10)
                .transition(.opacity)
        } else if workout.isActive {
            Label("\(workout.activityName) active", systemImage: "figure.strengthtraining.traditional")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(violet)
        }
    }

    /// The day's total leads; its unit stays on the same line in the water colour.
    private func amount(size: CGFloat) -> some View {
        let parts = hydration.preferences.formattedAmount(liters: displayedLiters).split(separator: " ")
        let number = Text(parts.first.map(String.init) ?? "")
            .font(.system(size: size, weight: .bold, design: .rounded))
        let unit = Text("\u{00A0}" + (parts.count > 1 ? String(parts[1]) : ""))
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(aqua)
        return (number + unit)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    private var status: String {
        if fillState.progress >= 1 { return "Goal reached" }
        let remaining = max(0, hydration.targetLiters - displayedLiters)
        let formatted = hydration.preferences.formattedAmount(liters: remaining)
        // A sip short of the goal would otherwise print as nothing left to drink.
        if formatted == hydration.preferences.formattedAmount(liters: 0) { return "Almost there" }
        return "\(formatted.joiningUnit) to go"
    }

    @ViewBuilder
    private var drinks: some View {
        if hydration.isAuthorized || previewLiters != nil {
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(quickPresets) { preset in
                        quickAdd(preset)
                    }
                    Button {
                        showsCustomAmount = true
                    } label: {
                        drinkLabel(icon: "slider.horizontal.3", title: "Other", detail: "mL", tint: .white)
                    }
                    .buttonStyle(WatchGlassButtonStyle(tint: .white, cornerRadius: 16))
                    .accessibilityLabel("Custom amount")
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 8, for: .scrollContent)
        } else {
            Button {
                Task { await hydration.reconnect() }
            } label: {
                Label("Reconnect Apple Health", systemImage: "heart.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(WatchGlassButtonStyle(tint: aqua, cornerRadius: 16))
            .padding(.horizontal, 8)
        }
    }

    private var quickPresets: [WatchQuickPreset] {
        if !hydration.presets.isEmpty {
            return hydration.presets.map(WatchQuickPreset.init)
        }
        return HydrationLedger.defaultPresetTemplates.map(WatchQuickPreset.init)
    }

    private func quickAdd(_ preset: WatchQuickPreset) -> some View {
        let tint = HydrationPalette.color(for: preset.paletteToken)
        return Button {
            Task {
                await hydration.add(
                    milliliters: Double(preset.amountML),
                    kind: preset.kind,
                    paletteToken: preset.paletteToken,
                    iconToken: preset.iconToken
                )
            }
        } label: {
            drinkLabel(
                icon: preset.iconToken,
                title: "+\(preset.amountML)",
                detail: hydration.preferences.showsPresetNames ? preset.name : "mL",
                tint: tint
            )
        }
        .buttonStyle(WatchGlassButtonStyle(tint: tint, cornerRadius: 16))
        .disabled(hydration.isSaving)
        .accessibilityLabel("Add \(preset.amountML) milliliters of \(preset.name)")
    }

    private func drinkLabel(icon: String, title: String, detail: String, tint: Color) -> some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(height: 15)
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 60, minHeight: 50)
    }

    // MARK: More

    private var morePage: some View {
        ScrollView {
            VStack(spacing: 6) {
                if workout.isActive {
                    Button {
                        Task { await workout.stop() }
                    } label: {
                        WatchMoreRow(
                            title: "End \(workout.activityName)",
                            systemImage: "figure.strengthtraining.traditional",
                            tint: violet,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(WatchGlassButtonStyle(tint: violet, cornerRadius: 18))
                    .accessibilityHint("Ends the FITR MAX workout sensor session")
                }
                NavigationLink {
                    HydrationHistoryView()
                        .environmentObject(hydration)
                } label: {
                    WatchMoreRow(title: "History", systemImage: "clock.arrow.circlepath", tint: aqua)
                }
                .buttonStyle(WatchGlassButtonStyle(tint: aqua, cornerRadius: 18))

                NavigationLink {
                    WatchHydrationSettingsView()
                        .environmentObject(hydration)
                } label: {
                    WatchMoreRow(title: "Settings", systemImage: "gearshape.fill", tint: .white)
                }
                .buttonStyle(WatchGlassButtonStyle(tint: .white, cornerRadius: 18))
                .accessibilityLabel("Hydration settings")
            }
            .padding(.horizontal, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private enum WatchPage: Hashable {
    case water
    case supplements
    case more

    static var initial: WatchPage {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["APEX_WATCH_PREVIEW_PAGE"] {
        case "supplements": return .supplements
        case "more": return .more
        default: return .water
        }
        #else
        return .water
        #endif
    }
}

enum WatchTint {
    static let aqua = Color(red: 0.08, green: 0.80, blue: 0.92)
    static let violet = Color(red: 0.55, green: 0.34, blue: 0.98)
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.29)
    static let ember = Color(red: 1.0, green: 0.45, blue: 0.2)
}

/// Frosted glass that takes the colour of what it holds, lit along its top edge; it dips and brightens under a finger.
struct WatchGlassButtonStyle: ButtonStyle {
    let tint: Color
    let cornerRadius: CGFloat
    var isLit = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let lift = configuration.isPressed ? 0.12 : 0
        configuration.label
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.15 + lift), .white.opacity(0.045 + lift)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                shape.fill(tint.opacity((isLit ? 0.22 : 0.07) + lift))
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(isLit ? 0.7 : 0.42), tint.opacity(isLit ? 0.55 : 0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct WatchMoreRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    var showsChevron = true

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: Circle())
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 50)
    }
}

private extension String {
    /// "2.75 L" with a no-break space, so a figure never wraps away from its unit.
    var joiningUnit: String { replacingOccurrences(of: " ", with: "\u{00A0}") }
}

private struct WatchQuickPreset: Identifiable {
    let id: UUID
    let name: String
    let amountML: Int
    let kind: HydrationKind
    let paletteToken: String
    let iconToken: String

    init(_ preset: HydrationPreset) {
        id = preset.id
        name = preset.name
        amountML = preset.amountML
        kind = preset.kind.eventKind
        paletteToken = preset.paletteToken
        iconToken = preset.iconToken
    }

    init(_ preset: HydrationPresetTemplate) {
        id = preset.id
        name = preset.name
        amountML = preset.amountML
        kind = preset.kind.eventKind
        paletteToken = preset.paletteToken
        iconToken = preset.iconToken
    }
}

private enum HydrationPalette {
    static func color(for token: String) -> Color {
        let rgb = rgb(for: token)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func rgb(for token: String) -> (red: Double, green: Double, blue: Double) {
        switch token {
        case "espresso": (0.55, 0.29, 0.13)
        case "tea": (0.24, 0.75, 0.39)
        case "citrus": (1.00, 0.54, 0.08)
        case "cocoa": (0.66, 0.39, 0.24)
        case "violet": (0.55, 0.34, 0.98)
        case "food": (0.20, 0.78, 0.66)
        case "external": (0.94, 0.32, 0.62)
        case "legacy": (0.32, 0.52, 0.72)
        case "blue": (0.11, 0.39, 0.98)
        default: (0.08, 0.80, 0.92)
        }
    }

    /// The day's drinks in the order they were poured, weighted by volume, for the liquid in the figure.
    static func vesselBands(for bands: [HydrationCompositionBand]) -> [WatchVesselBand] {
        // Layout locations run from the surface (0) down to the feet (1); the vessel counts upwards.
        let layout = HydrationCompositionLayout.stops(for: bands, mappedInto: 0 ... 1)
        guard !layout.isEmpty else {
            return [
                WatchVesselBand(red: 0.55, green: 0.34, blue: 0.98, location: 0),
                WatchVesselBand(red: 0.11, green: 0.39, blue: 0.98, location: 0.4),
                WatchVesselBand(red: 0.08, green: 0.80, blue: 0.92, location: 0.85),
                WatchVesselBand(red: 0.62, green: 0.94, blue: 1.0, location: 1),
            ]
        }
        return layout.map {
            let rgb = rgb(for: $0.paletteToken)
            return WatchVesselBand(red: rgb.red, green: rgb.green, blue: rgb.blue, location: 1 - $0.location)
        }
    }

    static func timelineStops(
        for bands: [HydrationCompositionBand],
        fallback: [Color],
        mappedInto range: ClosedRange<Double> = 0 ... 1
    ) -> [Gradient.Stop] {
        let layout = HydrationCompositionLayout.timelineStops(for: bands, mappedInto: range)
        return gradientStops(for: layout, fallback: fallback)
    }

    private static func gradientStops(
        for layout: [HydrationCompositionStop],
        fallback: [Color]
    ) -> [Gradient.Stop] {
        guard !layout.isEmpty else {
            let denominator = Double(max(1, fallback.count - 1))
            return fallback.enumerated().map { index, color in
                Gradient.Stop(color: color, location: Double(index) / denominator)
            }
        }
        return layout.map {
            Gradient.Stop(color: color(for: $0.paletteToken), location: $0.location)
        }
    }
}

private struct HydrationProgressGleam: View {
    let progress: Double
    let composition: [HydrationCompositionBand]
    let animationIsEnabled: Bool
    let aqua: Color
    let violet: Color

    var body: some View {
        TimelineView(.animation(paused: !animationIsEnabled)) { timeline in
            let phase = animationIsEnabled ? timeline.date.timeIntervalSinceReferenceDate * 0.9 : 0
            GeometryReader { geometry in
                let width = max(0, geometry.size.width * progress)
                let travel = max(0, width - 10)
                let normalizedPhase = animationIsEnabled ? (sin(phase * 0.85) + 1) / 2 : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.14))

                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: HydrationPalette.timelineStops(for: composition, fallback: [violet, aqua]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width)
                        .overlay(alignment: .leading) {
                            if animationIsEnabled, width > 10 {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, .white.opacity(0.85), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 10)
                                    .offset(x: travel * normalizedPhase)
                                    .blendMode(.plusLighter)
                            }
                        }
                        .clipShape(Capsule())
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct WatchHydrationSettingsView: View {
    @EnvironmentObject private var hydration: WatchHydrationStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = WatchHydrationPreferences.default
    @State private var quietStart = Date()
    @State private var quietEnd = Date()
    @State private var validationMessage: String?
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("Daily goal") {
                Picker(
                    "Goal mode",
                    selection: Binding(
                        get: { draft.effectiveTargetMode },
                        set: { draft.targetMode = $0 }
                    )
                ) {
                    Text("Auto").tag(HydrationTargetMode.automatic)
                    Text("Custom").tag(HydrationTargetMode.custom)
                }
                if draft.effectiveTargetMode == .automatic {
                    Text("\(draft.targetLiters.formatted(.number.precision(.fractionLength(2)))) L from your profile and today’s iPhone activity")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    TextField(
                        "Exact litres",
                        value: $draft.targetLiters,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    Stepper(value: $draft.targetLiters, in: 1...6, step: 0.1) {
                        Text("\(draft.targetLiters.formatted(.number.precision(.fractionLength(2)))) L")
                            .font(.headline)
                            .bold()
                    }
                }
                Picker("Units", selection: $draft.unit) {
                    ForEach(WatchHydrationPreferences.Unit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
            }

            Section("Reminders") {
                Toggle("Hydration reminders", isOn: $draft.remindersEnabled)
                if draft.remindersEnabled {
                    Picker("Reminder gap", selection: $draft.reminderIntervalMinutes) {
                        Text("60 min").tag(60)
                        Text("90 min").tag(90)
                        Text("120 min").tag(120)
                    }
                    DatePicker("Quiet from", selection: $quietStart, displayedComponents: .hourAndMinute)
                    DatePicker("Quiet until", selection: $quietEnd, displayedComponents: .hourAndMinute)
                    Text("Only when you are behind your goal pace. Maximum three per day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Presentation") {
                Toggle("Show preset names", isOn: $draft.showsPresetNames)
                Toggle("Confirmation haptics", isOn: $draft.confirmationHaptics)
                Picker("Motion", selection: $draft.motionIntensity) {
                    ForEach(WatchHydrationPreferences.MotionIntensity.allCases) { intensity in
                        Text(intensity.label).tag(intensity)
                    }
                }
            }

            Section {
                NavigationLink {
                    WatchSupplementSettingsView()
                        .environmentObject(hydration)
                } label: {
                    Label {
                        Text("Supplements", tableName: "WatchSupplements")
                    } icon: {
                        Image(systemName: "pills")
                    }
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button("Save settings", systemImage: "checkmark.circle.fill", action: save)
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
        }
        .navigationTitle("Hydration")
        .task {
            loadDraft()
        }
    }

    private func loadDraft() {
        guard !didLoad else { return }
        didLoad = true
        draft = hydration.preferences
        quietStart = date(minutesAfterMidnight: draft.quietHoursStartMinutes)
        quietEnd = date(minutesAfterMidnight: draft.quietHoursEndMinutes)
    }

    private func save() {
        draft.quietHoursStartMinutes = minutesAfterMidnight(quietStart)
        draft.quietHoursEndMinutes = minutesAfterMidnight(quietEnd)
        Task {
            do {
                try await hydration.updatePreferences(draft)
                dismiss()
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }

    private func date(minutesAfterMidnight: Int) -> Date {
        let start = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .minute, value: minutesAfterMidnight, to: start) ?? start
    }

    private func minutesAfterMidnight(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ((components.hour ?? 0) * 60) + (components.minute ?? 0)
    }
}

private struct HydrationHistoryView: View {
    @EnvironmentObject private var hydration: WatchHydrationStore
    @State private var deletionCandidate: WatchHydrationEntry?
    @State private var showsDeleteConfirmation = false

    var body: some View {
        Group {
            if hydration.entries.isEmpty {
                ContentUnavailableView(
                    "No water yet",
                    systemImage: "drop",
                    description: Text("Today’s entries will appear here.")
                )
            } else {
                List(hydration.entries) { entry in
                    if entry.canDelete {
                        Button {
                            requestDeletion(entry)
                        } label: {
                            HydrationHistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                requestDeletion(entry)
                            }
                        }
                        .accessibilityHint("Double-tap or swipe left to remove")
                    } else {
                        HydrationHistoryRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("History")
        .task { await hydration.refresh() }
        .confirmationDialog("Remove water entry?", isPresented: $showsDeleteConfirmation) {
            if let deletionCandidate {
                Button("Remove \(Int(deletionCandidate.milliliters.rounded())) mL", role: .destructive) {
                    removeCandidate()
                }
            }
            Button("Cancel", role: .cancel) {
                deletionCandidate = nil
                showsDeleteConfirmation = false
            }
        } message: {
            Text("This removes the FITR MAX Watch entry from Apple Health too.")
        }
    }

    private func requestDeletion(_ entry: WatchHydrationEntry) {
        deletionCandidate = entry
        showsDeleteConfirmation = true
    }

    private func removeCandidate() {
        guard let deletionCandidate else { return }
        self.deletionCandidate = nil
        showsDeleteConfirmation = false
        Task {
            await hydration.delete(deletionCandidate)
        }
    }
}

private struct HydrationHistoryRow: View {
    let entry: WatchHydrationEntry

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(entry.milliliters.rounded())) mL")
                    .font(.headline)
                    .bold()
                Text(entry.date, style: .time)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(entry.sourceName)
                    .font(.footnote)
                    .foregroundStyle(.cyan)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: entry.canDelete ? "trash.circle" : "lock.fill")
                .font(.footnote)
                .foregroundStyle(entry.canDelete ? Color.red : Color.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(Int(entry.milliliters.rounded())) milliliters, \(entry.sourceName)"
        )
    }
}
