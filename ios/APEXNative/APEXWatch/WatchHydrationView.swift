import SwiftUI

struct WatchHydrationView: View {
    @EnvironmentObject private var hydration: WatchHydrationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsCustomAmount = false
    @State private var showsHistory = false

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
            reduceMotion: reduceMotion
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
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(aqua)
                        Text("APEX HYDRATION")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.7)
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer(minLength: 0)
                    }

                    hydrationCard

                    HStack(spacing: 6) {
                        quickAdd(250)
                        quickAdd(300)
                        quickAdd(500)
                    }

                    HStack(spacing: 6) {
                        utilityButton("Custom", systemImage: "slider.horizontal.3") {
                            showsCustomAmount = true
                        }
                        utilityButton("History", systemImage: "clock.arrow.circlepath") {
                            showsHistory = true
                        }
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
                .padding(.vertical, 5)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            if previewLiters == nil {
                await hydration.start()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, previewLiters == nil else { return }
            Task { await hydration.refresh() }
        }
        .sheet(isPresented: $showsCustomAmount) {
            CustomHydrationAmountView()
                .environmentObject(hydration)
        }
        .sheet(isPresented: $showsHistory) {
            HydrationHistoryView()
                .environmentObject(hydration)
        }
    }

    private var hydrationCard: some View {
        HStack(spacing: 8) {
            HydrationSilhouetteGauge(
                fillState: fillState,
                aqua: aqua,
                violet: violet,
                animationIsEnabled: animationIsEnabled
            )
            .frame(width: 58, height: 101)

            VStack(alignment: .leading, spacing: 5) {
                Text(fillState.primaryAmount)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [violet, aqua], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 58 * fillState.progress)
                }
                .frame(width: 58, height: 4)
                .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: fillState.progress)

                Text("\(Int((fillState.progress * 100).rounded()))%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("TARGET \(hydration.targetLiters.formatted(.number.precision(.fractionLength(2)))) L")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
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
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hydration")
        .accessibilityValue(
            "\(displayedLiters.formatted(.number.precision(.fractionLength(2)))) of "
                + "\(hydration.targetLiters.formatted(.number.precision(.fractionLength(2)))) liters, "
                + "\(Int((fillState.progress * 100).rounded())) percent"
        )
    }

    private func quickAdd(_ milliliters: Int) -> some View {
        Button {
            Task { await hydration.add(milliliters: Double(milliliters)) }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(aqua)
                Text("+\(milliliters)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 36)
            .background(.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(aqua.opacity(0.18), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .disabled(hydration.isSaving)
        .accessibilityLabel("Add \(milliliters) milliliters of water")
    }

    private func utilityButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 30)
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
    let aqua: Color
    let violet: Color
    let animationIsEnabled: Bool

    var body: some View {
        TimelineView(.animation(paused: !animationIsEnabled)) { timeline in
            let phase = animationIsEnabled
                ? timeline.date.timeIntervalSinceReferenceDate * 0.9
                : 0
            let breath = animationIsEnabled ? sin(phase * 0.72) : 0
            let floatOffset = animationIsEnabled ? sin(phase * 0.54) * 1.7 : 0

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
                            colors: [Color.white.opacity(0.9), aqua, Color(red: 0.11, green: 0.39, blue: 0.98), violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
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
            .offset(y: floatOffset)
            .animation(animationIsEnabled ? .smooth(duration: 0.75) : nil, value: fillState.progress)
        }
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
