import SwiftUI

struct WatchHydrationView: View {
    @EnvironmentObject private var hydration: WatchHydrationStore
    @EnvironmentObject private var workout: WatchWorkoutSessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsCustomAmount = false
    @State private var showsHistory = false
    @State private var showsSettings = false

    private let aqua = Color(red: 0.08, green: 0.80, blue: 0.92)
    private let violet = Color(red: 0.55, green: 0.34, blue: 0.98)

    private var previewLiters: Double? {
        #if DEBUG
        ProcessInfo.processInfo.environment["APEX_WATCH_PREVIEW_LITERS"].flatMap(Double.init)
        #else
        nil
        #endif
    }

    private var displayedLiters: Double { previewLiters ?? hydration.liters }

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

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.035, blue: 0.075), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 4) {
                    hydrationCard

                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(quickPresets) { preset in
                                quickAdd(preset)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    HStack(spacing: 6) {
                        utilityButton("Custom", systemImage: "slider.horizontal.3") {
                            showsCustomAmount = true
                        }
                        utilityButton("History", systemImage: "clock.arrow.circlepath") {
                            showsHistory = true
                        }
                    }

                    if workout.isActive {
                        Button {
                            Task { await workout.stop() }
                        } label: {
                            Label("\(workout.activityName) active · End", systemImage: "figure.strengthtraining.traditional")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(violet)
                        .accessibilityHint("Ends the APEX workout sensor session")
                    }

                    if !hydration.isAuthorized {
                        Button("Reconnect Apple Health") {
                            Task { await hydration.reconnect() }
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .buttonStyle(.borderedProminent)
                        .tint(aqua)
                    }

                    if let message = hydration.message {
                        Text(message)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(aqua)
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
                .padding(.horizontal, 7)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.top, 0, for: .scrollContent)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: showHydrationSettings) {
                    HStack(spacing: 5) {
                        Label("APEX HYDRATION", systemImage: "drop.fill")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(aqua)
                        Image(systemName: "gearshape")
                            .font(.footnote)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hydration settings")
            }
        }
        .task {
            if previewLiters == nil {
                await hydration.start()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, previewLiters == nil else { return }
            Task { await hydration.refresh(retryComplicationIfStale: true) }
        }
        .sheet(isPresented: $showsCustomAmount) {
            CustomHydrationAmountView()
                .environmentObject(hydration)
        }
        .sheet(isPresented: $showsHistory) {
            HydrationHistoryView()
                .environmentObject(hydration)
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                WatchHydrationSettingsView()
                    .environmentObject(hydration)
            }
        }
    }

    private var hydrationCard: some View {
        TimelineView(.animation(paused: !animationIsEnabled)) { timeline in
            let phase = animationIsEnabled
                ? timeline.date.timeIntervalSinceReferenceDate * 0.9
                : 0

            HStack(spacing: 8) {
                HydrationSilhouetteGauge(
                    fillState: fillState,
                    composition: hydration.composition,
                    aqua: aqua,
                    violet: violet,
                    animationIsEnabled: animationIsEnabled,
                    phase: phase,
                    motionScale: hydration.preferences.motionIntensity.scale
                )
                .frame(width: 48, height: 83)

                VStack(alignment: .leading, spacing: 5) {
                    Text(hydration.preferences.formattedAmount(liters: displayedLiters))
                        .font(.title3)
                        .bold()
                        .fontDesign(.rounded)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    HydrationProgressGleam(
                        progress: fillState.progress,
                        composition: hydration.composition,
                        phase: phase,
                        animationIsEnabled: animationIsEnabled,
                        aqua: aqua,
                        violet: violet
                    )
                    .frame(height: 6)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: fillState.progress)

                    Text("\(Int((fillState.progress * 100).rounded()))%")
                        .font(.headline)
                        .bold()
                        .fontDesign(.rounded)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("TARGET \(hydration.preferences.formattedTarget)")
                        .font(.footnote)
                        .bold()
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [.white.opacity(0.105), aqua.opacity(0.055), violet.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.13), lineWidth: 0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hydration")
            .accessibilityValue(
                "\(hydration.preferences.formattedAmount(liters: displayedLiters)) of "
                    + "\(hydration.preferences.formattedTarget), "
                    + "\(Int((fillState.progress * 100).rounded())) percent"
            )
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
            VStack(spacing: 1) {
                Image(systemName: preset.iconToken)
                    .font(.footnote)
                    .bold()
                    .foregroundStyle(tint)
                Text(hydration.preferences.showsPresetNames ? preset.name : "+\(preset.amountML)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .bold()
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text(hydration.preferences.showsPresetNames ? "+\(preset.amountML) mL" : "mL")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 68)
            .frame(minHeight: 44)
            .background(.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.32), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .disabled(hydration.isSaving)
        .accessibilityLabel("Add \(preset.amountML) milliliters of \(preset.name)")
    }

    private func showHydrationSettings() {
        showsSettings = true
    }

    private func utilityButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote)
                .bold()
                .fontDesign(.rounded)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    .white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
    }
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
        switch token {
        case "espresso": Color(red: 0.55, green: 0.29, blue: 0.13)
        case "tea": Color(red: 0.24, green: 0.75, blue: 0.39)
        case "citrus": Color(red: 1.00, green: 0.54, blue: 0.08)
        case "cocoa": Color(red: 0.66, green: 0.39, blue: 0.24)
        case "violet": Color(red: 0.55, green: 0.34, blue: 0.98)
        case "food": Color(red: 0.20, green: 0.78, blue: 0.66)
        case "external": Color(red: 0.94, green: 0.32, blue: 0.62)
        case "legacy": Color(red: 0.32, green: 0.52, blue: 0.72)
        case "blue": Color(red: 0.11, green: 0.39, blue: 0.98)
        default: Color(red: 0.08, green: 0.80, blue: 0.92)
        }
    }

    static func stops(
        for bands: [HydrationCompositionBand],
        fallback: [Color],
        mappedInto range: ClosedRange<Double> = 0 ... 1
    ) -> [Gradient.Stop] {
        let layout = HydrationCompositionLayout.stops(for: bands, mappedInto: range)
        return gradientStops(for: layout, fallback: fallback)
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
    let phase: Double
    let animationIsEnabled: Bool
    let aqua: Color
    let violet: Color

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width * progress)
            let travel = max(0, width - 10)
            let normalizedPhase = animationIsEnabled ? (sin(phase * 0.85) + 1) / 2 : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .stroke(.white.opacity(0.20), lineWidth: 1)

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

private struct CustomHydrationAmountView: View {
    @EnvironmentObject private var hydration: WatchHydrationStore
    @Environment(\.dismiss) private var dismiss
    @State private var milliliters = 350.0

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Label("CUSTOM WATER", systemImage: "drop.fill")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.cyan)

                Stepper(value: $milliliters, in: 50...3_000, step: 10) {
                    VStack(spacing: 2) {
                        Text("\(Int(milliliters))")
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("MILLILITRES")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Add \(Int(milliliters)) mL") {
                    Task {
                        await hydration.add(milliliters: milliliters)
                        if hydration.isAuthorized { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(hydration.isSaving)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Custom")
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
            Text("This removes the APEX Watch entry from Apple Health too.")
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

private struct HydrationSilhouetteGauge: View {
    let fillState: WatchHydrationFillState
    let composition: [HydrationCompositionBand]
    let aqua: Color
    let violet: Color
    let animationIsEnabled: Bool
    let phase: Double
    let motionScale: Double

    var body: some View {
        let breath = animationIsEnabled ? sin(phase * 0.72) * motionScale : 0

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [aqua.opacity(0.30), violet.opacity(0.14), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 41
                    )
                )
                .frame(width: 82, height: 82)
                .blur(radius: 7)
                .scaleEffect(1 + (breath * 0.045))

            Image("HydrationMaleSilhouette")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.075))

            HydrationWaveShape(progress: fillState.progress, phase: phase)
                .fill(
                    LinearGradient(
                        stops: HydrationPalette.stops(
                            for: composition,
                            fallback: [Color.white.opacity(0.9), aqua, Color(red: 0.11, green: 0.39, blue: 0.98), violet],
                            mappedInto: fillState.baseWaterline ... 1
                        ),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: aqua.opacity(0.7), radius: 7)
                .mask {
                    Image("HydrationMaleSilhouette")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                }

            Image("HydrationMaleSilhouette")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white.opacity(0.58), aqua.opacity(0.34), violet.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(0.38)
                .shadow(color: aqua.opacity(0.62), radius: 3)
        }
        .scaleEffect(1 + (breath * 0.012))
        .animation(animationIsEnabled ? .smooth(duration: 0.75) : nil, value: fillState.progress)
        .accessibilityHidden(true)
    }
}

private struct HydrationWaveShape: Shape {
    var progress: Double
    var phase: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, phase) }
        set {
            progress = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 36
        for step in 0...steps {
            let x = Double(step) / Double(steps)
            let y = WatchHydrationFillState.waterline(progress: progress, normalizedX: x, phase: phase)
            let point = CGPoint(x: rect.minX + (rect.width * x), y: rect.minY + (rect.height * y))
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
