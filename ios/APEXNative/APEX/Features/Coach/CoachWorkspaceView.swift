import SwiftUI

struct CoachWorkspaceView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var roster: [CoachRosterEntry] = []
    @State private var query = ""
    @State private var loading = false
    @State private var invitePresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                coachHeader

                Button {
                    invitePresented = true
                } label: {
                    Label(language.text("Invite a client"), systemImage: "person.badge.plus")
                        .font(APEXFont.body(15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(language.text("Search clients"))
                            .font(APEXFont.mono(9, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(APEXColor.secondaryInk)
                        TextField(language.text("Search clients"), text: $query)
                            .textFieldStyle(.plain)
                            .font(APEXFont.body(15, weight: .semibold))
                            .padding(13)
                            .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .onSubmit { Task { await reload() } }

                        if loading {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 28)
                        } else if roster.isEmpty {
                            Text(language.text("No clients yet"))
                                .font(APEXFont.body(14, weight: .semibold))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        } else {
                            ForEach(roster) { client in
                                NavigationLink {
                                    CoachClientStudioView(client: client)
                                } label: {
                                    CoachRosterRow(client: client)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .dockClearance()
        }
        .navigationTitle(language.text("Coach workspace"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
        .sheet(isPresented: $invitePresented) {
            CoachInvitationSheet()
                .environment(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var coachHeader: some View {
        let coach = session.coachContext.coach
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    (Text(verbatim: "APEX") + Text(verbatim: " · ") + Text(language.text("Development access")))
                        .font(APEXFont.mono(9, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(language.text("Coach workspace"))
                        .font(APEXFont.display(35))
                        .foregroundStyle(.white)
                    Text(language.text("Your clients, plans and reviews in one private place."))
                        .font(APEXFont.body(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(language.text("Sponsored seats"))
                        .font(APEXFont.mono(8, weight: .bold))
                    Text("\(coach?.activeSeats ?? 0)/\(coach?.seatLimit ?? 0)")
                        .font(APEXFont.display(25))
                }
                .foregroundStyle(.white)
                .padding(11)
                .background(.white.opacity(0.17), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(22)
        .background(
            LinearGradient(colors: [APEXColor.violet, Color.purple, APEXColor.amber], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .shadow(color: APEXColor.violet.opacity(0.28), radius: 24, y: 14)
    }

    @MainActor
    private func reload() async {
        guard session.coachContext.capabilities.coachWorkspace else { return }
        loading = true
        defer { loading = false }
        do {
            roster = try await session.loadCoachRoster(query: query)
        } catch {
            session.alertMessage = error.localizedDescription
        }
    }
}

private struct CoachRosterRow: View {
    @State private var language = LanguageState.shared
    let client: CoachRosterEntry

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(client.attention.isEmpty ? APEXColor.green : APEXColor.amber)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName)
                    .font(APEXFont.body(15, weight: .bold))
                    .foregroundStyle(APEXColor.ink)
                    .lineLimit(1)
                Text(client.planTitle ?? language.text("Nothing has been published yet."))
                    .font(APEXFont.body(11, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .lineLimit(2)
                Text(language.text(client.attention.isEmpty ? "Up to date" : "Needs attention"))
                    .font(APEXFont.mono(8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(client.attention.isEmpty ? APEXColor.green : APEXColor.amberDeep)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
        }
        .padding(13)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CoachInvitationSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State private var email = ""
    @State private var scopes: Set<CoachConsentScope> = [.nutrition, .workouts, .activity, .hydration, .supplements, .avatar, .measurements, .recovery]
    @State private var visualProgress = false
    @State private var receipt: CoachInvitationReceipt?
    @State private var busy = false

    private var inviteLink: String? {
        receipt.map { "https://evoryder8-collab.github.io/APXAppiC/#/coach/invite/\($0.token)" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(language.text("Invite a client"))
                        .font(APEXFont.display(31))
                        .foregroundStyle(APEXColor.ink)
                    TextField(language.text("Client email"), text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 17, style: .continuous))

                    CoachScopeSelector(
                        scopes: $scopes,
                        visualProgress: $visualProgress,
                        offered: Set(CoachConsentScope.allCases),
                        visualProgressOffered: true
                    )

                    Button {
                        Task { await createInvite() }
                    } label: {
                        if busy { ProgressView().tint(.white) }
                        else { Text(language.text("Create private invite")) }
                    }
                    .font(APEXFont.body(15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(APEXColor.violet, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .disabled(busy || !email.contains("@"))

                    if let inviteLink {
                        ShareLink(item: inviteLink) {
                            Label(language.text("Share private invite"), systemImage: "square.and.arrow.up")
                                .font(APEXFont.body(15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(APEXColor.violet)
                                .background(APEXColor.violet.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .padding(20)
            }
            .background(APEXBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.text("Close")) { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func createInvite() async {
        busy = true
        defer { busy = false }
        do {
            var requested = scopes
            if visualProgress { requested.insert(.visualProgress) }
            receipt = try await session.createCoachInvitation(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                scopes: requested,
                visualProgressRequested: visualProgress
            )
        } catch {
            session.alertMessage = error.localizedDescription
        }
    }
}

private struct CoachClientStudioView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let client: CoachRosterEntry
    @State private var overview: CoachClientOverview?
    @State private var plan = CoachPlanDraft.empty
    @State private var expectedVersion = 0
    @State private var loading = true
    @State private var saving = false

    private var validation: CoachPlanValidator.Result {
        CoachPlanValidator.validate(
            plan,
            publishing: true,
            knownMovementIDs: Set(ExerciseCatalog.all.map(\.movementID))
        )
    }

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().padding(.top, 80)
            } else {
                VStack(spacing: 16) {
                    if let overview { sharedOverview(overview) }
                    planStudio
                }
                .padding(18)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle(client.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func sharedOverview(_ overview: CoachClientOverview) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("Shared overview"))
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(APEXColor.green)
                Text(language.text("Only categories this client consented to are visible."))
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                    if let workouts = overview.workouts {
                        CoachOverviewMetric(title: language.text("Workouts in 30 days"), value: "\(workouts.completed30Days)")
                    }
                    if let nutrition = overview.nutrition {
                        CoachOverviewMetric(title: language.text("Average daily energy"), value: nutrition.averageKcal.map { "\(Int($0)) kcal" } ?? "—")
                    }
                    if let hydration = overview.hydration {
                        CoachOverviewMetric(title: language.text("Average daily water"), value: hydration.averageLitres.map { String(format: "%.2f L", $0) } ?? "—")
                    }
                    if let measurements = overview.measurements {
                        CoachOverviewMetric(title: language.text("Current weight"), value: String(format: "%.1f kg", measurements.weightKG))
                    }
                }
            }
        }
    }

    private var planStudio: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                (Text(language.text("Plan studio"))
                    + Text(verbatim: " · ")
                    + Text(verbatim: "v")
                    + Text(verbatim: String(expectedVersion + 1)))
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(APEXColor.violet)
                CoachTextField(title: language.text("Plan title"), text: $plan.title)
                CoachTextField(title: language.text("Objective"), text: $plan.objective, axis: .vertical)
                CoachTextField(title: language.text("Coach note"), text: $plan.coachNote, axis: .vertical)
                CoachTextField(title: language.text("Review date"), text: Binding(
                    get: { plan.reviewDate ?? "" },
                    set: { plan.reviewDate = $0.isEmpty ? nil : $0 }
                ))

                ForEach($plan.sessions) { $workout in
                    CoachSessionEditor(session: $workout)
                }

                Button {
                    plan.sessions.append(CoachSessionTemplate(
                        id: UUID(), weekday: min(7, plan.sessions.count + 1), name: "",
                        sessionMode: .guided, estimatedMinutes: 45, warmupNote: "", exercises: []
                    ))
                } label: {
                    Label(language.text("Add session"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .font(APEXFont.body(14, weight: .bold))
                .foregroundStyle(APEXColor.violet)
                .background(APEXColor.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                CoachChecklist(checklist: $plan.checklist)
                if !validation.publishable {
                    Text(language.format("%d checks remain before publishing.", validation.issues.count))
                        .font(APEXFont.body(11, weight: .bold))
                        .foregroundStyle(APEXColor.amberDeep)
                }

                HStack(spacing: 10) {
                    Button(language.text("Save draft")) { Task { await save(publish: false) } }
                        .buttonStyle(.bordered)
                    Button(language.text("Publish to client")) { Task { await save(publish: true) } }
                        .buttonStyle(.borderedProminent)
                        .tint(APEXColor.violet)
                        .disabled(!validation.publishable)
                }
                .font(APEXFont.body(13, weight: .bold))
                .disabled(saving)
            }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let value = try await session.loadCoachClientOverview(relationshipID: client.id)
            overview = value
            plan = value.currentPlan?.plan ?? .empty
            expectedVersion = value.currentPlan?.version ?? 0
        } catch {
            session.alertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save(publish: Bool) async {
        saving = true
        defer { saving = false }
        do {
            let receipt = publish
                ? try await session.publishCoachPlan(relationshipID: client.id, plan: plan, expectedVersion: expectedVersion)
                : try await session.saveCoachPlan(relationshipID: client.id, plan: plan, expectedVersion: expectedVersion)
            expectedVersion = receipt.version
            await load()
        } catch {
            session.alertMessage = error.localizedDescription
        }
    }
}

private struct CoachOverviewMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(APEXFont.body(10, weight: .semibold)).foregroundStyle(APEXColor.secondaryInk)
            Text(value).font(APEXFont.display(20)).foregroundStyle(APEXColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct CoachTextField: View {
    let title: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(APEXFont.mono(8, weight: .bold)).foregroundStyle(APEXColor.secondaryInk)
            TextField(title, text: $text, axis: axis)
                .lineLimit(axis == .vertical ? 2...6 : 1...1)
                .font(APEXFont.body(14, weight: .semibold))
                .padding(12)
                .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct CoachSessionEditor: View {
    @State private var language = LanguageState.shared
    @Binding var session: CoachSessionTemplate
    @State private var cataloguePresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.text("Session"))
                    .font(APEXFont.mono(9, weight: .bold))
                    .foregroundStyle(APEXColor.violet)
                Spacer()
                Stepper("\(language.text("Day")) \(session.weekday)", value: $session.weekday, in: 1...7)
                    .font(APEXFont.body(11, weight: .bold))
            }
            CoachTextField(title: language.text("Session name"), text: $session.name)
            Picker(language.text("Session mode"), selection: $session.sessionMode) {
                Text(language.text("Guided")).tag(WorkoutSessionMode.guided)
                Text(language.text("Tracked")).tag(WorkoutSessionMode.tracked)
            }
            .pickerStyle(.segmented)
            Stepper("\(session.estimatedMinutes) \(language.text("minutes"))", value: $session.estimatedMinutes, in: 5...360, step: 5)
                .font(APEXFont.body(12, weight: .bold))
            CoachTextField(title: language.text("Warm-up note"), text: $session.warmupNote, axis: .vertical)

            ForEach($session.exercises) { $exercise in
                CoachExerciseEditor(exercise: $exercise) {
                    session.exercises.removeAll { $0.id == exercise.id }
                }
            }

            Button {
                cataloguePresented = true
            } label: {
                Label(language.text("Add movement"), systemImage: "plus")
                    .font(APEXFont.body(12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(APEXColor.violet)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(13)
        .background(APEXColor.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sheet(isPresented: $cataloguePresented) {
            CoachMovementPicker { item in
                session.exercises.append(CoachExerciseTemplate(
                    id: UUID(), movementID: item.movementID, name: item.name,
                    sets: max(1, min(12, item.sets)), targetMin: max(1, item.reps), targetMax: max(1, item.reps),
                    unit: ["reps", "seconds", "minutes", "metres", "steps", "rounds"].contains(item.unit) ? item.unit : "reps",
                    perSide: item.perSide, restSeconds: max(0, min(600, item.rest)),
                    tempoUpSeconds: 1, tempoDownSeconds: 2, tempoPauseSeconds: 0,
                    notes: "", optional: false, groupID: nil, groupPosition: nil
                ))
                cataloguePresented = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct CoachExerciseEditor: View {
    @State private var language = LanguageState.shared
    @Binding var exercise: CoachExerciseTemplate
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(exercise.name).font(APEXFont.body(13, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
            }
            HStack {
                Stepper("\(exercise.sets) \(language.text("sets"))", value: $exercise.sets, in: 1...12)
                Spacer()
                TextField("min", value: $exercise.targetMin, format: .number).frame(width: 45).textFieldStyle(.roundedBorder)
                Text("–")
                TextField("max", value: $exercise.targetMax, format: .number).frame(width: 45).textFieldStyle(.roundedBorder)
            }
            .font(APEXFont.body(11, weight: .semibold))
            Toggle(language.text("Per side"), isOn: $exercise.perSide)
                .font(APEXFont.body(11, weight: .semibold))
        }
        .padding(11)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct CoachMovementPicker: View {
    @State private var language = LanguageState.shared
    @State private var query = ""
    let select: (ExerciseCatalogItem) -> Void
    private var results: [ExerciseCatalogItem] {
        Array(ExerciseCatalog.search(query, category: "all", language: language.language).prefix(40))
    }
    var body: some View {
        NavigationStack {
            List(results) { item in
                Button {
                    select(item)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.localizedName(language.language)).font(APEXFont.body(14, weight: .bold))
                        Text(item.equipment).font(APEXFont.body(10, weight: .semibold)).foregroundStyle(APEXColor.secondaryInk)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: language.text("Find a reviewed movement"))
            .navigationTitle(language.text("Add movement"))
        }
    }
}

private struct CoachChecklist: View {
    @State private var language = LanguageState.shared
    @Binding var checklist: CoachPlanChecklist
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("Publishing check"))
                .font(APEXFont.mono(9, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
            Toggle(language.text("Nutrition reviewed"), isOn: $checklist.nutrition)
            Toggle(language.text("Workouts reviewed"), isOn: $checklist.workouts)
            Toggle(language.text("Supplements reviewed"), isOn: $checklist.supplements)
            Toggle(language.text("Hydration reviewed"), isOn: $checklist.hydration)
            Toggle(language.text("Schedule reviewed"), isOn: $checklist.schedule)
            Toggle(language.text("Review date set"), isOn: $checklist.reviewDate)
        }
        .font(APEXFont.body(12, weight: .semibold))
        .padding(13)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CoachScopeSelector: View {
    @State private var language = LanguageState.shared
    @Binding var scopes: Set<CoachConsentScope>
    @Binding var visualProgress: Bool
    let offered: Set<CoachConsentScope>
    let visualProgressOffered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(language.text("What they may share"))
                .font(APEXFont.mono(9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(APEXColor.secondaryInk)
            ForEach(CoachConsentScope.allCases.filter { $0 != .visualProgress && offered.contains($0) }, id: \.self) { scope in
                Toggle(language.text(scope.titleKey), isOn: Binding(
                    get: { scopes.contains(scope) },
                    set: { enabled in
                        if enabled { scopes.insert(scope) } else { scopes.remove(scope) }
                    }
                ))
                .font(APEXFont.body(13, weight: .semibold))
            }
            if visualProgressOffered && offered.contains(.visualProgress) {
                Toggle(isOn: $visualProgress) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.text("Visual progress photos"))
                        Text(language.text("Visual progress is always a separate opt-in."))
                            .font(APEXFont.body(10, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }
                .font(APEXFont.body(13, weight: .bold))
                .padding(12)
                .background(APEXColor.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
    }
}

extension CoachConsentScope {
    var titleKey: String {
        switch self {
        case .nutrition: "Nutrition"
        case .workouts: "Workouts"
        case .activity: "Daily activity"
        case .hydration: "Hydration"
        case .supplements: "Supplements"
        case .avatar: "Avatar scores"
        case .measurements: "Body measurements"
        case .notes: "Check-in notes"
        case .recovery: "Recovery"
        case .visualProgress: "Visual progress photos"
        }
    }
}
