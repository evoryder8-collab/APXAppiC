import SwiftUI

/// "Group workout" on the Simple dashboard and the Training page: open a room
/// whose workout the wheel chooses, or join someone else's with a code.
struct GroupWorkoutCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared

    var body: some View {
        // The developer sandbox has no server to open a room on.
        if !session.isDeveloperSandbox { card }
    }

    private var card: some View {
        GlassCard(radius: 26, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(
                            LinearGradient(colors: [APEXColor.violet, APEXColor.cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .shadow(color: APEXColor.violet.opacity(0.35), radius: 12, y: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("Group workout"))
                            .font(APEXFont.display(19))
                        Text(language.text("Train live with friends or clients, and spin the wheel for the workout."))
                            .font(APEXFont.body(13, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        session.trainTogetherStartRequested = true
                    } label: {
                        Label(language.text("Start"), systemImage: "plus")
                            .font(APEXFont.body(15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(APEXColor.violet.gradient, in: Capsule())
                            .shadow(color: APEXColor.violet.opacity(0.3), radius: 10, y: 5)
                    }
                    .accessibilityIdentifier("group-workout-start")
                    Button {
                        session.trainTogetherJoinRequested = true
                    } label: {
                        Label(language.text("Join with a code"), systemImage: "qrcode")
                            .font(APEXFont.body(15, weight: .bold))
                            .foregroundStyle(APEXColor.violet)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(.white.opacity(0.75), in: Capsule())
                            .overlay(Capsule().stroke(APEXColor.violet.opacity(0.25), lineWidth: 1))
                    }
                    .accessibilityIdentifier("train-together-join")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A room full screen: the wheel while it is choosing its workout, then the
/// guided player on the workout put into this account, as for any room.
struct TrainTogetherRoomScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let room: TrainTogetherRoom
    @State private var rows: TrainTogether.AnchorRows?
    @State private var failed = false

    var body: some View {
        Group {
            if room.choosing {
                TrainTogetherWheelLobby(room: room)
            } else if let rows {
                WorkoutPlayerView(
                    day: rows.day,
                    exercises: rows.exercises,
                    accent: APEXColor.violet,
                    lite: false,
                    date: Date().apexDateKey,
                    warmupText: room.plan.warmupText,
                    warmupDuration: room.plan.warmupDuration,
                    room: room
                )
            } else {
                VStack(spacing: 18) {
                    if failed {
                        Text(language.text("Could not set up the workout on this phone. Check your connection and join again."))
                            .font(APEXFont.body(15, weight: .semibold))
                            .multilineTextAlignment(.center)
                        Button(language.text("Close")) {
                            Task { await room.close(leaving: !room.isHost) }
                            dismiss()
                        }
                        .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.violet))
                    } else {
                        ProgressView()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(APEXBackground())
            }
        }
        .task(id: room.choosing) { await install() }
        // Whatever takes this screen away (an access change, signing out), the room is closed with it.
        .onAppear { session.openWorkoutScreens += 1 }
        .onDisappear {
            session.openWorkoutScreens -= 1
            Task { await room.close(leaving: false) }
        }
    }

    /// The room's workout becomes an inactive day in this account, so the normal
    /// player and the normal save run on it.
    private func install() async {
        guard !room.choosing, rows == nil else { return }
        guard let operation = session.accountOperationLease() else {
            failed = true
            return
        }
        let made = TrainTogether.anchorRows(plan: room.plan, roomID: room.info.id, title: room.title, ownerID: operation.ownerID)
        do {
            try await session.installTrainTogetherDay(made, operation: operation)
            rows = made
        } catch {
            failed = true
        }
    }
}

/// The room before it has a workout: everyone ticks their kit, the host picks
/// a focus and spins, and everyone watches the wheel land.
struct TrainTogetherWheelLobby: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let room: TrainTogetherRoom
    @State private var ticked: Set<TrainTogether.Kit> = []
    @State private var showExit = false
    /// "Train this" is being saved.
    @State private var committing = false
    /// The spin whose time is up on this phone; the wheel stops redrawing once it is.
    @State private var settled: TrainTogether.Wheel.Spin?
    @AppStorage("fitr.train-together.kit") private var rememberedKit = ""

    private var accent: Color { APEXColor.violet }
    private var wheel: TrainTogether.Wheel? { room.state.wheel }
    private var focus: TrainTogether.Focus { wheel?.focus ?? .fullBody }
    private var eligible: [TrainTogether.Challenge] {
        TrainTogether.Wheel.eligible(focus: focus, common: room.commonKit)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    if room.ended {
                        endedCard
                    } else {
                        TrainTogetherInviteCard(room: room, accent: accent)
                        if let error = room.lastError {
                            Text(language.text(error.message))
                                .font(APEXFont.body(13, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        wheelCard
                        focusCard
                        kitCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
        }
        .background(APEXBackground())
        .onAppear {
            ticked = Set(rememberedKit.split(separator: ",").compactMap { TrainTogether.Kit(rawValue: String($0)) })
        }
        .confirmationDialog(language.text("Leave this workout?"), isPresented: $showExit, titleVisibility: .visible) {
            // Without its host a room still choosing its workout has nothing left to do, so it ends.
            if room.isHost {
                Button(language.text("End for everyone"), role: .destructive) {
                    Task {
                        await room.endForEveryone()
                        await room.close(leaving: false)
                    }
                    dismiss()
                }
            } else {
                Button(language.text("Leave workout")) {
                    Task { await room.close(leaving: true) }
                    dismiss()
                }
            }
            Button(language.text("Stay"), role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                if room.ended {
                    Task { await room.close(leaving: false) }
                    dismiss()
                } else {
                    showExit = true
                }
            } label: {
                Label(language.text("Exit"), systemImage: "arrow.left")
            }
            .buttonStyle(.plain)
            Spacer()
            Text(language.text(room.title))
                .font(APEXFont.display(17))
                .lineLimit(1)
            Spacer()
            Label("\(room.headcount)", systemImage: "person.2.fill")
                .font(APEXFont.mono(12, weight: .bold))
                .foregroundStyle(accent)
                .accessibilityLabel(language.format("%d training", room.headcount))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var endedCard: some View {
        GlassCard(radius: 26, padding: 20) {
            VStack(spacing: 14) {
                Text(language.text("This workout has ended."))
                    .font(APEXFont.display(20))
                Button(language.text("Close")) {
                    Task { await room.close(leaving: false) }
                    dismiss()
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: accent))
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - The wheel

    private var wheelCard: some View {
        GlassCard(radius: 30, padding: 18) {
            VStack(spacing: 16) {
                Text(language.text("THE WHEEL"))
                    .font(APEXFont.mono(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TimelineView(.animation(minimumInterval: nil, paused: !spinning)) { _ in
                    let shown = shownSlots
                    let elapsed = wheel?.spin.map { room.serverNow.timeIntervalSince($0.at) }
                    let landed = wheel?.spin != nil && settled == wheel?.spin
                    let angle = wheel?.spin.map {
                        TrainTogether.Wheel.angle(slots: $0.slots.count, landing: $0.landing, elapsed: elapsed ?? 0)
                    } ?? 0
                    VStack(spacing: 16) {
                        ChallengeWheel(
                            labels: shown.map { TrainTogether.Challenge.named($0)?.name ?? "?" },
                            angle: angle,
                            landed: landed ? wheel?.spin?.landing : nil
                        )
                        .frame(maxWidth: 330)
                        .frame(maxWidth: .infinity)
                        .sensoryFeedback(.selection, trigger: TrainTogether.Wheel.slotUnderPointer(angle: angle, slots: shown.count))
                        .sensoryFeedback(.success, trigger: landed) { old, new in !old && new }
                        .accessibilityLabel(language.text("The wheel"))
                        if landed, let spin = wheel?.spin {
                            if let challenge = TrainTogether.Challenge.named(spin.slots[spin.landing]) {
                                result(challenge)
                            } else {
                                Text(language.text("Update FITR MAX to see this challenge."))
                                    .font(APEXFont.body(14, weight: .semibold))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                spinControls
                            }
                        } else if elapsed != nil {
                            Text(language.text("Spinning…"))
                                .font(APEXFont.body(15, weight: .semibold))
                                .foregroundStyle(APEXColor.secondaryInk)
                        } else {
                            spinControls
                        }
                    }
                }
            }
        }
        .task(id: wheel?.spin) {
            guard let spin = wheel?.spin else {
                settled = nil
                return
            }
            let left = spin.at.timeIntervalSince(room.serverNow) + TrainTogether.Wheel.spinSeconds
            try? await Task.sleep(for: .seconds(max(0, left) + 0.1))
            if !Task.isCancelled { settled = spin }
        }
    }

    /// The wheel everyone sees: the spin's own slots once spun, so every phone
    /// shows the same wheel; before that, what this phone's kit makes possible.
    private var shownSlots: [String] {
        wheel?.spin?.slots ?? TrainTogether.Wheel.slots(for: eligible.map(\.id))
    }

    @ViewBuilder private var spinControls: some View {
        if room.isHost {
            Button {
                spin()
            } label: {
                Label(language.text("Spin the wheel"), systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(APEXPrimaryButtonStyle(color: accent))
            .disabled(eligible.isEmpty)
            .accessibilityIdentifier("train-together-spin")
        } else {
            Text(language.format("Waiting for %@ to spin", room.info.hostName))
                .font(APEXFont.body(14, weight: .semibold))
                .foregroundStyle(APEXColor.secondaryInk)
        }
    }

    private func result(_ challenge: TrainTogether.Challenge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.text(challenge.name))
                .font(APEXFont.display(24))
            Text(language.format("%@ · about %d min", language.text(challenge.focus.label), challenge.estimatedMinutes))
                .font(APEXFont.mono(11))
                .foregroundStyle(accent)
            ForEach(Array(challenge.exercises().enumerated()), id: \.offset) { _, exercise in
                HStack(alignment: .firstTextBaseline) {
                    Text(language.text(exercise.name))
                        .font(APEXFont.body(14, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(WorkoutDayView.prescription(exercise, sets: exercise.sets, language: language))
                        .font(APEXFont.mono(11))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
            }
            if challenge.matHelps {
                Label(language.text("A mat helps"), systemImage: "rectangle.portrait.fill")
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            if room.isHost {
                HStack(spacing: 10) {
                    Button(language.text("Spin again")) { spin() }
                        .buttonStyle(.bordered)
                        .tint(accent)
                        .disabled(committing)
                    Button {
                        committing = true
                        Task {
                            await room.choose(challenge)
                            committing = false
                        }
                    } label: {
                        if committing { ProgressView().tint(.white) } else { Text(language.text("Train this")) }
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: accent))
                    .disabled(committing)
                    .accessibilityIdentifier("train-together-train-this")
                }
            } else {
                Text(language.format("Waiting for %@ to choose", room.info.hostName))
                    .font(APEXFont.body(14, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spin() {
        var generator = SystemRandomNumberGenerator()
        guard let drawn = TrainTogether.Wheel.draw(from: eligible, using: &generator) else { return }
        room.send(.spin(slots: drawn.slots, landing: drawn.landing))
    }

    // MARK: - Focus and kit

    private var focusCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("FOCUS"))
                    .font(APEXFont.mono(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(accent)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(TrainTogether.Focus.allCases, id: \.self) { option in
                        Button {
                            room.send(.wheelFocus(option))
                        } label: {
                            chip(language.text(option.label), selected: option == focus)
                        }
                        .buttonStyle(.plain)
                        .disabled(!room.isHost)
                    }
                }
                if !room.isHost {
                    Text(language.format("%@ picks the focus", room.info.hostName))
                        .font(APEXFont.body(12, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var spinning: Bool { wheel?.spin != nil && settled != wheel?.spin }

    private var kitCard: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("WHAT DO YOU HAVE?"))
                    .font(APEXFont.mono(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(accent)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(TrainTogether.Kit.allCases, id: \.self) { item in
                        Button {
                            if ticked.contains(item) { ticked.remove(item) } else { ticked.insert(item) }
                            if room.myKit != nil { shareKit() }
                        } label: {
                            chip(language.text(item.label), symbol: item.symbol, selected: ticked.contains(item))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(language.text("Bodyweight, floor space and a wall always count."))
                    .font(APEXFont.body(12, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                if room.myKit == nil {
                    Button(language.text("That's what I have")) { shareKit() }
                        .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.teal))
                        .accessibilityIdentifier("train-together-kit-done")
                } else {
                    Label(language.text("Sent to the room"), systemImage: "checkmark.circle.fill")
                        .font(APEXFont.body(14, weight: .semibold))
                        .foregroundStyle(APEXColor.teal)
                }
                Text(language.format("%d of %d have ticked their kit", room.kitAnswered, room.headcount))
                    .font(APEXFont.mono(11))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .accessibilityIdentifier("train-together-kit-answers")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shareKit() {
        let chosen = TrainTogether.Kit.allCases.filter(ticked.contains)
        rememberedKit = chosen.map(\.rawValue).joined(separator: ",")
        room.share(kit: chosen)
    }

    private func chip(_ title: String, symbol: String? = nil, selected: Bool) -> some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(title).lineLimit(2)
        }
        .font(APEXFont.body(13, weight: .bold))
        .foregroundStyle(selected ? .white : APEXColor.ink)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background {
            Capsule().fill(selected ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.white.opacity(0.72)))
        }
        .overlay(Capsule().stroke(selected ? Color.clear : accent.opacity(0.18), lineWidth: 1))
        .shadow(color: selected ? accent.opacity(0.28) : .clear, radius: 8, y: 4)
    }
}

/// The wheel itself: bright slices with their challenge names, turned by
/// `angle` degrees, with the pointer at the top.
struct ChallengeWheel: View {
    @State private var language = LanguageState.shared
    let labels: [String]
    let angle: Double
    /// The slot it stopped on, which glows while the rest dim.
    let landed: Int?

    private static let palette: [Color] = [
        APEXColor.violet, APEXColor.cyan, APEXColor.amber, APEXColor.teal,
        Color(red: 0.95, green: 0.33, blue: 0.56), Color(red: 0.33, green: 0.49, blue: 1.0),
    ]

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2
            let segment = labels.isEmpty ? 360 : 360 / Double(labels.count)
            ZStack {
                ZStack {
                    ForEach(labels.indices, id: \.self) { index in
                        let start = -90 + Double(index) * segment
                        WheelSlice(start: .degrees(start), end: .degrees(start + segment))
                            .fill(LinearGradient(
                                colors: [color(index), color(index).opacity(0.72)],
                                startPoint: .center, endPoint: .bottomTrailing
                            ))
                            .opacity(landed == nil || landed == index ? 1 : 0.35)
                        WheelSlice(start: .degrees(start), end: .degrees(start + segment))
                            .stroke(.white.opacity(0.7), lineWidth: 1.5)
                        // A name on the left half is turned over so it always reads upright.
                        let upsideDown = cos((start + segment / 2 + angle) * .pi / 180) < 0
                        Text(language.text(labels[index]))
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(upsideDown ? .leading : .trailing)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .frame(width: radius * 0.62, alignment: upsideDown ? .leading : .trailing)
                            .rotationEffect(.degrees(upsideDown ? 180 : 0))
                            .offset(x: radius * 0.5)
                            .rotationEffect(.degrees(start + segment / 2))
                    }
                }
                .rotationEffect(.degrees(angle))

                Circle()
                    .stroke(.white, lineWidth: 6)
                    .shadow(color: APEXColor.violet.opacity(0.45), radius: 18)
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .frame(width: radius * 0.34, height: radius * 0.34)
                    .overlay(
                        Image(systemName: "person.3.fill")
                            .font(.system(size: radius * 0.1, weight: .bold))
                            .foregroundStyle(APEXColor.violet)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                Pointer()
                    .fill(APEXColor.ink)
                    .frame(width: 26, height: 30)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .offset(y: -radius - 4)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.top, 14)
    }

    private func color(_ index: Int) -> Color {
        var step = index % Self.palette.count
        // The last slice sits beside the first, so it never takes the first one's colour.
        if labels.count > 1, index == labels.count - 1, step == 0 { step = 2 }
        return Self.palette[step]
    }

    private struct WheelSlice: Shape {
        let start: Angle
        let end: Angle

        func path(in rect: CGRect) -> Path {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            var path = Path()
            path.move(to: center)
            path.addArc(center: center, radius: min(rect.width, rect.height) / 2, startAngle: start, endAngle: end, clockwise: false)
            path.closeSubpath()
            return path
        }
    }

    private struct Pointer: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
