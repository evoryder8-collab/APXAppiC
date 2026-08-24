import SwiftUI

struct WatchHydrationView: View {
    @EnvironmentObject private var hydration: WatchHydrationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                reduceMotion: reduceMotion
            )
            .frame(width: 60, height: 88)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayedLiters.formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.72)
                Text("L TODAY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(aqua)

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
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(entry.milliliters.rounded())) mL")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text(entry.date, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.sourceName)
                                .font(.caption2)
                                .foregroundStyle(.cyan)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if entry.canDelete {
                            Button(role: .destructive) {
                                Task { await hydration.delete(entry) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(Int(entry.milliliters.rounded())) milliliters")
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Read only")
                        }
                    }
                }
            }
        }
        .navigationTitle("Today")
        .task { await hydration.refresh() }
    }
}

private struct HydrationSilhouetteGauge: View {
    let fillState: WatchHydrationFillState
    let aqua: Color
    let violet: Color
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: reduceMotion)) { timeline in
            let phase = reduceMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) * 1.05

            ZStack {
                Ellipse()
                    .fill(aqua.opacity(0.14))
                    .frame(width: 70, height: 28)
                    .blur(radius: 12)
                    .offset(y: 44)

                HydrationBodyShape()
                    .fill(.white.opacity(0.055))

                HydrationWaveShape(progress: fillState.progress, phase: phase)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), aqua, Color(red: 0.11, green: 0.39, blue: 0.98), violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: aqua.opacity(0.7), radius: 7)
                    .mask(HydrationBodyShape())

                HydrationBodyShape()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.62), aqua.opacity(0.5), violet.opacity(0.46)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.15
                    )
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.75), value: fillState.progress)
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

private struct HydrationBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let point: (Double, Double) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.addEllipse(in: CGRect(
            x: rect.minX + rect.width * 0.385,
            y: rect.minY + rect.height * 0.012,
            width: rect.width * 0.23,
            height: rect.height * 0.18
        ))
        path.move(to: point(0.42, 0.19))
        path.addCurve(to: point(0.28, 0.25), control1: point(0.40, 0.22), control2: point(0.33, 0.22))
        path.addCurve(to: point(0.17, 0.59), control1: point(0.23, 0.31), control2: point(0.19, 0.48))
        path.addCurve(to: point(0.23, 0.66), control1: point(0.15, 0.64), control2: point(0.19, 0.69))
        path.addLine(to: point(0.34, 0.43))
        path.addCurve(to: point(0.34, 0.60), control1: point(0.33, 0.49), control2: point(0.33, 0.55))
        path.addLine(to: point(0.29, 0.94))
        path.addCurve(to: point(0.39, 0.97), control1: point(0.28, 0.99), control2: point(0.36, 1.0))
        path.addLine(to: point(0.48, 0.67))
        path.addCurve(to: point(0.52, 0.67), control1: point(0.49, 0.64), control2: point(0.51, 0.64))
        path.addLine(to: point(0.61, 0.97))
        path.addCurve(to: point(0.71, 0.94), control1: point(0.64, 1.0), control2: point(0.72, 0.99))
        path.addLine(to: point(0.66, 0.60))
        path.addCurve(to: point(0.66, 0.43), control1: point(0.67, 0.55), control2: point(0.67, 0.49))
        path.addLine(to: point(0.77, 0.66))
        path.addCurve(to: point(0.83, 0.59), control1: point(0.81, 0.69), control2: point(0.85, 0.64))
        path.addCurve(to: point(0.72, 0.25), control1: point(0.81, 0.48), control2: point(0.77, 0.31))
        path.addCurve(to: point(0.58, 0.19), control1: point(0.67, 0.22), control2: point(0.60, 0.22))
        path.addCurve(to: point(0.42, 0.19), control1: point(0.54, 0.22), control2: point(0.46, 0.22))
        path.closeSubpath()
        return path
    }
}
