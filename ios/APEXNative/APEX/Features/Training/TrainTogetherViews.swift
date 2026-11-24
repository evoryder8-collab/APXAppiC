import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Opens a room for the workout on screen: now or at a time, with friends or,
/// for a coach, as a class.
struct TrainTogetherHostSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let title: String
    let plan: TrainTogether.Plan
    let accent: Color
    let onOpen: (TrainTogetherRoom) -> Void

    @State private var kind = TrainTogether.Kind.friends
    @State private var startNow = true
    @State private var startsAt = Date().addingTimeInterval(3_600)
    @State private var canHostClass = false
    @State private var allowed: Bool?
    @State private var working = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(language.text(title))
                        .font(APEXFont.display(22))
                    Text(language.format("%d exercises", plan.exercises.count))
                        .font(APEXFont.mono(11))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                if canHostClass {
                    Section {
                        Picker(language.text("Who is coming"), selection: $kind) {
                            Text(language.text("With friends")).tag(TrainTogether.Kind.friends)
                            Text(language.text("Class")).tag(TrainTogether.Kind.class)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    Toggle(language.text("Start now"), isOn: $startNow)
                    if !startNow {
                        DatePicker(language.text("Starts"), selection: $startsAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                } footer: {
                    Text(language.text(kind == .friends
                        ? "Up to 10 people. Everyone can pause, add time and start the next set."
                        : "Up to 50 people. Only you control the workout; everyone follows your screen."))
                }
                if let message {
                    Section { Text(language.text(message)).foregroundStyle(.orange) }
                }
            }
            .navigationTitle(language.text("Train together"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Open room")) { open() }
                        .disabled(working || allowed != true)
                        .accessibilityIdentifier("train-together-open-room")
                }
            }
            .task {
                guard let client = session.trainTogetherClient else {
                    allowed = false
                    message = TrainTogetherError.unavailable.message
                    return
                }
                let access = await TrainTogetherRoom.access(client: client)
                allowed = access.allowed
                canHostClass = access.canHostClass
                if !access.allowed { message = TrainTogetherError.premiumRequired.message }
            }
        }
    }

    private func open() {
        guard let client = session.trainTogetherClient else { return }
        working = true
        message = nil
        Task {
            defer { working = false }
            do {
                let room = try await TrainTogetherRoom.create(
                    client: client, kind: kind, title: title,
                    startsAt: startNow ? Date() : startsAt, plan: plan
                )
                dismiss()
                onOpen(room)
            } catch let error as TrainTogetherError {
                message = error.message
            } catch {
                message = TrainTogetherError.unavailable.message
            }
        }
    }
}

/// "Join a workout" for the Training page.
struct TrainTogetherJoinButton: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let accent: Color

    var body: some View {
        Button {
            session.trainTogetherJoinRequested = true
        } label: {
            Label(language.text("Join a workout"), systemImage: "person.2.fill")
                .font(APEXFont.body(13, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(minHeight: 46)
                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .accessibilityIdentifier("train-together-join")
    }
}

/// The code a link, a message or the welcome screen brought, then the room.
private struct TrainTogetherJoinSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State var code: String
    let onJoined: (TrainTogetherRoom, TrainTogether.AnchorRows) -> Void
    @State private var working = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(language.text("Enter the code from the person you're training with, or paste their link."))
                    .font(APEXFont.body(15, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                HStack(spacing: 12) {
                    TextField(language.text("Code"), text: $code)
                        .font(APEXFont.mono(26))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityIdentifier("train-together-code")
                    PasteButton(payloadType: String.self) { strings in
                        if let found = strings.lazy.compactMap(TrainTogether.code(in:)).first {
                            code = found
                        }
                    }
                    .labelStyle(.iconOnly)
                }
                if let message {
                    Text(language.text(message))
                        .font(APEXFont.body(13, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Button {
                    join()
                } label: {
                    if working { ProgressView().tint(.white) } else { Text(language.text("Join")) }
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.violet))
                .disabled(working || TrainTogether.code(in: code) == nil)
                .accessibilityIdentifier("train-together-join-confirm")
                Spacer()
            }
            .padding(20)
            .navigationTitle(language.text("Join a workout"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Cancel")) {
                        session.pendingTrainTogetherCode = nil
                        dismiss()
                    }
                }
            }
            .task {
                if TrainTogether.code(in: code) != nil { join() }
            }
        }
    }

    private func join() {
        guard !working, let found = TrainTogether.code(in: code),
              let client = session.trainTogetherClient,
              let operation = session.accountOperationLease() else { return }
        working = true
        message = nil
        // A saved code is tried once; it must never retry itself on every launch.
        session.pendingTrainTogetherCode = nil
        Task {
            defer { working = false }
            var opened: TrainTogetherRoom?
            do {
                let room = try await TrainTogetherRoom.join(client: client, code: found)
                opened = room
                let rows = TrainTogether.anchorRows(
                    plan: room.info.plan, roomID: room.info.id, title: room.info.title, ownerID: operation.ownerID
                )
                try await session.installTrainTogetherDay(rows, operation: operation)
                dismiss()
                onJoined(room, rows)
            } catch {
                await opened?.close(leaving: false)
                message = ((error as? TrainTogetherError) ?? .unavailable).message
            }
        }
    }
}

/// Presents the join sheet when a link, the welcome screen or the Training
/// page asks for it, then the joined workout full screen.
struct TrainTogetherJoinFlow: ViewModifier {
    @Environment(AppSession.self) private var session
    @State private var joined: JoinedRoom?
    /// Held until the code sheet has finished closing, so the workout can open.
    @State private var arrived: JoinedRoom?

    private struct JoinedRoom: Identifiable {
        let id: UUID
        let room: TrainTogetherRoom
        let rows: TrainTogether.AnchorRows
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: {
                    joined == nil && arrived == nil
                        && (session.pendingTrainTogetherCode != nil || session.trainTogetherJoinRequested)
                },
                set: { open in
                    if !open {
                        session.trainTogetherJoinRequested = false
                        session.pendingTrainTogetherCode = nil
                    }
                }
            ), onDismiss: {
                joined = arrived
                arrived = nil
            }) {
                TrainTogetherJoinSheet(code: session.pendingTrainTogetherCode ?? "") { room, rows in
                    session.trainTogetherJoinRequested = false
                    arrived = JoinedRoom(id: room.info.id, room: room, rows: rows)
                }
                .environment(session)
                .presentationDetents([.medium])
            }
            .fullScreenCover(item: $joined) { joined in
                WorkoutPlayerView(
                    day: joined.rows.day,
                    exercises: joined.rows.exercises,
                    accent: APEXColor.violet,
                    lite: false,
                    date: Date().apexDateKey,
                    warmupText: joined.room.info.plan.warmupText,
                    warmupDuration: joined.room.info.plan.warmupDuration,
                    room: joined.room
                )
                .environment(session)
            }
    }
}

extension View {
    func trainTogetherJoinFlow() -> some View { modifier(TrainTogetherJoinFlow()) }

    func trainTogetherHostFlow(
        isPresented: Binding<Bool>, day: ProgramDay?, exercises: [Exercise], warmupText: String,
        warmupDuration: Int, accent: Color, lite: Bool, date: String
    ) -> some View {
        modifier(TrainTogetherHostFlow(
            isPresented: isPresented, day: day, exercises: exercises, warmupText: warmupText,
            warmupDuration: warmupDuration, accent: accent, lite: lite, date: date
        ))
    }
}

/// "Train together" beside a day's start buttons.
struct TrainTogetherHostButton: View {
    @State private var language = LanguageState.shared
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(language.text("Train together"), systemImage: "person.2.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(accent)
    }
}

/// The host sheet, then the guided player in room mode. Attached at the top of a
/// screen, not to the button, so the workout stays open when the button goes.
struct TrainTogetherHostFlow: ViewModifier {
    @Environment(AppSession.self) private var session
    @Binding var isPresented: Bool
    let day: ProgramDay?
    let exercises: [Exercise]
    let warmupText: String
    let warmupDuration: Int
    let accent: Color
    let lite: Bool
    let date: String
    /// Held until the host sheet has finished closing, so the workout can open.
    @State private var opened: TrainTogetherRoom?
    @State private var hosting: TrainTogetherRoom?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: {
                hosting = opened
                opened = nil
            }) {
                if let day {
                    TrainTogetherHostSheet(
                        title: day.name,
                        plan: TrainTogether.Plan(
                            name: day.name, warmupText: warmupText, warmupDuration: warmupDuration,
                            exercises: exercises.map(TrainTogether.PlanExercise.init)
                        ),
                        accent: accent
                    ) { room in
                        opened = room
                    }
                    .environment(session)
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { hosting != nil },
                set: { open in if !open { hosting = nil } }
            )) {
                if let day, let hosting {
                    WorkoutPlayerView(
                        day: day,
                        exercises: exercises,
                        accent: accent,
                        lite: lite,
                        date: min(date, Date().apexDateKey),
                        warmupText: warmupText,
                        warmupDuration: warmupDuration,
                        room: hosting
                    )
                    .environment(session)
                }
            }
            // The day's date is counted from the shared date, which a Sunday midnight would move a week on under an open workout.
            .onChange(of: hosting != nil) { _, open in session.holdBrowsingDate(open) }
    }
}

/// The room before Start: who is hosting, how to invite, and the exercises,
/// which a class follows card by card as the host swipes.
struct TrainTogetherLobby: View {
    @State private var language = LanguageState.shared
    let room: TrainTogetherRoom
    let exercises: [Exercise]
    let accent: Color
    @Binding var shareMySets: Bool
    @State private var page: Int?
    @State private var showQR = false

    private var synced: Bool { room.info.kind == .class }

    var body: some View {
        VStack(spacing: 16) {
            GlassCard(radius: 30, padding: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(language.text(room.info.kind == .class ? "CLASS" : "TRAIN TOGETHER"))
                        .font(APEXFont.mono(10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(accent)
                    Text(language.text(room.info.title))
                        .font(APEXFont.display(26))
                    Text(startLine)
                        .font(APEXFont.body(13, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                    Text(peopleLine)
                        .font(APEXFont.body(13, weight: .semibold))
                        .accessibilityIdentifier("train-together-people")
                    if room.isHost || room.info.kind == .friends {
                        invite
                    }
                    if room.info.kind == .friends {
                        Toggle(language.text("Let the others see my sets"), isOn: $shareMySets)
                            .font(APEXFont.body(13, weight: .semibold))
                        if room.isHost {
                            Toggle(language.text("Everyone can control"), isOn: Binding(
                                get: { room.sharedControl },
                                set: { room.setSharedControl($0) }
                            ))
                            .font(APEXFont.body(13, weight: .semibold))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                        card(exercise, focused: index == (page ?? room.focus))
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollDisabled(synced && !room.isHost)
            .frame(height: 300)
            .onChange(of: page) { _, index in
                if let index, synced, room.isHost { room.show(card: index) }
            }
            .onChange(of: room.focus) { _, focus in
                guard synced, !room.isHost, page != focus else { return }
                withAnimation(.smooth(duration: 0.45)) { page = focus }
            }
            .onAppear { page = room.focus }

            if room.canControl {
                Button {
                    room.send(.start)
                } label: {
                    Label(language.text("Start"), systemImage: "play.fill")
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: accent))
                .accessibilityIdentifier("train-together-start")
            } else {
                Text(language.format("Waiting for %@ to start", room.info.hostName))
                    .font(APEXFont.body(13, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var startLine: String {
        let host = room.info.hostName
        guard room.info.startsAt > room.serverNow.addingTimeInterval(60) else {
            return host.isEmpty ? language.text("Starting now") : language.format("With %@ · starting now", host)
        }
        let time = room.info.startsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(language.language.locale))
        return host.isEmpty ? time : language.format("With %@ · %@", host, time)
    }

    private var peopleLine: String {
        guard room.showsNames else {
            return language.format("%d training", room.memberCount + 1)
        }
        let others = room.names
            .filter { $0.key != room.myUserID && $0.key != room.info.hostUserID }
            .map(\.value).filter { !$0.isEmpty }.sorted()
        if others.isEmpty { return language.text("Nobody else has joined yet") }
        return language.format("Here: %@", others.joined(separator: ", "))
    }

    private var invite: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(room.info.code)
                    .font(APEXFont.mono(30, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(accent)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("train-together-code-display")
                Spacer()
                Button {
                    showQR.toggle()
                } label: {
                    Image(systemName: "qrcode")
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.7), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("Show QR code"))
                if let url = TrainTogether.shareURL(code: room.info.code) {
                    ShareLink(item: url, message: Text(language.format("Train with me in FITR MAX. Code %@", room.info.code))) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.7), in: Circle())
                    }
                    .accessibilityLabel(language.text("Share the invitation"))
                }
            }
            if showQR, let appURL = TrainTogether.appURL(code: room.info.code), let image = TrainTogetherQRCode.image(for: appURL.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(language.text("QR code to join with the iPhone camera"))
            }
        }
    }

    private func card(_ exercise: Exercise, focused: Bool) -> some View {
        GlassCard(radius: 24, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                if focused, let artwork = GuidedArtwork.movement(exercise) {
                    TimelineView(.animation) { context in
                        GuidedArtworkView(
                            artwork: artwork, exercise: exercise,
                            elapsed: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600),
                            advancing: true
                        )
                    }
                    .frame(height: 190)
                } else {
                    GuidedPreviewPhoto(exercise: exercise, height: 190)
                }
                Text(language.text(exercise.name))
                    .font(APEXFont.display(19))
                    .lineLimit(2)
                Text(WorkoutDayView.prescription(exercise, sets: exercise.sets, language: language))
                    .font(APEXFont.mono(11))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accent.opacity(focused && synced ? 0.5 : 0), lineWidth: 2)
        )
    }

}

/// The room's people count and sound switches in the player's header. Whoever
/// controls the room switches them for everyone; anyone else mutes their phone.
struct TrainTogetherHeaderButtons: View {
    @State private var language = LanguageState.shared
    let room: TrainTogetherRoom
    @Binding var muted: Bool
    let accent: Color

    var body: some View {
        Label("\(room.memberCount + 1)", systemImage: "person.2.fill")
            .font(APEXFont.mono(11, weight: .bold))
            .foregroundStyle(accent)
            .accessibilityLabel(language.format("%d training", room.memberCount + 1))
        if room.canControl {
            circle(room.state.voice ? "speaker.wave.2.fill" : "speaker.slash.fill",
                   label: room.state.voice ? "Turn the voice off for everyone" : "Turn the voice on for everyone") {
                room.send(.voice(!room.state.voice))
            }
            circle(room.state.sound ? "metronome.fill" : "metronome",
                   label: room.state.sound ? "Turn sounds off for everyone" : "Turn sounds on for everyone") {
                room.send(.sound(!room.state.sound))
            }
        } else {
            circle(muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                   label: muted ? "Unmute this phone" : "Mute this phone") {
                muted.toggle()
            }
        }
    }

    private func circle(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 35, height: 35)
                .background(.white.opacity(0.7), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text(label))
    }
}

/// Above the workout: who leads it, a way on if the host has gone, and why a
/// press did not go through.
struct TrainTogetherBanner: View {
    @State private var language = LanguageState.shared
    let room: TrainTogetherRoom
    let accent: Color
    let onCarryOn: () -> Void

    var body: some View {
        let host = room.info.hostName
        if let error = room.lastError {
            Text(language.text(error.message))
                .font(APEXFont.body(12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)
        }
        if !room.isHost, let away = room.hostAwaySince, Date().timeIntervalSince(away) > 60 {
            Button(action: onCarryOn) {
                Label(host.isEmpty ? language.text("Carry on alone") : language.format("Carry on without %@", host),
                      systemImage: "figure.run")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(accent)
            .accessibilityIdentifier("train-together-carry-on")
        } else if !room.canControl {
            Text(host.isEmpty ? language.text("Following along") : language.format("Following %@", host))
                .font(APEXFont.mono(10, weight: .bold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
        }
    }
}

/// On the rest card: a class host sees how many have logged the set just done;
/// friends see each other's last set when they chose to share it.
struct TrainTogetherRestLines: View {
    @State private var language = LanguageState.shared
    let room: TrainTogetherRoom
    let position: Int

    var body: some View {
        if room.isHost, room.info.kind == .class {
            let others = room.present.filter { $0.key != room.myUserID }
            let logged = others.filter { $0.value.logged >= position + 1 }.count
            Text(language.format("%d of %d logged", logged, others.count))
                .font(APEXFont.body(13, weight: .bold))
                .foregroundStyle(APEXColor.violet)
                .accessibilityIdentifier("train-together-logged")
        }
        if room.info.kind == .friends {
            let shared = room.present
                .filter { $0.key != room.myUserID }
                .compactMap { id, presence in presence.set.map { (room.names[id] ?? "", $0) } }
                .sorted { $0.0 < $1.0 }
            ForEach(shared, id: \.0) { name, set in
                Text("\(name): \(line(set))")
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func line(_ set: TrainTogetherPresence.SharedSet) -> String {
        var parts = [language.text(set.exercise)]
        if let reps = set.reps {
            // The figure and its unit stay on one line.
            let load = set.kg.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))\u{00A0}kg" }
            parts.append(load.map { "\(reps) × \($0)" } ?? language.format("%d reps", reps))
        }
        if let rir = set.rir { parts.append(language.text("RIR") + "\u{00A0}\(rir)") }
        return parts.joined(separator: " · ")
    }
}

enum TrainTogetherQRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
