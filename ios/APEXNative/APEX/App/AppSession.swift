import Foundation
import Observation
import UIKit

struct AccountGenerationGate: Sendable {
    private(set) var token: UInt64 = 0

    mutating func advance() {
        token &+= 1
    }

    func accepts(_ candidate: UInt64) -> Bool {
        candidate == token
    }
}

@MainActor
@Observable
final class AppSession {
    var route: AppRoute = .launching
    var selectedPersona: Persona?
    /// Shown briefly after a bespoke account signs in by email.
    var greetingPersona: Persona?
    /// The address a confirmation link was just sent to, if any. Held so the
    /// sign-up screen can say what happened rather than appear to do nothing.
    var awaitingConfirmationFor: String?
    /// Debug only: opens the premium sheet straight away for visual checking.
    var previewPaywall = false
    var data: DashboardData = .empty {
        didSet { recomputeBrain() }
    }
    /* Receipts from the interconnection engine, for the Avatar feed */
    var brainSynergies: [FBSynergyEvent] = []
    @ObservationIgnored private var brainRecomputing = false
    var isBusy = false
    var isRefreshing = false
    var alertMessage: String?
    var lastSyncAt: Date?
    var pendingSyncCount = 0
    var navigationPath: [PortalDestination] = []

    private let service = SupabaseService.shared
    private let offlineStore = OfflineStore.shared
    private let defaults = UserDefaults.standard
    @ObservationIgnored private let hydrationConnectivity = HydrationPhoneConnectivity()
    @ObservationIgnored private let hydrationMutationQueue = HydrationMutationQueue()
    @ObservationIgnored private var hydrationMutationsInFlight: Set<UUID> = []
    private var bootstrapped = false
    private var realtimeDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var accountGeneration = AccountGenerationGate()

    init() {
        hydrationConnectivity.mutationHandler = { [weak self] mutation in
            await self?.handleHydrationMutation(mutation)
        }
    }

    @discardableResult
    private func beginAccountBoundary() -> UInt64 {
        accountGeneration.advance()
        hydrationConnectivity.publishDisconnected()
        realtimeDebounceTask?.cancel()
        realtimeDebounceTask = nil
        isBusy = false
        isRefreshing = false
        return accountGeneration.token
    }

    @discardableResult
    private func completeAccountBoundary() -> UInt64 {
        accountGeneration.advance()
        return accountGeneration.token
    }

    private func hydrationOperationIsCurrent(ownerID: UUID, token: UInt64) -> Bool {
        accountGeneration.accepts(token) && verifiedPersistenceOwnerID() == ownerID
    }

    var profile: Profile? { data.profile }
    var isAuthenticated: Bool { data.profile != nil }
    var interfaceMode: PortalUIMode { PortalUIMode.current(from: data.settings) }

    /// A person's last choice is local device preference, deliberately kept
    /// apart from a programme day's authored default.
    func workoutSessionMode(for day: ProgramDay) -> WorkoutSessionMode {
        let key = profile.map { "apex.workout-session-mode.\($0.userID.uuidString)" }
        return WorkoutSessionMode.resolve(
            lastUsed: key.flatMap { defaults.string(forKey: $0) },
            dayDefault: day.sessionMode
        )
    }

    func rememberWorkoutSessionMode(_ mode: WorkoutSessionMode) {
        guard let userID = profile?.userID else { return }
        defaults.set(mode.rawValue, forKey: "apex.workout-session-mode.\(userID.uuidString)")
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        let accountToken = accountGeneration.token
        bootstrapped = true
        EntitlementStore.shared.resetAccount()

        #if DEBUG
        /* Jump straight to a first-run screen for visual checking. Debug only,
           and it never touches the network, so inspecting the questionnaire
           does not leave a stray account behind. */
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-apex-preview"),
           index + 1 < ProcessInfo.processInfo.arguments.count {
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-first-run") {
                LanguageState.shared.language = .english
            }
            switch ProcessInfo.processInfo.arguments[index + 1] {
            case "welcome": route = .welcome
            case "induction": route = .induction
            case "consent": route = .consent
            case "persona": route = .persona
            case "paywall":
                route = .persona
                previewPaywall = true
            default: route = .welcome
            }
            bootstrapped = true
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-apex-ui-test") {
            /* Preferences outlive a relaunch, so one test could otherwise hand
               the next a screen with different sections open. Start every run
               from the same layout. */
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("apex.section.expanded.") {
                defaults.removeObject(forKey: key)
            }
            LanguageState.shared.language = .english
            data = APEXDebugFixture.dashboard()
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-incomplete-plan"),
               var settings = data.settings {
                func claimedIDs(_ slug: String) -> JSONValue {
                    let programIDs = Set(data.programs.filter { $0.slug == slug }.map(\.id))
                    return .array(
                        data.programDays
                            .filter { programIDs.contains($0.programID) }
                            .prefix(1)
                            .map { .string($0.id.uuidString.lowercased()) }
                    )
                }
                settings.addons["training_induction"] = .object([
                    "sessions_per_week": .number(3),
                    "transition_day_ids": claimedIDs("transition"),
                    "main_day_ids": claimedIDs("main"),
                ])
                data.settings = settings
            }
            selectedPersona = .constantine
            route = .portal
            return
        }
        #endif

        if let userID = await service.currentUserID() {
            guard accountGeneration.accepts(accountToken) else { return }
            EntitlementStore.shared.prepareForAccount(userID)
            let cached = try? await offlineStore.loadDashboard(for: userID)
            guard accountGeneration.accepts(accountToken) else { return }
            if let cached, TrainingInduction.belongsToAccount(cached, userID: userID) {
                data = cached
                selectedPersona = cached.profile?.persona
                route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                    ? .portal : .induction
            }
            do {
                await flushPendingChanges(for: userID)
                guard accountGeneration.accepts(accountToken) else { return }
                try await refreshDashboard(expectedUserID: userID)
                guard accountGeneration.accepts(accountToken) else { return }
                selectedPersona = data.profile?.persona
                route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                    ? .portal : .induction
                await startRealtimeSync()
                guard accountGeneration.accepts(accountToken) else { return }
                await importHealthQuietly()
                return
            } catch {
                guard accountGeneration.accepts(accountToken) else { return }
                if TrainingInduction.belongsToAccount(data, userID: userID) {
                    /* No alert: the sync indicator already shows this, and a modal on
                       every launch without signal trains people to dismiss modals. */
                    /* Health still imports. It comes off the phone, not the
                       network, so a failed refresh is no reason to leave the
                       day's steps unread. */
                    await importHealthQuietly()
                    return
                }
            }
        }

        /* No session: the public front door, not the portrait wall. The four
           bespoke accounts reach their portraits from a link on it. */
        guard accountGeneration.accepts(accountToken) else { return }
        route = .welcome
    }

    func choose(_ persona: Persona) {
        selectedPersona = persona
        route = .login(persona)
    }

    func returnToPersonas() {
        selectedPersona = nil
        route = .persona
    }

    func signIn(email: String, password: String) async {
        var accountToken = beginAccountBoundary()
        var boundaryCompleted = false
        EntitlementStore.shared.resetAccount()
        isBusy = true
        defer {
            if accountGeneration.accepts(accountToken) { isBusy = false }
        }
        do {
            let userID = try await service.signIn(email: email, password: password)
            guard accountGeneration.accepts(accountToken) else { return }
            accountToken = completeAccountBoundary()
            boundaryCompleted = true
            try await refreshDashboard(expectedUserID: userID)
            guard accountGeneration.accepts(accountToken) else { return }
            /* The portrait entrance promises a particular person, so it still
               checks. The public email door promises nothing and skips it. */
            if let expected = selectedPersona {
                guard let actual = data.profile?.persona else {
                    throw APEXServiceError.configurationMissing
                }
                guard actual == expected else {
                    try await service.signOut()
                    guard accountGeneration.accepts(accountToken) else { return }
                    data = .empty
                    throw APEXServiceError.personaMismatch(expected: expected, actual: actual)
                }
            }
            if let persona = data.profile?.persona {
                defaults.set(persona.rawValue, forKey: "apex.lastPersona")
                /* A bespoke account gets its own portrait on the way in, and
                   only its own. The portrait wall asked you to pick a face
                   before proving who you were; this shows the face the
                   credentials already identified. */
                if data.profile?.foundingMember == true, selectedPersona == nil {
                    greetingPersona = persona
                }
            }
            route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                ? .portal : .induction
            await startRealtimeSync()
        } catch {
            guard accountGeneration.accepts(accountToken) else { return }
            if !boundaryCompleted {
                accountToken = completeAccountBoundary()
                boundaryCompleted = true
            }
            alertMessage = error.localizedDescription
        }
    }

    /// Create an account, then send it into the questionnaire only if the
    /// account is actually signed in.
    ///
    /// Supabase returns a user with no session when the address needs
    /// confirming, and again when the address was already registered, which it
    /// does deliberately so signing up cannot be used to discover who has an
    /// account. Taking the user id as proof of a session walked people through
    /// all six questions and then discarded the answers at the end, because
    /// saving them needs an authenticated request.
    func signUp(email: String, password: String) async {
        var accountToken = beginAccountBoundary()
        var boundaryCompleted = false
        EntitlementStore.shared.resetAccount()
        isBusy = true
        defer {
            if accountGeneration.accepts(accountToken) { isBusy = false }
        }
        do {
            let outcome = try await service.signUp(email: email, password: password)
            guard accountGeneration.accepts(accountToken) else { return }
            accountToken = completeAccountBoundary()
            boundaryCompleted = true
            switch outcome {
            case .signedIn(let userID):
                EntitlementStore.shared.prepareForAccount(userID)
                selectedPersona = nil
                data = .empty
                route = .induction
            case .awaitingEmailConfirmation:
                awaitingConfirmationFor = email
            }
        } catch {
            guard accountGeneration.accepts(accountToken) else { return }
            if !boundaryCompleted {
                accountToken = completeAccountBoundary()
                boundaryCompleted = true
            }
            alertMessage = error.localizedDescription
        }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        var accountToken = beginAccountBoundary()
        var boundaryCompleted = false
        EntitlementStore.shared.resetAccount()
        isBusy = true
        defer {
            if accountGeneration.accepts(accountToken) { isBusy = false }
        }
        do {
            let userID = try await service.signInWithApple(idToken: idToken, nonce: nonce)
            guard accountGeneration.accepts(accountToken) else { return }
            accountToken = completeAccountBoundary()
            boundaryCompleted = true
            selectedPersona = nil
            try await refreshDashboard(expectedUserID: userID)
            guard accountGeneration.accepts(accountToken) else { return }
            /* A returning Apple account already has a profile and goes home. A
               first-time one has none, and answers the questionnaire instead. */
            route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                ? .portal : .induction
            await startRealtimeSync()
        } catch {
            guard accountGeneration.accepts(accountToken) else { return }
            if !boundaryCompleted {
                accountToken = completeAccountBoundary()
                boundaryCompleted = true
            }
            alertMessage = error.localizedDescription
        }
    }

    /// Turn questionnaire answers into a profile and a first twelve weeks.
    func completeInduction(_ input: TrainingInduction.Input) async {
        await submitInduction(.answered(input))
    }

    /// Continue without turning questionnaire defaults into claimed facts.
    /// Only an account-scoped settings marker is stored; there is deliberately
    /// no profile, generated programme or derived fitness snapshot.
    func skipInduction() async {
        await submitInduction(.skipped)
    }

    private func submitInduction(_ submission: TrainingInduction.Submission) async {
        let accountToken = accountGeneration.token
        guard !isBusy else { return }
        isBusy = true
        defer {
            if accountGeneration.accepts(accountToken) { isBusy = false }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-first-run") {
            submitInductionToFirstRunFixture(submission)
            return
        }
        #endif
        guard let userID = await service.currentUserID() else {
            guard accountGeneration.accepts(accountToken) else { return }
            alertMessage = "Sign in again to continue."
            route = .welcome
            return
        }
        guard accountGeneration.accepts(accountToken) else { return }
        do {
            var settings = try await service.createSettingsIfNeeded(userID: userID).rebound(to: userID)
            guard accountGeneration.accepts(accountToken) else { return }

            let plan = submission.generatedPlan(
                userID: userID,
                existingPrograms: data.programs,
                generationRevision: TrainingInduction.generationRevision(settings)
            )
            if let plan {
                settings = TrainingInduction.markingPendingPlan(settings, plan: plan)
                try await service.upsert(settings, table: "settings", onConflict: "user_id")
                guard accountGeneration.accepts(accountToken) else { return }
                data.settings = settings
                await saveLocalSnapshot()
                guard accountGeneration.accepts(accountToken) else { return }
                try await service.saveInductionPlan(plan)
                guard accountGeneration.accepts(accountToken) else { return }
            }
            settings = submission.applyingAccountMetadata(
                to: settings,
                plan: plan,
                existingData: data
            )
            try await service.upsert(settings, table: "settings", onConflict: "user_id")
            guard accountGeneration.accepts(accountToken) else { return }
            if let plan { applyInductionPlan(plan, settings: settings) }
            else { data.settings = settings }
            if submission.requiresProfile {
                let profile = try await service.createProfileIfNeeded(
                    userID: userID,
                    goal: submission.profileGoal
                )
                guard accountGeneration.accepts(accountToken) else { return }
                data.profile = profile
            }
            await saveLocalSnapshot()
            guard accountGeneration.accepts(accountToken) else { return }
            do { try await refreshDashboard(expectedUserID: userID) }
            catch {
                guard accountGeneration.accepts(accountToken) else { return }
                lastSyncAt = .now
            }
            guard accountGeneration.accepts(accountToken) else { return }
            await resolveEntitlements()
            guard accountGeneration.accepts(accountToken) else { return }
            route = .consent
        } catch {
            guard accountGeneration.accepts(accountToken) else { return }
            alertMessage = error.localizedDescription
        }
    }

    #if DEBUG
    /// Deterministic authenticated first-run account used only by UI tests.
    /// It exercises the real submission and routing decisions without touching
    /// production Supabase data or allowing a preview-only no-op to pass.
    private func submitInductionToFirstRunFixture(_ submission: TrainingInduction.Submission) {
        let userID = UUID(uuidString: "7d3e70bf-c420-4b66-90ae-5a103465f1c1")!
        var settings = APEXDebugFixture.dashboard().settings!.rebound(to: userID)
        settings.addons = [:]
        let plan = submission.generatedPlan(userID: userID, existingPrograms: [])
        settings = submission.applyingAccountMetadata(to: settings, plan: plan, existingData: data)

        data.profile = nil
        data.settings = settings
        data.programs = plan?.programs ?? []
        data.programDays = plan?.programDays ?? []
        data.exercises = plan?.exercises ?? []
        data.snapshots = []
        route = .consent
    }
    #endif

    /// The last step of a first run: permissions have been offered, the trial
    /// is running, and the app opens for real.
    func finishOnboarding() async {
        route = .portal
        await startRealtimeSync()
        await refreshNudges()
    }

    func signOut() async {
        var accountToken = beginAccountBoundary()
        isBusy = true
        defer {
            if accountGeneration.accepts(accountToken) { isBusy = false }
        }
        do {
            try await service.signOut()
            guard accountGeneration.accepts(accountToken) else { return }
            accountToken = completeAccountBoundary()
        }
        catch {
            guard accountGeneration.accepts(accountToken) else { return }
            accountToken = completeAccountBoundary()
            alertMessage = error.localizedDescription
        }
        guard accountGeneration.accepts(accountToken) else { return }
        data = .empty
        pendingSyncCount = 0
        navigationPath.removeAll()
        selectedPersona = nil
        EntitlementStore.shared.resetAccount()
        route = .welcome
    }

    func refreshDashboard(expectedUserID: UUID? = nil) async throws {
        let accountToken = accountGeneration.token
        isRefreshing = true
        defer {
            if accountGeneration.accepts(accountToken) { isRefreshing = false }
        }
        var next = try await service.loadDashboard()
        guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
        let currentUserID = await service.currentUserID()
        guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
        if let profileID = next.profile?.userID,
           let settingsID = next.settings?.userID,
           profileID != settingsID {
            throw APEXServiceError.configurationMissing
        }
        if let expectedUserID,
           !TrainingInduction.isCompatibleDashboard(next, userID: expectedUserID) {
            throw APEXServiceError.configurationMissing
        }
        if let currentUserID {
            guard expectedUserID == nil || expectedUserID == currentUserID,
                  TrainingInduction.isCompatibleDashboard(next, userID: currentUserID)
            else { throw APEXServiceError.configurationMissing }
        }
        let authenticatedUserID = next.profile?.userID
            ?? next.settings?.userID
            ?? expectedUserID
            ?? currentUserID
        if let authenticatedUserID {
            EntitlementStore.shared.prepareForAccount(authenticatedUserID)
            next.settings = next.settings?.rebound(to: authenticatedUserID)
        }
        data = next
        if let authenticatedUserID {
            await ensureHydrationDefaults(ownerID: authenticatedUserID)
            publishHydrationState()
        }
        lastSyncAt = .now
        if let userID = authenticatedUserID {
            try? await offlineStore.saveDashboard(data, for: userID)
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
            let count = try? await offlineStore.pendingOperations(for: userID).count
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
            pendingSyncCount = count ?? 0
        }
        await considerWeeklyCalibration()
        guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
        await resolveEntitlements()
        guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
    }

    /// Store a new profile picture.
    ///
    /// Uploaded first, recorded second: a profile pointing at a file that was
    /// never stored would show a broken picture on every device the account
    /// opens on.
    func setAvatar(data: Data) async {
        guard var profile else { return }
        do {
            let path = try await service.uploadAvatar(userID: profile.userID, data: data)
            profile.avatarPath = path
            profile.updatedAt = Date().ISO8601Format()
            self.data.profile = profile
            await persistUpsert(profile, table: "profile", onConflict: "user_id")
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// Pull today's activity from Apple Health on open, without prompting.
    ///
    /// The phone records steps by itself, and a watch writes to the same place,
    /// so there is nothing to wait for and no reason to make anyone press a
    /// button for data the system already has.
    func importHealthQuietly() async {
        guard let profile else { return }
        if HealthKitManager.shared.waterWriteState == .authorized {
            try? await HealthKitManager.shared.syncFoodWater(
                liters: foodHydrationLiters(on: .now),
                on: .now,
                accountID: profile.userID
            )
        }
        guard let snapshot = await HealthKitManager.shared.silentRefresh() else { return }
        await applyHealthSnapshot(snapshot)
    }

    func startWatchWorkout(day: ProgramDay, exercises: [Exercise]) async {
        guard let ownerID = verifiedPersistenceOwnerID() else { return }
        let accountToken = accountGeneration.token
        let kind = WatchWorkoutHandoff.resolve(
            dayType: day.dayType,
            name: day.name,
            exerciseNames: exercises.map(\.name)
        )
        _ = await HealthKitManager.shared.startWatchWorkout(kind)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
    }

    func stopWatchWorkout() {
        guard let ownerID = verifiedPersistenceOwnerID() else { return }
        hydrationConnectivity.send(.stopping(ownerID: ownerID))
    }

    /// Work out what this account may use, and start the trial clock on the
    /// first open rather than at account creation, so an account made in
    /// advance does not expire sitting unopened.
    func resolveEntitlements() async {
        let accountToken = accountGeneration.token
        if let userID = data.profile?.userID ?? data.settings?.userID {
            EntitlementStore.shared.prepareForAccount(userID)
        }
        guard var profile else { return }
        if profile.foundingMember != true, profile.trialStartedAt == nil {
            profile.trialStartedAt = Date().ISO8601Format()
            profile.updatedAt = Date().ISO8601Format()
            data.profile = profile
            await persistUpsert(profile, table: "profile", onConflict: "user_id")
            guard accountGeneration.accepts(accountToken) else { return }
        }
        EntitlementStore.shared.resolve(profile: profile)
    }

    /*
     * The brain lives on the phone now. Every material data change replays
     * the deterministic engine from the baseline date, exactly like the web
     * client, and the newest snapshot is upserted under the same
     * deterministic per-user id so both clients converge on one row.
     * A missing network never freezes stats again: decay, synergies and
     * imports all keep computing offline.
     */
    private func recomputeBrain() {
        guard !brainRecomputing,
              let userID = data.profile?.userID,
              let input = FitnessBrainService.engineInput(from: data) else { return }
        let result = FitnessBrainEngine.compute(input, throughDate: Date().apexDateKey)
        guard !result.snapshots.isEmpty else { return }

        let previousLatest = data.snapshots.max { $0.date < $1.date }
        let rows = FitnessBrainService.appSnapshots(result.snapshots, userID: userID)
        brainRecomputing = true
        data.snapshots = rows
        brainSynergies = result.synergies
        brainRecomputing = false

        if let latest = rows.last,
           previousLatest?.date != latest.date || previousLatest?.overall != latest.overall {
            #if DEBUG
            // UI automation runs an unauthenticated local fixture; a remote
            // persist would fail into the offline path and raise an alert
            // over the screen mid-test.
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test") { return }
            #endif
            Task { await persistUpsert(latest, table: "rpg_snapshots") }
        }
    }

    func refresh() async {
        if let userID = profile?.userID { await flushPendingChanges(for: userID) }
        do { try await refreshDashboard() }
        catch is CancellationError {
            // Pull-to-refresh, realtime refreshes and scene transitions may
            // legitimately supersede one another. Cancellation is control
            // flow, not a user-facing sync failure.
        } catch let error as URLError where error.code == .cancelled {
            // URLSession reports the same benign cancellation separately.
        } catch {
            /* Falling back to the cache is the designed behaviour, and the
               underlying error is a developer detail, not a user message. */
        }
    }

    func onAppBecameActive() async {
        #if DEBUG
        // UI automation uses a deterministic, local dashboard and must not
        // replace it with an unauthenticated network refresh when XCTest
        // brings the app to the foreground.
        if ProcessInfo.processInfo.arguments.contains("-apex-ui-test") { return }
        #endif
        guard route == .portal else { return }
        /* Health first, and independent of the network. It used to hang off the
           end of the dashboard refresh, so any failed or slow request skipped
           the import altogether and the card sat on "no wearable data" with a
           button to press, for data the phone already had on disk. */
        await importHealthQuietly()
        await refresh()
    }

    func handleAuthCallback(_ url: URL) async {
        var accountToken = beginAccountBoundary()
        var switchedAccounts = false
        EntitlementStore.shared.resetAccount()
        await service.stopRealtime()
        guard accountGeneration.accepts(accountToken) else { return }
        do {
            let userID = try await service.handleAuthCallback(url)
            guard accountGeneration.accepts(accountToken) else { return }
            accountToken = completeAccountBoundary()
            switchedAccounts = true
            EntitlementStore.shared.prepareForAccount(userID)
            data = .empty
            pendingSyncCount = 0
            navigationPath.removeAll()
            selectedPersona = nil
            route = .induction
            try await refreshDashboard(expectedUserID: userID)
            guard accountGeneration.accepts(accountToken) else { return }
            selectedPersona = data.profile?.persona
            route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                ? .portal : .induction
            if route == .portal { await startRealtimeSync() }
        } catch {
            guard accountGeneration.accepts(accountToken) else { return }
            if !switchedAccounts {
                accountToken = completeAccountBoundary()
                await resolveEntitlements()
                guard accountGeneration.accepts(accountToken) else { return }
                if route == .portal { await startRealtimeSync() }
            }
            guard accountGeneration.accepts(accountToken) else { return }
            alertMessage = error.localizedDescription
        }
    }

    func toggleMeal(_ meal: Meal, on date: Date = .now) async {
        guard let profile else { return }
        let day = date.apexDateKey
        if let existing = data.mealLogs.first(where: { $0.date == day && $0.mealID == meal.id }) {
            data.mealLogs.removeAll { $0.id == existing.id }
            await persistDelete(table: "meal_logs", id: existing.id)
        } else {
            let row = MealLog(id: UUID(), userID: profile.userID, date: day, mealID: meal.id, checkedAt: Date().ISO8601Format())
            data.mealLogs.append(row)
            await persistUpsert(row, table: "meal_logs", onConflict: "user_id,date,meal_id")
        }
    }

    /// Mirrors the browser Simple Mode contract: one tap records both the
    /// planned-meal completion and an exact structured nutrition snapshot.
    /// The shared idempotency key lets web and iOS converge on one meal.
    func togglePlannedMeal(_ prescription: AdaptiveMeal, on date: Date = .now) async {
        guard let profile else { return }
        let meal = prescription.source
        let day = date.apexDateKey
        let existingCheck = data.mealLogs.first { $0.date == day && $0.mealID == meal.id }
        let existingStructured = data.loggedMeals.first {
            $0.localDate == day && $0.sourcePlannedMealID == meal.id
        }

        if existingCheck != nil || existingStructured != nil {
            if let existingStructured { await deleteLoggedMeal(existingStructured) }
            if let existingCheck {
                data.mealLogs.removeAll { $0.id == existingCheck.id }
                await persistDelete(table: "meal_logs", id: existingCheck.id)
            }
            return
        }

        let now = Date().ISO8601Format()
        let mealID = UUID()
        let entryID = UUID()
        let idempotencyKey = "simple-planned:\(profile.userID.uuidString.lowercased()):\(day):\(meal.id.uuidString.lowercased())"
        let request = StructuredMealRequest(
            id: mealID,
            localDate: day,
            mealSlot: plannedMealSlot(meal),
            displayName: meal.name,
            sourcePresetID: nil,
            sourcePlannedMealID: meal.id,
            loggedAt: now,
            clientIdempotencyKey: idempotencyKey,
            loggedAs: "planned",
            replaceMealID: nil
        )
        let entry = StructuredFoodEntryRequest(
            id: entryID,
            foodID: nil,
            sortOrder: 0,
            snapshotName: "\(meal.name) · planned prescription",
            snapshotBrand: "APEX plan",
            snapshotPreparationState: "prepared",
            snapshotNutritionBasis: "per_100g",
            snapshotKcal100: Double(prescription.kcal),
            snapshotProtein100: Double(prescription.proteinG),
            snapshotCarbs100: Double(prescription.carbsG),
            snapshotFat100: Double(prescription.fatG),
            snapshotFibre100: nil,
            snapshotSugar100: nil,
            snapshotSaturatedFat100: nil,
            snapshotSalt100: nil,
            snapshotWaterML100: nil,
            snapshotWaterBasis: "unknown",
            snapshotWaterSourceID: nil,
            quantity: 1,
            unit: "serving",
            equivalentAmount: 100
        )
        let localMeal = LoggedMeal(
            id: mealID,
            userID: profile.userID,
            localDate: day,
            mealSlot: plannedMealSlot(meal),
            displayName: meal.name,
            sourcePresetID: nil,
            sourcePlannedMealID: meal.id,
            loggedAt: now,
            clientIdempotencyKey: idempotencyKey,
            loggedAs: "planned",
            totalKcal: Double(prescription.kcal),
            totalProteinG: Double(prescription.proteinG),
            totalCarbsG: Double(prescription.carbsG),
            totalFatG: Double(prescription.fatG)
        )
        let localEntry = LoggedFoodEntry(
            id: entryID,
            mealID: mealID,
            userID: profile.userID,
            foodID: nil,
            sortOrder: 0,
            snapshotName: "\(meal.name) · planned prescription",
            snapshotBrand: "APEX plan",
            snapshotPreparationState: "prepared",
            snapshotNutritionBasis: "per_100g",
            snapshotKcal100: Double(prescription.kcal),
            snapshotProtein100: Double(prescription.proteinG),
            snapshotCarbs100: Double(prescription.carbsG),
            snapshotFat100: Double(prescription.fatG),
            quantity: 1,
            unit: "serving",
            equivalentAmount: 100,
            kcal: Double(prescription.kcal),
            proteinG: Double(prescription.proteinG),
            carbsG: Double(prescription.carbsG),
            fatG: Double(prescription.fatG)
        )
        let check = MealLog(
            id: UUID(), userID: profile.userID, date: day,
            mealID: meal.id, checkedAt: now
        )

        data.loggedMeals.insert(localMeal, at: 0)
        await refreshNudges()
        data.loggedFoodEntries.insert(localEntry, at: 0)
        data.mealLogs.append(check)
        await recalculateLocalStructuredDay(day, userID: profile.userID)
        await persistUpsert(check, table: "meal_logs", onConflict: "user_id,date,meal_id")

        do {
            _ = try await service.logStructuredMeal(meal: request, entries: [entry])
            try await refreshDashboard()
        } catch {
            do {
                let payload = StructuredMealRPCPayload(pMeal: request, pEntries: [entry])
                try await offlineStore.enqueue(.rpc("log_structured_meal", params: payload), for: profile.userID)
                pendingSyncCount = (try? await offlineStore.pendingOperations(for: profile.userID).count) ?? pendingSyncCount + 1
                /* Saved offline and queued. Deliberately silent: this is the app
                   working, not an event, and pendingSyncCount already shows it.
                   Naming the backend on a user's screen helps nobody. */
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func toggleSupplement(_ supplement: Supplement, on date: Date = .now) async {
        guard let profile else { return }
        let day = date.apexDateKey
        if let existing = data.supplementLogs.first(where: { $0.date == day && $0.supplementID == supplement.id }) {
            data.supplementLogs.removeAll { $0.id == existing.id }
            await persistDelete(table: "supplement_logs", id: existing.id)
        } else {
            let row = SupplementLog(id: UUID(), userID: profile.userID, date: day, supplementID: supplement.id, checkedAt: Date().ISO8601Format())
            data.supplementLogs.append(row)
            await persistUpsert(row, table: "supplement_logs", onConflict: "user_id,date,supplement_id")
        }
        await refreshNudges()
    }

    /// Adds a supplement to the plan from wherever the user happens to be.
    ///
    /// Previously the stack could only be checked off, never changed, so
    /// adding one meant leaving the thing you were doing and going to find the
    /// full editor. Sorting after the current last item keeps it in the group
    /// the user picked rather than jumping to the top.
    func addSupplement(name: String, dose: String, groupLabel: String) async {
        guard let profile else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let row = Supplement(
            id: UUID(),
            userID: profile.userID,
            name: trimmedName,
            dose: dose.trimmingCharacters(in: .whitespacesAndNewlines),
            timing: "anytime",
            clockTime: nil,
            offsetMinutes: nil,
            groupLabel: groupLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            trainingDaysOnly: false,
            sortOrder: (data.supplements.map(\.sortOrder).max() ?? 0) + 1
        )
        data.supplements.append(row)
        await persistUpsert(row, table: "supplements", onConflict: "id")
    }

    /// Retires a supplement from the plan, keeping what it recorded.
    ///
    /// supplement_logs cascades on delete, so removing the row would take
    /// every past check-off with it. For somebody paying for the app that is
    /// their data disappearing because they tidied a list, so the row stays
    /// and simply stops appearing in the plan.
    func archiveSupplement(_ supplement: Supplement) async {
        guard let index = data.supplements.firstIndex(where: { $0.id == supplement.id }) else { return }
        data.supplements[index].archived = true
        await persistUpsert(data.supplements[index], table: "supplements", onConflict: "id")
    }

    /// Puts an archived supplement back into the plan.
    func restoreSupplement(_ supplement: Supplement) async {
        guard let index = data.supplements.firstIndex(where: { $0.id == supplement.id }) else { return }
        data.supplements[index].archived = false
        await persistUpsert(data.supplements[index], table: "supplements", onConflict: "id")
    }

    /// Re-evaluate today's reminders from live data.
    ///
    /// Called on open and after anything that could change the answer, because
    /// a local notification is scheduled ahead of time and would otherwise fire
    /// on a stale reading. Being told you are short on protein an hour after
    /// hitting the target is the failure people actually notice.
    func refreshNudges() async {
        guard let profile else { return }
        let today = Date().apexDateKey
        let logs = data.activityLogs.filter { $0.date == today }
        let targets = EnergyEngine.targets(
            profile: profile,
            logs: logs,
            catalog: data.activityTypes,
            planContext: NutritionGoalPolicy.context(from: data.settings)
        )
        let consumed = data.loggedMeals
            .filter { $0.localDate == today }
            .reduce(0.0) { $0 + $1.totalProteinG }
        let creatine = activeSupplements.first { $0.name.lowercased().contains("creatine") }
        let creatineLogged = creatine.map { supplement in
            data.supplementLogs.contains { $0.date == today && $0.supplementID == supplement.id }
        } ?? false

        await NudgeCenter.shared.refresh(
            proteinConsumedG: consumed,
            proteinTargetG: Double(targets.proteinG),
            goal: profile.goal.rawValue,
            bodyweightKG: profile.weightKG,
            creatineInStack: creatine != nil,
            creatineLoggedToday: creatineLogged
        )
    }

    /// What the plan should show: everything not retired.
    var activeSupplements: [Supplement] {
        data.supplements.filter { !$0.archived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func updateDailyLog(_ row: DailyLog, ownerID: UUID? = nil) async {
        if let index = data.dailyLogs.firstIndex(where: { $0.id == row.id }) {
            data.dailyLogs[index] = row
        } else {
            data.dailyLogs.append(row)
        }
        await persistUpsert(
            row,
            table: "daily_logs",
            onConflict: "user_id,date",
            ownerID: ownerID
        )
    }

    func saveMorningWeight(_ weightKG: Double, on date: Date) async {
        guard weightKG.isFinite,
              (25...350).contains(weightKG),
              let ownerID = verifiedPersistenceOwnerID() else { return }
        let day = date.apexDateKey
        let existing = data.dailyLogs.first {
            $0.userID == ownerID && $0.date == day
        }
        let activityMode = data.activityLogs.contains {
            $0.userID == ownerID && $0.date == day
        } ? "precise" : "quick"
        let row = MorningCheckLogic.applyingWeight(
            weightKG,
            to: existing,
            userID: ownerID,
            date: day,
            activityMode: activityMode
        )
        await updateDailyLog(row, ownerID: ownerID)
    }

    /// Water naturally present in foods logged for the selected day. This is
    /// deliberately kept separate from `DailyLog.waterL`, which represents
    /// drinks and Apple Health dietary-water samples.
    func foodHydrationLiters(on date: Date) -> Double {
        let day = date.apexDateKey
        let mealIDs = Set(data.loggedMeals.lazy.filter { $0.localDate == day }.map(\.id))
        guard !mealIDs.isEmpty else { return 0 }
        let milliliters = data.loggedFoodEntries.lazy
            .filter { mealIDs.contains($0.mealID) }
            .reduce(0.0) { result, entry in
                if let measured = entry.waterML { return result + max(0, measured) }
                guard let per100 = entry.snapshotWaterML100 else { return result }
                return result + max(0, per100) * max(0, entry.equivalentAmount) / 100
            }
        return milliliters / 1_000
    }

    func hydrationResolution(on date: Date) -> HydrationDayResolution {
        guard let ownerID = verifiedPersistenceOwnerID() else {
            return HydrationDayResolution(
                drinkML: 0, foodML: 0, totalML: 0,
                composition: [], usesLegacyAggregate: false
            )
        }
        return hydrationResolution(ownerID: ownerID, on: date)
    }

    private func hydrationResolution(ownerID: UUID, on date: Date) -> HydrationDayResolution {
        let day = date.apexDateKey
        let legacy = data.dailyLogs.first { $0.userID == ownerID && $0.date == day }?.waterL ?? 0
        return HydrationLedger.resolve(
            ownerID: ownerID,
            date: day,
            events: data.hydrationEvents ?? [],
            legacyDrinkLiters: legacy
        )
    }

    var hydrationPreferences: HydrationAccountPreferences? {
        guard let ownerID = verifiedPersistenceOwnerID(),
              data.hydrationPreferences?.userID == ownerID else { return nil }
        return data.hydrationPreferences
    }

    func hydrationTargetResolution(
        on date: Date,
        plannedExerciseMinutes: Int? = nil,
        now: Date = .now
    ) -> HydrationTargetResolution {
        guard let profile else {
            return HydrationTargetPolicy.resolve(sex: "male", weightKG: 87)
        }
        let day = date.apexDateKey
        let today = now.apexDateKey
        let relation: HydrationTargetDateRelation = day < today ? .past : day > today ? .future : .today
        let wearable = WearableActivityRecord.history(
            from: data.settings?.addons["watch_activity_history"]
        ).last { $0.date == day }
        let logs = data.activityLogs.filter { $0.date == day }
        let loggedMinutes = logs.reduce(0) { $0 + max(0, $1.durationMinutes ?? 0) }
        let recordedMinutes = max(wearable?.exerciseMinutes ?? 0, loggedMinutes)
        let activeCalories = EnergyEngine.resolvedActiveCalories(
            wearableActiveCalories: wearable?.activeCalories,
            logs: logs
        )
        let preferences = hydrationPreferences
        let mode = preferences?.effectiveTargetMode ?? .automatic
        let planMinutes = plannedExerciseMinutes ?? plannedHydrationExerciseMinutes(on: date)
        let localHour = relation == .past
            ? 23
            : relation == .future ? 0 : Calendar.current.component(.hour, from: now)
        return HydrationTargetPolicy.resolve(
            sex: profile.sex,
            weightKG: profile.weightKG,
            mode: mode,
            customTargetML: preferences?.targetML,
            plannedExerciseMinutes: planMinutes,
            recordedExerciseMinutes: recordedMinutes,
            activeCalories: activeCalories,
            steps: wearable?.steps,
            dateRelation: relation,
            localHour: localHour
        )
    }

    private func plannedHydrationExerciseMinutes(on date: Date) -> Int? {
        let day = date.apexDateKey
        let fallback = SimpleHomeLogic.guidedProgramSlug(
            persona: profile?.persona,
            mainIsUsable: TrainingInduction.hasUsablePrescription(in: data, slug: "main"),
            transitionIsUsable: TrainingInduction.hasUsablePrescription(in: data, slug: "transition")
        )
        let slug: String
        if data.settings?.addons["training_induction"]?.objectValue != nil,
           TrainingPlanEngine.isInsideInductionWindow(data, slug: "transition", date: day),
           TrainingInduction.hasUsablePrescription(in: data, slug: "transition") {
            slug = "transition"
        } else if data.settings?.addons["training_induction"]?.objectValue != nil,
                  TrainingPlanEngine.isInsideInductionWindow(data, slug: "main", date: day),
                  TrainingInduction.hasUsablePrescription(in: data, slug: "main") {
            slug = "main"
        } else {
            slug = fallback
        }
        guard TrainingInduction.hasUsablePrescription(in: data, slug: slug) else { return nil }
        let weekday = Calendar.current.component(.weekday, from: date)
        let mondayBasedWeekday = weekday == 1 ? 7 : weekday - 1
        return TrainingInduction.visibleProgramDays(in: data, slug: slug)
            .first { $0.weekday == mondayBasedWeekday }?.estimatedMinutes
    }

    var hydrationPresets: [HydrationPreset] {
        guard let ownerID = verifiedPersistenceOwnerID() else { return [] }
        return (data.hydrationPresets ?? [])
            .filter { $0.userID == ownerID && $0.enabled }
            .sorted { ($0.sortOrder, $0.createdAt, $0.id) < ($1.sortOrder, $1.createdAt, $1.id) }
    }

    func logHydration(
        amountML: Int,
        kind: HydrationKind = .water,
        paletteToken: String = "aqua",
        iconToken: String = "drop.fill",
        source: HydrationSource = .iPhone,
        on date: Date = .now,
        eventID: UUID = UUID(),
        clientKey: String? = nil
    ) async {
        guard amountML > 0, amountML <= 10_000,
              let ownerID = verifiedPersistenceOwnerID() else { return }
        let accountToken = accountGeneration.token
        let day = date.apexDateKey
        await materializeLegacyHydrationIfNeeded(ownerID: ownerID, date: date)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        let occurred = hydrationOccurrence(on: date)
        let now = Date().ISO8601Format()
        var event = HydrationEvent(
            id: eventID,
            userID: ownerID,
            clientIdempotencyKey: clientKey ?? "\(source.rawValue):\(eventID.uuidString.lowercased())",
            localDate: day,
            occurredAt: occurred.ISO8601Format(),
            amountML: amountML,
            kind: kind,
            paletteToken: paletteToken,
            iconToken: iconToken,
            source: source,
            healthKitSampleID: nil,
            createdAt: now,
            updatedAt: now
        )
        upsertHydrationEventLocally(event)
        await persistUpsert(
            event,
            table: "hydration_events",
            onConflict: "user_id,client_idempotency_key",
            ownerID: ownerID
        )
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }

        if source == .iPhone, occurred <= Date().addingTimeInterval(60) {
            do {
                event.healthKitSampleID = try await HealthKitManager.shared.saveWater(
                    liters: Double(amountML) / 1_000,
                    date: occurred,
                    eventID: eventID,
                    ownerID: ownerID,
                    kind: kind,
                    paletteToken: paletteToken,
                    iconToken: iconToken
                )
                guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
                event.updatedAt = Date().ISO8601Format()
                upsertHydrationEventLocally(event)
                await persistUpsert(
                    event,
                    table: "hydration_events",
                    onConflict: "user_id,client_idempotency_key",
                    ownerID: ownerID,
                    surfacePermanentFailure: false
                )
                guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
            } catch {
                if hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) {
                    HealthKitManager.shared.message = error.localizedDescription
                }
            }
        }
        await mirrorHydrationAggregate(ownerID: ownerID, on: date)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        publishHydrationState()
    }

    func logHydration(preset: HydrationPreset, on date: Date = .now) async {
        guard preset.userID == verifiedPersistenceOwnerID() else { return }
        await logHydration(
            amountML: preset.amountML,
            kind: preset.kind,
            paletteToken: preset.paletteToken,
            iconToken: preset.iconToken,
            on: date
        )
    }

    func deleteHydrationEvent(_ event: HydrationEvent, on date: Date) async {
        guard let ownerID = verifiedPersistenceOwnerID(), event.userID == ownerID,
              event.source != .healthKitExternal, event.source != .food else { return }
        let accountToken = accountGeneration.token
        data.hydrationEvents?.removeAll { $0.id == event.id && $0.userID == ownerID }
        await persistDelete(table: "hydration_events", id: event.id, ownerID: ownerID)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        if event.source == .iPhone {
            try? await HealthKitManager.shared.deleteWater(eventID: event.id, date: date)
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }
        await mirrorHydrationAggregate(ownerID: ownerID, on: date)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        publishHydrationState()
    }

    func saveHydrationPreset(_ preset: HydrationPreset) async {
        guard let ownerID = verifiedPersistenceOwnerID(), preset.userID == ownerID else { return }
        let accountToken = accountGeneration.token
        var rows = data.hydrationPresets ?? []
        rows.removeAll { $0.id == preset.id && $0.userID == ownerID }
        rows.append(preset)
        data.hydrationPresets = rows
        await persistUpsert(preset, table: "hydration_presets", onConflict: "user_id,id", ownerID: ownerID)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        publishHydrationState()
    }

    func deleteHydrationPreset(_ preset: HydrationPreset) async {
        guard let ownerID = verifiedPersistenceOwnerID(), preset.userID == ownerID else { return }
        let accountToken = accountGeneration.token
        data.hydrationPresets?.removeAll { $0.id == preset.id && $0.userID == ownerID }
        await persistDelete(table: "hydration_presets", id: preset.id, ownerID: ownerID)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        publishHydrationState()
    }

    func saveHydrationPreferences(_ preferences: HydrationAccountPreferences) async {
        guard let ownerID = verifiedPersistenceOwnerID(), preferences.userID == ownerID else { return }
        let accountToken = accountGeneration.token
        data.hydrationPreferences = preferences
        await persistUpsert(
            preferences,
            table: "hydration_preferences",
            onConflict: "user_id",
            ownerID: ownerID
        )
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        publishHydrationState()
    }

    func setActivityLevel(_ level: ActivityLevel) async {
        guard var profile else { return }
        profile.activityLevel = level
        profile.updatedAt = Date().ISO8601Format()
        data.profile = profile
        await persistUpsert(profile, table: "profile", onConflict: "user_id")
    }

    func setGoal(_ goal: Goal) async {
        guard var profile else { return }
        profile.goal = goal
        profile.updatedAt = Date().ISO8601Format()
        data.profile = profile
        await persistUpsert(profile, table: "profile", onConflict: "user_id")
    }

    func updateSettings(_ transform: (inout UserSettings) -> Void) async {
        guard let profile, var settings = data.settings else { return }
        settings = settings.rebound(to: profile.userID)
        transform(&settings)
        data.settings = settings
        await persistUpsert(settings, table: "settings", onConflict: "user_id")
    }

    func setInterfaceMode(_ mode: PortalUIMode) {
        /* Simple and Advanced swap the *root* of the navigation stack, so
           switching while somewhere pushed -- Nutrition, Training, anywhere --
           changed the screen underneath and left the pushed one on top. From
           the outside the toggle simply did nothing. Returning to the root is
           what the switch is asking for: show me that mode. */
        navigationPath = []
        guard var settings = data.settings else { return }
        let ownerID = profile?.userID ?? settings.userID
        guard TrainingInduction.belongsToAccount(data, userID: ownerID) else { return }
        settings = settings.rebound(to: ownerID)
        settings.addons["uiMode"] = .string(mode.rawValue)
        /* Root navigation must change in the button action itself. Deferring
           this mutation to a Task lets a dismissed briefing tear down before
           the task runs, visibly returning to the old Advanced root. */
        data.settings = settings
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-first-run") { return }
        #endif
        let accountToken = accountGeneration.token
        Task { [weak self] in
            guard let self,
                  self.accountGeneration.accepts(accountToken),
                  self.verifiedPersistenceOwnerID(ownerID) == ownerID else { return }
            await self.persistUpsert(
                settings,
                table: "settings",
                onConflict: "user_id",
                ownerID: ownerID
            )
        }
    }

    static func waterWatermarkKey(_ date: String, userID: UUID) -> String {
        "apex.hk.water.external.\(userID.uuidString.lowercased()).\(date)"
    }

    /*
     * Every water change flows through here so the HealthKit watermark stays
     * consistent. iPhone additions are tagged as APEX mirrors and excluded
     * from the external total, while Watch and third-party water flows back as
     * a reversible delta. A local correction therefore stays corrected.
    */
    @discardableResult
    func adjustWater(deltaLiters: Double, on date: Date) async -> Double {
        let task = hydrationMutationQueue.enqueue { [weak self] in
            guard let self else { return 0 }
            return await self.performWaterAdjustment(deltaLiters: deltaLiters, on: date)
        }
        return await task.value
    }

    private func performWaterAdjustment(deltaLiters: Double, on date: Date) async -> Double {
        guard let ownerID = verifiedPersistenceOwnerID() else { return 0 }
        let accountToken = accountGeneration.token
        guard deltaLiters.isFinite, deltaLiters != 0 else {
            return Double(hydrationResolution(ownerID: ownerID, on: date).drinkML) / 1_000
        }
        if deltaLiters > 0 {
            await logHydration(amountML: Int((deltaLiters * 1_000).rounded()), on: date)
        } else {
            await reduceHydration(byML: Int((-deltaLiters * 1_000).rounded()), on: date)
        }
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return 0 }
        return Double(hydrationResolution(ownerID: ownerID, on: date).drinkML) / 1_000
    }

    func setWaterTotal(_ liters: Double, on date: Date) async {
        let current = Double(hydrationResolution(on: date).drinkML) / 1_000
        await adjustWater(deltaLiters: liters - current, on: date)
    }

    private func ensureHydrationDefaults(ownerID: UUID) async {
        let accountToken = accountGeneration.token
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        let now = Date().ISO8601Format()
        if (data.hydrationPresets ?? []).filter({ $0.userID == ownerID }).isEmpty {
            let presets = HydrationLedger.defaultPresetTemplates.map { template in
                HydrationPreset(
                    id: APEXStableID.scopedUUID(
                        namespace: "hydration-preset",
                        date: template.id.uuidString.lowercased(),
                        userID: ownerID
                    ),
                    userID: ownerID,
                    name: template.name,
                    amountML: template.amountML,
                    kind: template.kind,
                    paletteToken: template.paletteToken,
                    iconToken: template.iconToken,
                    sortOrder: template.sortOrder,
                    enabled: template.enabled,
                    createdAt: now,
                    updatedAt: now
                )
            }
            data.hydrationPresets = (data.hydrationPresets ?? []) + presets
            for preset in presets {
                await persistUpsert(
                    preset,
                    table: "hydration_presets",
                    onConflict: "user_id,id",
                    ownerID: ownerID,
                    surfacePermanentFailure: false
                )
                guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
            }
        }
        if data.hydrationPreferences?.userID != ownerID {
            let preferences = HydrationAccountPreferences(
                userID: ownerID,
                targetML: 2_750,
                targetMode: HydrationTargetMode.automatic.rawValue,
                displayUnit: "liters",
                remindersEnabled: false,
                reminderIntervalMinutes: 90,
                quietHoursStartMinutes: (21 * 60) + 30,
                quietHoursEndMinutes: 8 * 60,
                showsPresetNames: true,
                confirmationHaptics: true,
                motionIntensity: "subtle",
                createdAt: now,
                updatedAt: now
            )
            data.hydrationPreferences = preferences
            await persistUpsert(
                preferences,
                table: "hydration_preferences",
                onConflict: "user_id",
                ownerID: ownerID,
                surfacePermanentFailure: false
            )
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }
    }

    private func materializeLegacyHydrationIfNeeded(ownerID: UUID, date: Date) async {
        let accountToken = accountGeneration.token
        let day = date.apexDateKey
        let events = data.hydrationEvents ?? []
        guard !events.contains(where: {
            $0.userID == ownerID && $0.localDate == day && $0.kind != .food
        }), let legacy = data.dailyLogs.first(where: {
            $0.userID == ownerID && $0.date == day
        })?.waterL, legacy > 0 else { return }
        let anchor = hydrationOccurrence(on: date)
        let migration = HydrationLedger.legacyMigration(
            legacyDrinkLiters: legacy,
            previouslyImportedLiters: defaults.object(
                forKey: Self.waterWatermarkKey(day, userID: ownerID)
            ) as? Double,
            anchor: anchor
        )
        guard migration.baselineML > 0 else { return }
        let id = APEXStableID.scopedUUID(namespace: "hydration-legacy", date: day, userID: ownerID)
        let now = Date().ISO8601Format()
        let event = HydrationEvent(
            id: id,
            userID: ownerID,
            clientIdempotencyKey: "legacy:\(day)",
            localDate: day,
            occurredAt: anchor.ISO8601Format(),
            amountML: migration.baselineML,
            kind: .legacy,
            paletteToken: migration.importCutoff == nil
                ? HydrationLedger.legacyAdjustedPalette
                : HydrationLedger.legacyAnchorPalette,
            iconToken: "drop.circle",
            source: .legacy,
            healthKitSampleID: nil,
            createdAt: now,
            updatedAt: now
        )
        upsertHydrationEventLocally(event)
        await persistUpsert(
            event,
            table: "hydration_events",
            onConflict: "user_id,client_idempotency_key",
            ownerID: ownerID,
            surfacePermanentFailure: false
        )
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        publishHydrationState()
    }

    private func hydrationOccurrence(on date: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return .now }
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .hour, value: 12, to: start) ?? date
    }

    private func upsertHydrationEventLocally(_ event: HydrationEvent) {
        var rows = data.hydrationEvents ?? []
        rows = HydrationLedger.merge(current: rows, incoming: [event])
        data.hydrationEvents = rows
    }

    private func mirrorHydrationAggregate(ownerID: UUID, on date: Date) async {
        let accountToken = accountGeneration.token
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        let day = date.apexDateKey
        let resolved = hydrationResolution(ownerID: ownerID, on: date)
        let liters = Double(resolved.drinkML) / 1_000
        let existing = data.dailyLogs.first { $0.userID == ownerID && $0.date == day }
        guard abs((existing?.waterL ?? 0) - liters) > 0.000_5 || existing == nil else { return }
        var row = existing ?? DailyLog(
            id: APEXStableID.scopedUUID(namespace: "daily-log", date: day, userID: ownerID),
            userID: ownerID, date: day,
            kcal: nil, proteinG: nil, fatG: nil, carbsG: nil, waterL: 0,
            estimatedTDEE: nil, computedPAL: nil,
            activityMode: data.activityLogs.contains { $0.date == day } ? "precise" : "quick",
            weightKG: nil
        )
        row.waterL = liters
        await updateDailyLog(row, ownerID: ownerID)
    }

    private func reduceHydration(byML amountML: Int, on date: Date) async {
        guard amountML > 0, let ownerID = verifiedPersistenceOwnerID() else { return }
        let accountToken = accountGeneration.token
        let day = date.apexDateKey
        await materializeLegacyHydrationIfNeeded(ownerID: ownerID, date: date)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        let plan = HydrationLedger.reductionPlan(
            ownerID: ownerID,
            date: day,
            events: data.hydrationEvents ?? [],
            amountML: amountML,
            updatedAt: Date().ISO8601Format()
        )
        guard !plan.deletedEvents.isEmpty || !plan.replacements.isEmpty else { return }

        /* Stage the complete ledger and its legacy mirror together before the
           first network suspension. Otherwise deleting the final event exposes
           the old DailyLog aggregate, which materialization can mistake for a
           fresh litre and add back during a partial reduction. */
        data.hydrationEvents = plan.resultingEvents
        let existing = data.dailyLogs.first { $0.userID == ownerID && $0.date == day }
        var aggregateRow = existing ?? DailyLog(
            id: APEXStableID.scopedUUID(namespace: "daily-log", date: day, userID: ownerID),
            userID: ownerID, date: day,
            kcal: nil, proteinG: nil, fatG: nil, carbsG: nil, waterL: 0,
            estimatedTDEE: nil, computedPAL: nil,
            activityMode: data.activityLogs.contains { $0.date == day } ? "precise" : "quick",
            weightKG: nil
        )
        aggregateRow.waterL = Double(plan.drinkML) / 1_000
        if let index = data.dailyLogs.firstIndex(where: { $0.id == aggregateRow.id }) {
            data.dailyLogs[index] = aggregateRow
        } else {
            data.dailyLogs.append(aggregateRow)
        }
        publishHydrationState()

        for event in plan.deletedEvents {
            await persistDelete(table: "hydration_events", id: event.id, ownerID: ownerID)
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
            if event.source == .iPhone {
                try? await HealthKitManager.shared.deleteWater(eventID: event.id, date: date)
                guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
            }
        }

        for pair in plan.replacements {
            var replacement = pair.replacement
            if pair.original.source == .iPhone {
                try? await HealthKitManager.shared.deleteWater(eventID: pair.original.id, date: date)
                guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
                let occurred = ISO8601DateFormatter().date(from: pair.original.occurredAt)
                    ?? hydrationOccurrence(on: date)
                if occurred <= Date().addingTimeInterval(60) {
                    do {
                        replacement.healthKitSampleID = try await HealthKitManager.shared.saveWater(
                            liters: Double(replacement.amountML) / 1_000,
                            date: occurred,
                            eventID: replacement.id,
                            ownerID: ownerID,
                            kind: replacement.kind,
                            paletteToken: replacement.paletteToken,
                            iconToken: replacement.iconToken
                        )
                        replacement.updatedAt = Date().ISO8601Format()
                        upsertHydrationEventLocally(replacement)
                    } catch {
                        if hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) {
                            HealthKitManager.shared.message = error.localizedDescription
                        }
                    }
                }
            }
            await persistUpsert(
                replacement,
                table: "hydration_events",
                onConflict: "user_id,client_idempotency_key",
                ownerID: ownerID
            )
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }

        await persistUpsert(
            aggregateRow,
            table: "daily_logs",
            onConflict: "user_id,date",
            ownerID: ownerID
        )
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        publishHydrationState()
    }

    private func syncFoodHydrationEvent(on date: Date, ownerID: UUID) async {
        let accountToken = accountGeneration.token
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        let day = date.apexDateKey
        let key = "food:\(day)"
        let amountML = Int((foodHydrationLiters(on: date) * 1_000).rounded())
        let existing = (data.hydrationEvents ?? []).first {
            $0.userID == ownerID && $0.clientIdempotencyKey == key
        }
        guard amountML > 0 else {
            if let existing {
                data.hydrationEvents?.removeAll { $0.id == existing.id }
                await persistDelete(table: "hydration_events", id: existing.id, ownerID: ownerID)
                guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
                publishHydrationState()
            }
            return
        }
        if existing?.amountML == amountML { return }
        let now = Date().ISO8601Format()
        let event = HydrationEvent(
            id: existing?.id ?? APEXStableID.scopedUUID(
                namespace: "hydration-food", date: day, userID: ownerID
            ),
            userID: ownerID,
            clientIdempotencyKey: key,
            localDate: day,
            occurredAt: hydrationOccurrence(on: date).ISO8601Format(),
            amountML: amountML,
            kind: .food,
            paletteToken: "food",
            iconToken: "fork.knife",
            source: .food,
            healthKitSampleID: nil,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        upsertHydrationEventLocally(event)
        await persistUpsert(
            event,
            table: "hydration_events",
            onConflict: "user_id,client_idempotency_key",
            ownerID: ownerID,
            surfacePermanentFailure: false
        )
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        publishHydrationState()
    }

    private func reconcileHealthHydration(_ snapshot: HealthSnapshot, ownerID: UUID) async {
        guard snapshot.importableDietaryWaterL != nil else { return }
        let accountToken = accountGeneration.token
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken),
              let date = ISO8601DateFormatter.apexDateOnly.date(from: snapshot.date) else { return }
        await materializeLegacyHydrationIfNeeded(ownerID: ownerID, date: date)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        let imported = snapshot.hydrationSamples.filter {
            ($0.source == .apexWatch || $0.source == .external)
                && hydrationHealthSampleBelongsToOwner($0, ownerID: ownerID)
                && HydrationLedger.shouldImportHealthSample(
                    occurredAt: $0.occurredAt,
                    ownerID: ownerID,
                    date: snapshot.date,
                    events: data.hydrationEvents ?? []
                )
        }
        let deleted = HydrationLedger.eventsDeletedByHealthKit(
            events: data.hydrationEvents ?? [],
            ownerID: ownerID,
            deletedSampleIDs: snapshot.deletedHydrationSampleIDs
        )
        for event in deleted {
            data.hydrationEvents?.removeAll { $0.id == event.id }
            await persistDelete(table: "hydration_events", id: event.id, ownerID: ownerID)
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }

        for sample in imported {
            let source: HydrationSource = sample.source == .apexWatch ? .watch : .healthKitExternal
            let key = "healthkit:\(sample.id.uuidString.lowercased())"
            let existing = (data.hydrationEvents ?? []).first {
                $0.userID == ownerID && $0.clientIdempotencyKey == key
            }
            let amountML = Int((sample.liters * 1_000).rounded())
            guard amountML > 0 else { continue }
            let kind: HydrationKind = source == .healthKitExternal ? .external : sample.kind
            if existing?.amountML == amountML, existing?.kind == kind,
               existing?.paletteToken == sample.paletteToken { continue }
            let now = Date().ISO8601Format()
            let event = HydrationEvent(
                id: existing?.id ?? APEXStableID.scopedUUID(
                    namespace: "hydration-healthkit",
                    date: sample.id.uuidString.lowercased(),
                    userID: ownerID
                ),
                userID: ownerID,
                clientIdempotencyKey: key,
                localDate: snapshot.date,
                occurredAt: sample.occurredAt.ISO8601Format(),
                amountML: amountML,
                kind: kind,
                paletteToken: source == .healthKitExternal ? "external" : sample.paletteToken,
                iconToken: source == .healthKitExternal ? "heart.fill" : sample.iconToken,
                source: source,
                healthKitSampleID: sample.id,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            upsertHydrationEventLocally(event)
            await persistUpsert(
                event,
                table: "hydration_events",
                onConflict: "user_id,client_idempotency_key",
                ownerID: ownerID,
                surfacePermanentFailure: false
            )
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }
        await mirrorHydrationAggregate(ownerID: ownerID, on: date)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        publishHydrationState()
    }

    private func hydrationHealthSampleBelongsToOwner(
        _ sample: HealthHydrationSample,
        ownerID: UUID
    ) -> Bool {
        if let explicitOwnerID = sample.ownerID { return explicitOwnerID == ownerID }
        let key = "apex.hk.hydration.claim.\(sample.id.uuidString.lowercased())"
        if let claimed = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) {
            return claimed == ownerID
        }
        defaults.set(ownerID.uuidString.lowercased(), forKey: key)
        return true
    }

    private func publishHydrationState() {
        guard let ownerID = verifiedPersistenceOwnerID() else { return }
        let date = Date()
        let day = date.apexDateKey
        let legacy = data.dailyLogs.first { $0.userID == ownerID && $0.date == day }?.waterL ?? 0
        var preferences = data.hydrationPreferences.map(WatchHydrationPreferences.init(account:)) ?? .default
        let target = hydrationTargetResolution(on: date)
        preferences.targetMode = target.mode
        preferences.targetLiters = Double(target.targetML) / 1_000
        let snapshot = HydrationCompanionSnapshot.make(
            ownerID: ownerID,
            date: day,
            events: data.hydrationEvents ?? [],
            presets: data.hydrationPresets ?? [],
            preferences: preferences,
            legacyDrinkLiters: legacy,
            revision: Date().ISO8601Format()
        )
        hydrationConnectivity.publish(snapshot)
    }

    private func beginHydrationMutation(_ mutation: HydrationCompanionMutation) -> Bool {
        let key = "apex.watch.hydration.processed.\(mutation.ownerID.uuidString.lowercased())"
        let processed = defaults.stringArray(forKey: key) ?? []
        let mutationID = mutation.id.uuidString.lowercased()
        guard !processed.contains(mutationID), !hydrationMutationsInFlight.contains(mutation.id) else {
            return false
        }
        hydrationMutationsInFlight.insert(mutation.id)
        return true
    }

    private func finishHydrationMutation(_ mutation: HydrationCompanionMutation) {
        hydrationMutationsInFlight.remove(mutation.id)
        let key = "apex.watch.hydration.processed.\(mutation.ownerID.uuidString.lowercased())"
        var processed = defaults.stringArray(forKey: key) ?? []
        let mutationID = mutation.id.uuidString.lowercased()
        guard !processed.contains(mutationID) else { return }
        processed.append(mutationID)
        defaults.set(Array(processed.suffix(512)), forKey: key)
    }

    private func hydrationTombstoneRevision(eventID: UUID, ownerID: UUID) -> String? {
        defaults.string(forKey: hydrationTombstoneKey(eventID: eventID, ownerID: ownerID))
    }

    private func recordHydrationTombstone(eventID: UUID, ownerID: UUID, revision: String) {
        let key = hydrationTombstoneKey(eventID: eventID, ownerID: ownerID)
        if let current = defaults.string(forKey: key), revision <= current { return }
        defaults.set(revision, forKey: key)
    }

    private func hydrationTombstoneKey(eventID: UUID, ownerID: UUID) -> String {
        "apex.watch.hydration.tombstone.\(ownerID.uuidString.lowercased()).\(eventID.uuidString.lowercased())"
    }

    private func handleHydrationMutation(_ mutation: HydrationCompanionMutation) async {
        guard let ownerID = verifiedPersistenceOwnerID(), mutation.belongs(to: ownerID),
              beginHydrationMutation(mutation) else { return }
        defer { finishHydrationMutation(mutation) }
        let accountToken = accountGeneration.token
        switch mutation.action {
        case .upsertEvent:
            guard let event = mutation.event,
                  HydrationMutationOrdering.accepts(
                      event: event,
                      afterTombstoneRevision: hydrationTombstoneRevision(
                          eventID: event.healthKitSampleID ?? event.id,
                          ownerID: ownerID
                      )
                  ) else { return }
            let existing = (data.hydrationEvents ?? []).first {
                $0.userID == ownerID && $0.clientIdempotencyKey == event.clientIdempotencyKey
            }
            if existing != event {
                upsertHydrationEventLocally(event)
                await persistUpsert(
                    event,
                    table: "hydration_events",
                    onConflict: "user_id,client_idempotency_key",
                    ownerID: ownerID,
                    surfacePermanentFailure: false
                )
                guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
            }
            if let date = ISO8601DateFormatter.apexDateOnly.date(from: event.localDate) {
                await mirrorHydrationAggregate(ownerID: ownerID, on: date)
                guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
            }
        case .deleteEvent:
            guard let eventID = mutation.eventID else { return }
            recordHydrationTombstone(eventID: eventID, ownerID: ownerID, revision: mutation.createdAt)
            guard let event = (data.hydrationEvents ?? []).first(where: {
                $0.userID == ownerID && ($0.id == eventID || $0.healthKitSampleID == eventID)
            }) else { return }
            guard !HydrationMutationOrdering.accepts(
                event: event,
                afterTombstoneRevision: mutation.createdAt
            ) else { return }
            data.hydrationEvents?.removeAll { $0.userID == ownerID && $0.id == event.id }
            await persistDelete(table: "hydration_events", id: event.id, ownerID: ownerID)
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
            if let date = ISO8601DateFormatter.apexDateOnly.date(from: event.localDate) {
                await mirrorHydrationAggregate(ownerID: ownerID, on: date)
                guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
            }
        case .updatePreferences:
            guard let preferences = mutation.preferences,
                  HydrationMutationOrdering.acceptsPreference(
                      incomingRevision: mutation.createdAt,
                      currentRevision: data.hydrationPreferences?.updatedAt
                  ) else { return }
            await saveHydrationPreferences(
                preferences.accountRow(ownerID: ownerID, existing: data.hydrationPreferences)
            )
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }
        publishHydrationState()
    }

    func applyHealthSnapshot(_ snapshot: HealthSnapshot) async {
        guard let profile else { return }
        let ownerID = profile.userID
        let accountToken = accountGeneration.token
        if HealthKitManager.shared.waterWriteState == .authorized,
           let resolvedDate = ISO8601DateFormatter.apexDateOnly.date(from: snapshot.date) {
            try? await HealthKitManager.shared.syncFoodWater(
                liters: foodHydrationLiters(on: resolvedDate),
                on: resolvedDate,
                accountID: profile.userID
            )
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }
        if snapshot.weightKG != nil || snapshot.vo2Max != nil || snapshot.restingHeartRate != nil {
            let existing = data.healthMetrics.first { $0.date == snapshot.date }
            let metric = HealthMetric(
                id: existing?.id ?? UUID(),
                userID: profile.userID,
                date: snapshot.date,
                weightKG: snapshot.weightKG ?? existing?.weightKG,
                vo2Max: snapshot.vo2Max ?? existing?.vo2Max,
                restingHeartRate: snapshot.restingHeartRate ?? existing?.restingHeartRate
            )
            data.healthMetrics.removeAll { $0.id == metric.id }
            data.healthMetrics.append(metric)
            await persistUpsert(metric, table: "health_metrics", onConflict: "user_id,date")
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }

        await reconcileHealthHydration(snapshot, ownerID: ownerID)
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }

        if snapshot.steps != nil || snapshot.activeEnergyKcal != nil || snapshot.exerciseMinutes != nil {
            let wearable = WearableActivityRecord(
                date: snapshot.date,
                steps: Int((snapshot.steps ?? 0).rounded()),
                activeCalories: Int((snapshot.activeEnergyKcal ?? 0).rounded()),
                exerciseMinutes: Int((snapshot.exerciseMinutes ?? 0).rounded()),
                source: "apple_health",
                updatedAt: Date().ISO8601Format()
            )
            await saveWearableActivity(wearable, automaticallyApply: snapshot.date == Date().apexDateKey)
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }

        if snapshot.sleepDurationHours != nil || snapshot.heartRateVariabilityMS != nil {
            await updateSettings { settings in
                settings.addons["apple_recovery_context"] = .object([
                    "date": .string(snapshot.date),
                    "sleep_duration_hours": snapshot.sleepDurationHours.map(JSONValue.number) ?? .null,
                    "heart_rate_variability_ms": snapshot.heartRateVariabilityMS.map(JSONValue.number) ?? .null,
                    "resting_heart_rate": snapshot.restingHeartRate.map(JSONValue.number) ?? .null,
                    "source": .string("apple_health"),
                    "updated_at": .string(Date().ISO8601Format())
                ])
            }
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }

        for workout in snapshot.workouts {
            await importHealthWorkoutIfNeeded(workout)
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }
    }

    func saveWearableActivity(_ record: WearableActivityRecord, automaticallyApply: Bool) async {
        await updateSettings { settings in
            var history = WearableActivityRecord.history(from: settings.addons["watch_activity_history"])
            history.removeAll { $0.date == record.date }
            history.append(record)
            history.sort { $0.date < $1.date }
            settings.addons["watch_activity_history"] = .array(history.suffix(730).map(\.jsonValue))
        }
        if record.date == Date().apexDateKey { publishHydrationState() }
        guard automaticallyApply,
              data.activityLogs.contains(where: { $0.date == record.date }) == false else { return }
        let suggested = WearableActivityEngine.suggestedLevel(
            persona: profile?.persona ?? .constantine,
            steps: record.steps,
            activeCalories: record.activeCalories,
            exerciseMinutes: record.exerciseMinutes
        )
        await setActivityLevel(suggested)
    }

    func addActivity(
        type: ActivityType,
        date: Date,
        quantity: Double = 1,
        durationMinutes: Int? = nil,
        distanceKM: Double? = nil,
        watchKcal: Double? = nil,
        source: String = "manual"
    ) async {
        guard let profile else { return }
        let now = Date().ISO8601Format()
        let log = ActivityLog(
            id: UUID(),
            userID: profile.userID,
            date: date.apexDateKey,
            typeID: type.id,
            quantity: quantity,
            durationMinutes: durationMinutes,
            distanceKM: distanceKM,
            watchKcal: watchKcal,
            computedKcal: EnergyEngine.blockCalories(
                type: type,
                quantity: quantity,
                durationMinutes: durationMinutes,
                distanceKM: distanceKM,
                watchKcal: watchKcal,
                weightKG: profile.weightKG
            ),
            source: source,
            reconciled: false,
            createdAt: now,
            updatedAt: now
        )
        data.activityLogs.append(log)
        await persistUpsert(log, table: "activity_logs")
    }

    func prefillEventActivitiesIfNeeded(for date: Date) async {
        guard let profile else { return }
        let day = date.apexDateKey
        let event = data.events.first {
            $0.userID == profile.userID
                && $0.type == "filming_championship"
                && $0.startDate <= day
                && $0.endDate >= day
        }
        guard let event else { return }
        guard data.activityLogs.contains(where: { $0.date == day }) == false else { return }

        let marker = "apex.event-prefill.\(profile.userID.uuidString).\(event.id.uuidString).\(day)"
        guard defaults.bool(forKey: marker) == false else { return }
        defaults.set(true, forKey: marker)

        if let filming = data.activityTypes.first(where: { $0.id == "gimbal-filming" }) {
            await addActivity(
                type: filming,
                date: date,
                durationMinutes: 8 * 60,
                source: "event_prefill"
            )
        }
        if let travel = data.activityTypes.first(where: { $0.id == "travel-day" }) {
            await addActivity(
                type: travel,
                date: date,
                durationMinutes: 2 * 60,
                source: "event_prefill"
            )
        }
    }

    func removeActivity(_ log: ActivityLog) async {
        data.activityLogs.removeAll { $0.id == log.id }
        await persistDelete(table: "activity_logs", id: log.id)
    }

    func clearActivities(on date: Date) async {
        let logs = data.activityLogs.filter { $0.date == date.apexDateKey }
        for log in logs { await removeActivity(log) }
    }

    func repeatYesterday(onto date: Date) async {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) else { return }
        let previous = data.activityLogs.filter { $0.date == yesterday.apexDateKey }
        for log in previous {
            guard let type = data.activityTypes.first(where: { $0.id == log.typeID }) else { continue }
            await addActivity(
                type: type,
                date: date,
                quantity: log.quantity,
                durationMinutes: log.durationMinutes,
                distanceKM: log.distanceKM,
                watchKcal: log.watchKcal,
                source: "manual"
            )
        }
    }

    func finalizeActivityDay(_ date: Date, targets: NutritionTargets) async {
        guard let profile else { return }
        let day = date.apexDateKey
        let indices = data.activityLogs.indices.filter { data.activityLogs[$0].date == day }
        for index in indices {
            data.activityLogs[index].reconciled = true
            data.activityLogs[index].updatedAt = Date().ISO8601Format()
            await persistUpsert(data.activityLogs[index], table: "activity_logs")
        }
        let existing = data.dailyLogs.first { $0.date == day }
        let row = DailyLog(
            id: existing?.id ?? UUID(),
            userID: profile.userID,
            date: day,
            kcal: existing?.kcal,
            proteinG: existing?.proteinG,
            fatG: existing?.fatG,
            carbsG: existing?.carbsG,
            waterL: existing?.waterL ?? 0,
            estimatedTDEE: targets.tdee,
            computedPAL: targets.pal,
            activityMode: indices.isEmpty ? "quick" : "precise",
            weightKG: existing?.weightKG ?? profile.weightKG,
            nutritionSource: existing?.nutritionSource ?? "manual",
            manualKcal: existing?.manualKcal,
            manualProteinG: existing?.manualProteinG,
            manualFatG: existing?.manualFatG,
            manualCarbsG: existing?.manualCarbsG
        )
        await updateDailyLog(row)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /* A provider almost never publishes water, so it is estimated on the way in.
       Without this a scanned food silently contributes nothing to hydration. */
    func lookupFood(barcode: String) async throws -> FoodLookupEnvelope {
        let ownerID = verifiedPersistenceOwnerID()
        let accountToken = accountGeneration.token
        let envelope = try await service.lookupFood(barcode: barcode)
        let resolved = FoodLookupEnvelope(
            state: envelope.state,
            source: envelope.source,
            food: envelope.food.map(FoodHydration.resolved),
            results: envelope.results?.map(FoodHydration.resolved),
            message: envelope.message
        )
        if let ownerID, hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken),
           let found = resolved.food {
            data.foods.removeAll { $0.id.lowercased() == found.id.lowercased() }
            data.foods.insert(found, at: 0)
            await saveLocalSnapshot()
        }
        return resolved
    }

    func searchFoods(query: String) async throws -> [Food] {
        let remote = try await service.searchFoods(query: query)
        return (remote.results ?? []).map(FoodHydration.resolved)
    }

    /// Saves a complete meal in one atomic Supabase operation. The same RPC is
    /// used by the web client, so edits, ordering and nutrition totals converge
    /// across both clients instead of creating one row per food.
    func saveStructuredMeal(_ draft: MealComposerDraft) async throws {
        guard let profile else { throw APEXServiceError.configurationMissing }
        let validItems = draft.items.filter { $0.equivalentAmount > 0 }
        guard validItems.isEmpty == false else { throw APEXServiceError.incompleteFood }

        let key = draft.clientIdempotencyKey
        let loggedAs = MealLogKind.normalized(draft.loggedAs)
        let request = StructuredMealRequest(
            id: draft.id,
            localDate: draft.localDate,
            mealSlot: draft.mealSlot,
            displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? draft.mealSlot.capitalized
                : draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            sourcePresetID: draft.sourcePresetID,
            sourcePlannedMealID: draft.sourcePlannedMealID,
            loggedAt: draft.finishedAt.ISO8601Format(),
            clientIdempotencyKey: key,
            loggedAs: loggedAs,
            replaceMealID: draft.replaceMealID
        )
        let entryRequests = validItems.enumerated().map { index, item in
            StructuredFoodEntryRequest(
                id: item.id,
                foodID: item.foodID,
                sortOrder: index,
                snapshotName: item.name,
                snapshotBrand: item.brand,
                snapshotPreparationState: item.preparationState,
                snapshotNutritionBasis: item.nutritionBasis,
                snapshotKcal100: item.kcal100,
                snapshotProtein100: item.protein100,
                snapshotCarbs100: item.carbs100,
                snapshotFat100: item.fat100,
                snapshotFibre100: item.fibre100,
                snapshotSugar100: item.sugar100,
                snapshotSaturatedFat100: item.saturatedFat100,
                snapshotSalt100: item.salt100,
                snapshotWaterML100: item.waterML100,
                snapshotWaterBasis: item.waterBasis ?? "unknown",
                snapshotWaterSourceID: item.waterSourceID,
                quantity: item.quantity,
                unit: item.unit,
                equivalentAmount: item.equivalentAmount
            )
        }
        let totals = draft.totals
        let localMeal = LoggedMeal(
            id: draft.id,
            userID: profile.userID,
            localDate: draft.localDate,
            mealSlot: draft.mealSlot,
            displayName: request.displayName,
            sourcePresetID: draft.sourcePresetID,
            sourcePlannedMealID: draft.sourcePlannedMealID,
            loggedAt: request.loggedAt,
            clientIdempotencyKey: key,
            loggedAs: loggedAs,
            totalKcal: totals.kcal.rounded(),
            totalProteinG: totals.proteinG,
            totalCarbsG: totals.carbsG,
            totalFatG: totals.fatG
        )
        let localEntries = validItems.enumerated().map { index, item in
            let nutrients = item.nutrients
            return LoggedFoodEntry(
                id: item.id,
                mealID: draft.id,
                userID: profile.userID,
                foodID: item.foodID,
                sortOrder: index,
                snapshotName: item.name,
                snapshotBrand: item.brand,
                snapshotPreparationState: item.preparationState,
                snapshotNutritionBasis: item.nutritionBasis,
                snapshotKcal100: item.kcal100,
                snapshotProtein100: item.protein100,
                snapshotCarbs100: item.carbs100,
                snapshotFat100: item.fat100,
                quantity: item.quantity,
                unit: item.unit,
                equivalentAmount: item.equivalentAmount,
                kcal: nutrients.kcal.rounded(),
                proteinG: nutrients.proteinG,
                carbsG: nutrients.carbsG,
                fatG: nutrients.fatG,
                snapshotFibre100: item.fibre100,
                snapshotSugar100: item.sugar100,
                snapshotSaturatedFat100: item.saturatedFat100,
                snapshotSalt100: item.salt100,
                fibreG: item.fibre100.map { $0 * item.equivalentAmount / 100 },
                sugarG: item.sugar100.map { $0 * item.equivalentAmount / 100 },
                saturatedFatG: item.saturatedFat100.map { $0 * item.equivalentAmount / 100 },
                saltG: item.salt100.map { $0 * item.equivalentAmount / 100 },
                snapshotWaterML100: item.waterML100,
                snapshotWaterBasis: item.waterBasis ?? "unknown",
                snapshotWaterSourceID: item.waterSourceID,
                waterML: item.waterML100.map { $0 * item.equivalentAmount / 100 }
            )
        }
        let preferenceUpdates = MealMemory.usagePreferenceUpdates(
            current: data.foodPreferences,
            items: validItems,
            userID: profile.userID,
            usedAt: request.loggedAt
        )

        let previousData = data
        let payload = StructuredMealRPCPayload(pMeal: request, pEntries: entryRequests)
        let offlineOperation = try OfflineOperation.rpc("log_structured_meal", params: payload)

        if let replaced = draft.replaceMealID {
            data.loggedMeals.removeAll { $0.id == replaced }
            data.loggedFoodEntries.removeAll { $0.mealID == replaced }
        }
        data.loggedMeals.removeAll { $0.id == draft.id }
        data.loggedMeals.insert(localMeal, at: 0)
        await refreshNudges()
        data.loggedFoodEntries.removeAll { $0.mealID == draft.id }
        data.loggedFoodEntries.insert(contentsOf: localEntries, at: 0)
        let updatedFoodIDs = Set(preferenceUpdates.map(\.foodID))
        data.foodPreferences.removeAll { updatedFoodIDs.contains($0.foodID) }
        data.foodPreferences.append(contentsOf: preferenceUpdates)
        await recalculateLocalStructuredDay(draft.localDate, userID: profile.userID)
        await saveLocalSnapshot()

        do {
            _ = try await service.logStructuredMeal(meal: request, entries: entryRequests)
            lastSyncAt = .now
        } catch {
            switch SyncFailurePolicy.classify(error) {
            case .transient:
                do {
                    try await offlineStore.enqueue(offlineOperation, for: profile.userID)
                    pendingSyncCount = (try? await offlineStore.pendingOperations(for: profile.userID).count)
                        ?? pendingSyncCount + 1
                    /* Saved offline and queued. Deliberately silent: this is
                       normal offline operation, not a failed save. */
                } catch {
                    data = previousData
                    await saveLocalSnapshot()
                    throw error
                }
            case .permanent:
                data = previousData
                await saveLocalSnapshot()
                try? await offlineStore.recordFailure(
                    offlineOperation,
                    reason: error.localizedDescription,
                    for: profile.userID
                )
                throw error
            }
        }
        for preference in preferenceUpdates {
            await persistUpsert(
                preference,
                table: "food_preferences",
                onConflict: "user_id,food_id",
                ownerID: profile.userID
            )
        }

        // The write is already committed and idempotent. A dashboard refresh
        // failure must not turn a successful meal into an offline retry or a
        // false error; the optimistic local meal remains the accurate view.
        do {
            try await refreshDashboard(expectedUserID: profile.userID)
        } catch {
            lastSyncAt = .now
        }
    }

    /// Copies the selected structured meals and legacy planned-meal checks to
    /// another date. The web client follows the same replacement rule: a
    /// copied planned meal replaces that planned meal on the destination day,
    /// while genuinely custom meals remain separate entries.
    func copyNutritionDay(
        from sourceDate: Date,
        to destinationDate: Date,
        mealIDs: Set<UUID>? = nil
    ) async throws {
        guard let profile else { throw APEXServiceError.configurationMissing }
        let sourceKey = sourceDate.apexDateKey
        let destinationKey = destinationDate.apexDateKey
        guard sourceKey != destinationKey else { return }

        let sourceMeals = data.loggedMeals
            .filter { $0.localDate == sourceKey && (mealIDs == nil || mealIDs?.contains($0.id) == true) }
            .sorted { $0.loggedAt < $1.loggedAt }
        var destinationMeals = data.loggedMeals.filter { $0.localDate == destinationKey }

        for sourceMeal in sourceMeals {
            let sourceEntries = data.loggedFoodEntries
                .filter { $0.mealID == sourceMeal.id }
                .sorted { $0.sortOrder < $1.sortOrder }
            guard sourceEntries.isEmpty == false else { continue }

            let newMealID = UUID()
            let replacement = sourceMeal.sourcePlannedMealID.flatMap { plannedID in
                destinationMeals.first { $0.sourcePlannedMealID == plannedID }
            }
            let items = sourceEntries.map { entry -> MealComposerItem in
                var item = MealComposerItem(entry: entry)
                item.id = UUID()
                return item
            }
            let draft = MealComposerDraft(
                id: newMealID,
                localDate: destinationKey,
                mealSlot: sourceMeal.mealSlot,
                displayName: sourceMeal.displayName,
                finishedAt: copiedClock(from: sourceMeal.loggedAt, onto: destinationDate),
                sourcePresetID: sourceMeal.sourcePresetID,
                sourcePlannedMealID: sourceMeal.sourcePlannedMealID,
                replaceMealID: replacement?.id,
                loggedAs: sourceMeal.loggedAs,
                items: items
            )
            try await saveStructuredMeal(draft)
            destinationMeals = data.loggedMeals.filter { $0.localDate == destinationKey }
        }

        let structuredSourcePlannedIDs = Set(sourceMeals.compactMap(\.sourcePlannedMealID))
        let sourceChecks = data.mealLogs.filter { check in
            guard check.date == sourceKey else { return false }
            if let mealIDs {
                // A structured planned check follows the selected structured
                // meal. Legacy checks without a structured meal are offered
                // only by a full-day paste.
                return structuredSourcePlannedIDs.contains(check.mealID)
                    && sourceMeals.contains { $0.sourcePlannedMealID == check.mealID && mealIDs.contains($0.id) }
            }
            return true
        }
        var destinationChecks = Set(data.mealLogs.filter { $0.date == destinationKey }.map(\.mealID))
        for sourceCheck in sourceChecks where destinationChecks.contains(sourceCheck.mealID) == false {
            let row = MealLog(
                id: UUID(),
                userID: profile.userID,
                date: destinationKey,
                mealID: sourceCheck.mealID,
                checkedAt: Date().ISO8601Format()
            )
            data.mealLogs.append(row)
            await persistUpsert(row, table: "meal_logs", onConflict: "user_id,date,meal_id")
            destinationChecks.insert(sourceCheck.mealID)
        }

        await saveLocalSnapshot()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Calendar Clear intentionally removes only meals and snacks. Hydration,
    /// workouts, supplements and activity evidence remain untouched.
    func clearNutritionDay(_ date: Date) async {
        let key = date.apexDateKey
        let structured = data.loggedMeals.filter { $0.localDate == key }
        let legacyChecks = data.mealLogs.filter { $0.date == key }
        for meal in structured { await deleteLoggedMeal(meal) }
        for check in legacyChecks {
            data.mealLogs.removeAll { $0.id == check.id }
            await persistDelete(table: "meal_logs", id: check.id)
        }
        if let userID = profile?.userID {
            await recalculateLocalStructuredDay(key, userID: userID)
            await saveLocalSnapshot()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Moves an actual meal on the metabolic Dayline. The nutrition values do
    /// not change, only the recorded finish time used by timing intelligence.
    func updateLoggedMealFinishedAt(_ mealID: UUID, to date: Date) async {
        guard let index = data.loggedMeals.firstIndex(where: { $0.id == mealID }) else { return }
        var meal = data.loggedMeals[index]
        meal.loggedAt = date.ISO8601Format()
        data.loggedMeals[index] = meal
        await persistUpsert(meal, table: "logged_meals")
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Moves a planned meal moment. This is intentionally account-scoped and
    /// persists the same `meals.time` value consumed by the web client.
    func updatePlannedMealTime(_ mealID: UUID, to time: String) async {
        guard let index = data.meals.firstIndex(where: { $0.id == mealID }) else { return }
        var meal = data.meals[index]
        meal.time = time
        data.meals[index] = meal
        await persistUpsert(meal, table: "meals")
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func copiedClock(from isoTimestamp: String, onto destination: Date) -> Date {
        let source = ISO8601DateFormatter().date(from: isoTimestamp) ?? destination
        let calendar = Calendar.current
        let clock = calendar.dateComponents([.hour, .minute, .second], from: source)
        var destinationParts = calendar.dateComponents([.year, .month, .day], from: destination)
        destinationParts.hour = clock.hour
        destinationParts.minute = clock.minute
        destinationParts.second = clock.second
        return calendar.date(from: destinationParts) ?? destination
    }

    @discardableResult
    func saveMealPreset(
        name: String,
        mealSlot: String,
        items: [MealComposerItem],
        subtitle: String = "",
        existing: MealPreset? = nil
    ) async throws -> UUID {
        guard let profile else { throw APEXServiceError.configurationMissing }
        let eligible = items.filter { $0.foodID != nil && $0.equivalentAmount > 0 }
        guard eligible.isEmpty == false else { throw APEXServiceError.incompleteFood }
        let presetID = existing?.id ?? UUID()
        let preset = MealPresetRequest(
            id: presetID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mealSlot: mealSlot,
            sourcePlannedMealID: existing?.sourcePlannedMealID,
            archived: false
        )
        let itemRequests = eligible.enumerated().compactMap { index, item -> MealPresetItemRequest? in
            guard let foodID = item.foodID else { return nil }
            return MealPresetItemRequest(
                id: UUID(), foodID: foodID, sortOrder: index,
                quantity: item.quantity, unit: item.unit,
                optional: item.optional, locked: item.locked,
                adjustable: item.adjustable,
                minimumAmount: item.minimumAmount,
                maximumAmount: item.maximumAmount,
                stepAmount: item.stepAmount,
                adjustmentRole: item.adjustmentRole
            )
        }
        let expectedVersion = existing?.version ?? 0
        let localPreset = MealPreset(
            id: presetID, userID: profile.userID,
            name: preset.name, mealSlot: mealSlot,
            sourcePlannedMealID: existing?.sourcePlannedMealID,
            archived: false, version: expectedVersion + 1
        )
        let localItems = itemRequests.map { value in
            MealPresetItem(
                id: value.id, presetID: presetID, userID: profile.userID,
                foodID: value.foodID, sortOrder: value.sortOrder,
                quantity: value.quantity, unit: value.unit,
                optional: value.optional, locked: value.locked,
                adjustable: value.adjustable,
                minimumAmount: value.minimumAmount,
                maximumAmount: value.maximumAmount,
                stepAmount: value.stepAmount,
                adjustmentRole: value.adjustmentRole
            )
        }
        data.mealPresets.removeAll { $0.id == presetID }
        data.mealPresets.append(localPreset)
        data.mealPresetItems.removeAll { $0.presetID == presetID }
        data.mealPresetItems.append(contentsOf: localItems)
        if subtitle.isEmpty == false {
            await updateSettings { settings in
                var subtitles = settings.addons["meal_preset_subtitles"]?.objectValue ?? [:]
                subtitles[presetID.uuidString.lowercased()] = .string(subtitle)
                settings.addons["meal_preset_subtitles"] = .object(subtitles)
            }
        }
        await saveLocalSnapshot()

        do {
            let savedID = try await service.saveMealPreset(
                preset: preset,
                items: itemRequests,
                expectedVersion: expectedVersion
            )
            try await refreshDashboard()
            return savedID
        } catch {
            let payload = MealPresetRPCPayload(
                pPreset: preset,
                pItems: itemRequests,
                pExpectedVersion: expectedVersion
            )
            try await offlineStore.enqueue(.rpc("save_meal_preset", params: payload), for: profile.userID)
            pendingSyncCount = (try? await offlineStore.pendingOperations(for: profile.userID).count) ?? pendingSyncCount + 1
            /* Saved offline and queued. Deliberately silent: this is the app
               working, not an event, and pendingSyncCount already shows it.
               Naming the backend on a user's screen helps nobody. */
            return presetID
        }
    }

    func deleteMealPreset(_ preset: MealPreset) async {
        guard let profile else { return }
        data.mealPresets.removeAll { $0.id == preset.id }
        data.mealPresetItems.removeAll { $0.presetID == preset.id }
        await saveLocalSnapshot()
        do {
            try await service.deleteMealPreset(preset.id)
            try await refreshDashboard()
        } catch {
            do {
                try await offlineStore.enqueue(
                    .rpc("delete_meal_preset", params: ["p_preset_id": preset.id.uuidString]),
                    for: profile.userID
                )
                pendingSyncCount = (try? await offlineStore.pendingOperations(for: profile.userID).count) ?? pendingSyncCount + 1
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func setFoodFavourite(_ food: Food, favourite: Bool) async {
        guard let profile, let foodID = UUID(uuidString: food.id) else { return }
        let existing = data.foodPreferences.first { $0.foodID == foodID }
        let value = FoodPreference(
            id: existing?.id ?? UUID(), userID: profile.userID, foodID: foodID,
            personalName: existing?.personalName, aliases: existing?.aliases ?? [],
            favourite: favourite, usualAmount: existing?.usualAmount,
            usualUnit: existing?.usualUnit, usageCount: existing?.usageCount ?? 0,
            lastUsedAt: existing?.lastUsedAt, hidden: existing?.hidden ?? false
        )
        data.foodPreferences.removeAll { $0.foodID == foodID }
        data.foodPreferences.append(value)
        await persistUpsert(value, table: "food_preferences", onConflict: "user_id,food_id")
    }

    func updateProfile(_ transform: (inout Profile) -> Void) async {
        guard var profile else { return }
        transform(&profile)
        profile.updatedAt = Date().ISO8601Format()
        data.profile = profile
        await persistUpsert(profile, table: "profile", onConflict: "user_id")
    }

    func logFood(
        _ food: Food,
        amount: Double,
        unit: String,
        mealSlot: String,
        date: Date
    ) async throws {
        guard let profile else { throw APEXServiceError.configurationMissing }
        let equivalentAmount: Double
        switch unit {
        case "piece": equivalentAmount = amount * (food.pieceGramsOrML ?? 0)
        case "serving": equivalentAmount = amount * (food.servingGramsOrML ?? 0)
        default: equivalentAmount = amount
        }
        guard equivalentAmount > 0, food.kcal100 != nil else {
            throw APEXServiceError.incompleteFood
        }

        let now = Date().ISO8601Format()
        let mealID = UUID()
        let entryID = UUID()
        let nutrients = food.nutrients(forEquivalentAmount: equivalentAmount)
        let key = "ios-food-\(mealID.uuidString.lowercased())"
        let mealRequest = StructuredMealRequest(
            id: mealID,
            localDate: date.apexDateKey,
            mealSlot: mealSlot,
            displayName: food.name,
            sourcePresetID: nil,
            sourcePlannedMealID: nil,
            loggedAt: now,
            clientIdempotencyKey: key,
            loggedAs: "custom",
            replaceMealID: nil
        )
        let entryRequest = StructuredFoodEntryRequest(
            id: entryID,
            foodID: UUID(uuidString: food.id),
            sortOrder: 0,
            snapshotName: food.name,
            snapshotBrand: food.brand,
            snapshotPreparationState: food.preparationState,
            snapshotNutritionBasis: food.nutritionBasis,
            snapshotKcal100: food.kcal100 ?? 0,
            snapshotProtein100: food.protein100 ?? 0,
            snapshotCarbs100: food.carbs100 ?? 0,
            snapshotFat100: food.fat100 ?? 0,
            snapshotFibre100: food.fibre100,
            snapshotSugar100: food.sugar100,
            snapshotSaturatedFat100: food.saturatedFat100,
            snapshotSalt100: food.salt100,
            snapshotWaterML100: food.waterML100,
            snapshotWaterBasis: food.waterBasis ?? "unknown",
            snapshotWaterSourceID: food.waterSourceID,
            quantity: amount,
            unit: unit,
            equivalentAmount: equivalentAmount
        )
        let localMeal = LoggedMeal(
            id: mealID,
            userID: profile.userID,
            localDate: date.apexDateKey,
            mealSlot: mealSlot,
            displayName: food.name,
            sourcePresetID: nil,
            sourcePlannedMealID: nil,
            loggedAt: now,
            clientIdempotencyKey: key,
            loggedAs: "custom",
            totalKcal: nutrients.kcal.rounded(),
            totalProteinG: nutrients.proteinG,
            totalCarbsG: nutrients.carbsG,
            totalFatG: nutrients.fatG
        )
        let localEntry = LoggedFoodEntry(
            id: entryID,
            mealID: mealID,
            userID: profile.userID,
            foodID: UUID(uuidString: food.id),
            sortOrder: 0,
            snapshotName: food.name,
            snapshotBrand: food.brand,
            snapshotPreparationState: food.preparationState,
            snapshotNutritionBasis: food.nutritionBasis,
            snapshotKcal100: food.kcal100 ?? 0,
            snapshotProtein100: food.protein100 ?? 0,
            snapshotCarbs100: food.carbs100 ?? 0,
            snapshotFat100: food.fat100 ?? 0,
            quantity: amount,
            unit: unit,
            equivalentAmount: equivalentAmount,
            kcal: nutrients.kcal.rounded(),
            proteinG: nutrients.proteinG,
            carbsG: nutrients.carbsG,
            fatG: nutrients.fatG,
            snapshotFibre100: food.fibre100,
            snapshotSugar100: food.sugar100,
            snapshotSaturatedFat100: food.saturatedFat100,
            snapshotSalt100: food.salt100,
            fibreG: food.fibre100.map { $0 * equivalentAmount / 100 },
            sugarG: food.sugar100.map { $0 * equivalentAmount / 100 },
            saturatedFatG: food.saturatedFat100.map { $0 * equivalentAmount / 100 },
            saltG: food.salt100.map { $0 * equivalentAmount / 100 },
            snapshotWaterML100: food.waterML100,
            snapshotWaterBasis: food.waterBasis ?? "unknown",
            snapshotWaterSourceID: food.waterSourceID,
            waterML: food.waterML100.map { $0 * equivalentAmount / 100 }
        )
        let preferenceUpdates = MealMemory.usagePreferenceUpdates(
            current: data.foodPreferences,
            items: [MealComposerItem(food: food, quantity: amount, unit: unit)],
            userID: profile.userID,
            usedAt: now
        )

        data.loggedMeals.insert(localMeal, at: 0)
        await refreshNudges()
        data.loggedFoodEntries.insert(localEntry, at: 0)
        let updatedFoodIDs = Set(preferenceUpdates.map(\.foodID))
        data.foodPreferences.removeAll { updatedFoodIDs.contains($0.foodID) }
        data.foodPreferences.append(contentsOf: preferenceUpdates)
        await recalculateLocalStructuredDay(date.apexDateKey, userID: profile.userID)
        await saveLocalSnapshot()

        do {
            _ = try await service.logStructuredMeal(meal: mealRequest, entries: [entryRequest])
            try await refreshDashboard()
        } catch {
            let payload = StructuredMealRPCPayload(pMeal: mealRequest, pEntries: [entryRequest])
            let operation = try OfflineOperation.rpc("log_structured_meal", params: payload)
            try await offlineStore.enqueue(operation, for: profile.userID)
            pendingSyncCount = (try? await offlineStore.pendingOperations(for: profile.userID).count) ?? pendingSyncCount + 1
            /* Saved offline and queued. Deliberately silent: this is the app
               working, not an event, and pendingSyncCount already shows it.
               Naming the backend on a user's screen helps nobody. */
        }
        /* A successful meal RPC refreshes the dashboard before the separate
           preference upsert. Reapply the captured account-owned update so the
           freshly scanned food never vanishes from Recents during that gap. */
        let refreshedFoodIDs = Set(preferenceUpdates.map(\.foodID))
        data.foodPreferences.removeAll { refreshedFoodIDs.contains($0.foodID) }
        data.foodPreferences.append(contentsOf: preferenceUpdates)
        for preference in preferenceUpdates {
            await persistUpsert(
                preference,
                table: "food_preferences",
                onConflict: "user_id,food_id",
                ownerID: profile.userID
            )
        }
    }

    func deleteLoggedMeal(_ meal: LoggedMeal) async {
        guard let profile else { return }
        data.loggedMeals.removeAll { $0.id == meal.id }
        data.loggedFoodEntries.removeAll { $0.mealID == meal.id }
        await recalculateLocalStructuredDay(meal.localDate, userID: profile.userID)
        await saveLocalSnapshot()
        do {
            try await service.deleteStructuredMeal(meal.id)
            try await refreshDashboard()
        } catch {
            do {
                let operation = try OfflineOperation.rpc(
                    "delete_structured_meal",
                    params: ["p_meal_id": meal.id.uuidString]
                )
                try await offlineStore.enqueue(operation, for: profile.userID)
                pendingSyncCount = (try? await offlineStore.pendingOperations(for: profile.userID).count) ?? pendingSyncCount + 1
                /* Queued, and silent for the same reason a queued save is. */
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func saveProgressPhoto(
        original: Data,
        thumbnail: Data,
        width: Int,
        height: Int,
        pose: String,
        note: String,
        date: Date = .now
    ) async throws {
        guard let profile else { throw APEXServiceError.configurationMissing }
        let id = UUID()
        let owner = profile.userID.uuidString.lowercased()
        let month = String(date.apexDateKey.prefix(7))
        let stem = id.uuidString.lowercased()
        let originalPath = "\(owner)/\(month)/\(stem)-original.jpg"
        let thumbnailPath = "\(owner)/\(month)/\(stem)-thumb.jpg"
        let row = ProgressPhoto(
            id: id,
            userID: profile.userID,
            localDate: date.apexDateKey,
            capturedAt: date.ISO8601Format(),
            pose: pose,
            storagePath: originalPath,
            thumbnailPath: thumbnailPath,
            width: width,
            height: height,
            aspectRatio: Double(width) / Double(max(height, 1)),
            cropX: 0.5,
            cropY: 0.5,
            cropScale: 1,
            referencePhotoID: data.progressPhotos.first(where: { $0.pose == pose })?.id,
            weightKG: profile.weightKG,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            clientIdempotencyKey: "ios-progress-\(stem)"
        )
        try await service.uploadProgressPhoto(row: row, original: original, thumbnail: thumbnail)
        data.progressPhotos.insert(row, at: 0)
        await saveLocalSnapshot()
    }

    func signedProgressURL(for photo: ProgressPhoto, thumbnail: Bool) async throws -> URL {
        try await service.signedProgressURL(path: thumbnail ? photo.thumbnailPath : photo.storagePath)
    }

    /// Returns the finished session's id so the caller can show its receipt.
    @discardableResult
    func completeWorkout(
        day: ProgramDay,
        setInputs: [WorkoutSetInput],
        lite: Bool,
        startedAt: Date
    ) async -> UUID? {
        guard let ownerID = TrainingInduction.workoutOwnerID(in: data, day: day) else { return nil }
        let exercises = data.exercises
            .filter {
                $0.userID == ownerID
                    && $0.programDayID == day.id
                    && $0.isLite == lite
            }
            .sorted { $0.sortOrder < $1.sortOrder }
        let normalizedInputs = PlayerTimeline.persistenceOrder(
            setInputs.map { $0.normalizedForPersistence() },
            exercises: exercises
        )
        guard normalizedInputs.allSatisfy({ $0.skipped || ExerciseLogging.isValid($0) }) else {
            return nil
        }
        let now = Date().ISO8601Format()
        let isDeload = TrainingAdjustmentEngine.isDeload(
            on: Date().apexDateKey,
            marks: data.deloadMarks ?? []
        )
        let workout = WorkoutSession(
            id: UUID(), userID: ownerID, date: Date().apexDateKey,
            programDayID: day.id, isLite: lite, isDeload: isDeload,
            isEventRecovery: false, completed: true, qualityScore: 1,
            startedAt: startedAt.ISO8601Format(), completedAt: now, notes: "Completed in APEX iOS"
        )
        let logs = normalizedInputs.map { input in
            return WorkoutLog(
                id: UUID(), userID: ownerID, sessionID: workout.id,
                exerciseID: input.exerciseID, exerciseName: input.exerciseName,
                setNumber: input.setNumber, weightKG: input.weightKG,
                reps: input.reps, rir: input.rir,
                movementID: input.movementID,
                durationSeconds: input.durationSeconds,
                distanceMeters: input.distanceMeters,
                contacts: input.contacts,
                rounds: input.rounds,
                workSeconds: input.workSeconds,
                recoverySeconds: input.recoverySeconds,
                skipped: input.skipped,
                overrideFlag: false, createdAt: now
            )
        }
        data.workoutSessions.append(workout)
        data.workoutLogs.append(contentsOf: logs)

        var linkedActivity: ActivityLog?
        if let profile, profile.userID == ownerID,
           let activityType = data.activityTypes.first(where: { $0.id == "apex-strength" }) {
            let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
            let activity = ActivityLog(
                id: UUID(),
                userID: ownerID,
                date: Date().apexDateKey,
                typeID: activityType.id,
                quantity: 1,
                durationMinutes: elapsed,
                distanceKM: nil,
                watchKcal: nil,
                computedKcal: EnergyEngine.blockCalories(
                    type: activityType,
                    quantity: 1,
                    durationMinutes: elapsed,
                    distanceKM: nil,
                    watchKcal: nil,
                    weightKG: profile.weightKG
                ),
                source: "workout_module",
                reconciled: false,
                createdAt: now,
                updatedAt: now
            )
            data.activityLogs.append(activity)
            linkedActivity = activity
        }

        /* The receipt is part of completing the workout, so it must not wait
           for a chain of remote writes. Preserve one complete local snapshot
           first, then let the normal offline-aware sync path drain in the
           background. */
        await saveLocalSnapshot()
        Task { @MainActor [weak self] in
            guard let self, TrainingInduction.belongsToAccount(self.data, userID: ownerID) else { return }
            await self.persistUpsert(
                workout,
                table: "workout_sessions",
                ownerID: ownerID,
                surfacePermanentFailure: false
            )
            for log in logs {
                guard TrainingInduction.belongsToAccount(self.data, userID: ownerID) else { return }
                await self.persistUpsert(
                    log,
                    table: "workout_logs",
                    ownerID: ownerID,
                    surfacePermanentFailure: false
                )
            }
            if let linkedActivity, TrainingInduction.belongsToAccount(self.data, userID: ownerID) {
                await self.persistUpsert(
                    linkedActivity,
                    table: "activity_logs",
                    ownerID: ownerID,
                    surfacePermanentFailure: false
                )
            }
        }
        return workout.id
    }

    /// Correct measured facts from a finished-session receipt. A correction
    /// keeps the original row identity, so history and progression never split
    /// one performed set into two events.
    @discardableResult
    func updateWorkoutLog(id: UUID, draft: WorkoutSetInput) async -> Bool {
        guard let ownerID = verifiedPersistenceOwnerID(),
              let index = data.workoutLogs.firstIndex(where: { $0.id == id }),
              data.workoutLogs[index].userID == ownerID else {
            return false
        }
        let updated = WorkoutReceipt.correctedLog(data.workoutLogs[index], with: draft)
        data.workoutLogs[index] = updated
        await persistUpsert(updated, table: "workout_logs", ownerID: ownerID)
        return true
    }

    func toggleDeload(on date: Date = .now) async {
        guard let ownerID = verifiedPersistenceOwnerID() else { return }
        let day = date.apexDateKey
        if let existing = (data.deloadMarks ?? []).first(where: {
            $0.userID == ownerID && $0.date == day
        }) {
            data.deloadMarks?.removeAll { $0.id == existing.id }
            await persistDelete(table: "deload_marks", id: existing.id, ownerID: ownerID)
        } else {
            let mark = DeloadMark(id: UUID(), userID: ownerID, date: day)
            if data.deloadMarks == nil { data.deloadMarks = [] }
            data.deloadMarks?.append(mark)
            await persistUpsert(
                mark,
                table: "deload_marks",
                onConflict: "user_id,date",
                ownerID: ownerID
            )
        }
    }

    func exportOrbitData() throws -> URL {
        guard let profile else { throw APEXServiceError.configurationMissing }
        return try OrbitPrivateArchive
            .ownerScoped(from: data, userID: profile.userID)
            .writeTemporaryFile()
    }

    func deleteAllOrbitData() async {
        guard let profile else { return }

        let posters = data.orbitPosters.filter { $0.userID == profile.userID }
        let segments = data.orbitSegments.filter { $0.userID == profile.userID }
        let runs = data.orbitRuns.filter { $0.userID == profile.userID }
        let campaignSessions = data.orbitCampaignSessions.filter { $0.userID == profile.userID }
        let campaigns = data.orbitCampaigns.filter { $0.userID == profile.userID }
        let inductions = data.orbitInductions.filter { $0.userID == profile.userID }
        let routes = data.orbitRoutes.filter { $0.userID == profile.userID }
        let shoes = data.orbitShoes.filter { $0.userID == profile.userID }

        // Clear the local owner-scoped view first. Each remote delete then uses
        // the normal protected offline outbox if connectivity disappears.
        data.orbitPosters.removeAll { $0.userID == profile.userID }
        data.orbitSegments.removeAll { $0.userID == profile.userID }
        data.orbitRuns.removeAll { $0.userID == profile.userID }
        data.orbitCampaignSessions.removeAll { $0.userID == profile.userID }
        data.orbitCampaigns.removeAll { $0.userID == profile.userID }
        data.orbitInductions.removeAll { $0.userID == profile.userID }
        data.orbitRoutes.removeAll { $0.userID == profile.userID }
        data.orbitShoes.removeAll { $0.userID == profile.userID }
        OrbitLocationManager.shared.cancel()
        await saveLocalSnapshot()

        for item in posters { await persistDelete(table: "orbit_posters", id: item.id) }
        for item in segments { await persistDelete(table: "orbit_segments", id: item.id) }
        for item in runs { await persistDelete(table: "orbit_runs", id: item.id) }
        for item in campaignSessions { await persistDelete(table: "orbit_campaign_sessions", id: item.id) }
        for item in campaigns { await persistDelete(table: "orbit_campaigns", id: item.id) }
        for item in inductions { await persistDelete(table: "orbit_inductions", id: item.id) }
        for item in routes { await persistDelete(table: "orbit_routes", id: item.id) }
        for item in shoes { await persistDelete(table: "orbit_shoes", id: item.id) }
        alertMessage = "Orbit data deleted for this profile."
    }

    func saveOrbitRun(
        mission: String,
        startedAt: Date,
        endedAt: Date,
        samples: [OrbitLocationSample],
        distanceM: Double,
        movingSeconds: TimeInterval,
        pauses: [OrbitPauseInterval] = [],
        manualLapsM: [Double] = [],
        routeID: UUID? = nil,
        campaignSessionID: UUID? = nil,
        shoeID: UUID? = nil
    ) async -> OrbitRunRecord? {
        guard let profile else { return nil }
        let metrics = OrbitRunMetricsEngine.calculate(
            samples: samples,
            elapsedSeconds: endedAt.timeIntervalSince(startedAt),
            movingSeconds: movingSeconds,
            weightKG: profile.weightKG
        )
        let sampleJSON = metrics.acceptedSamples.map { sample in
            JSONValue.object([
                "lat": .number(sample.latitude),
                "lng": .number(sample.longitude),
                "elevation_m": sample.altitude.isFinite ? .number(sample.altitude) : .null,
                "recorded_at": .number(sample.timestamp.timeIntervalSince1970 * 1_000),
                "accuracy_m": .number(sample.horizontalAccuracy),
                "heart_rate_bpm": .null,
                "cadence_spm": .null
            ])
        }
        let runID = UUID()
        let now = Date().ISO8601Format()
        let run = OrbitRunRecord(
            id: runID, userID: profile.userID,
            clientIdempotencyKey: "ios-run-\(runID.uuidString.lowercased())",
            localDate: startedAt.apexDateKey,
            startedAt: startedAt.ISO8601Format(), endedAt: endedAt.ISO8601Format(),
            mission: mission, routeID: routeID, campaignSessionID: campaignSessionID, shoeID: shoeID,
            samples: sampleJSON,
            pauses: pauses.map(\.json),
            manualLapsM: manualLapsM.map { .number($0) },
            metrics: metrics.json,
            checkIn: [
                "perceived_effort": .null,
                "legs": .null,
                "discomfort": .null,
                "note": .string("")
            ], nutritionAdjustmentAppliedAt: nil,
            status: "completed", createdAt: now, updatedAt: now
        )
        data.orbitRuns.insert(run, at: 0)
        await persistUpsert(run, table: "orbit_runs", onConflict: "user_id,client_idempotency_key")
        if let campaignSessionID,
           let index = data.orbitCampaignSessions.firstIndex(where: { $0.id == campaignSessionID }) {
            data.orbitCampaignSessions[index].status = "completed"
            data.orbitCampaignSessions[index].completionRunID = runID
            data.orbitCampaignSessions[index].updatedAt = now
            await persistUpsert(data.orbitCampaignSessions[index], table: "orbit_campaign_sessions")
        }
        await integrateOrbitRun(run)
        return run
    }

    func updateOrbitRunCheckIn(
        _ run: OrbitRunRecord,
        perceivedEffort: Int?,
        legs: String?,
        discomfort: String?,
        note: String
    ) async -> OrbitRunRecord {
        let updated = OrbitRunRecord(
            id: run.id,
            userID: run.userID,
            clientIdempotencyKey: run.clientIdempotencyKey,
            localDate: run.localDate,
            startedAt: run.startedAt,
            endedAt: run.endedAt,
            mission: run.mission,
            routeID: run.routeID,
            campaignSessionID: run.campaignSessionID,
            shoeID: run.shoeID,
            samples: run.samples,
            pauses: run.pauses,
            manualLapsM: run.manualLapsM,
            metrics: run.metrics,
            checkIn: [
                "perceived_effort": perceivedEffort.map { .number(Double($0)) } ?? .null,
                "legs": legs.map { .string($0) } ?? .null,
                "discomfort": discomfort.map { .string($0) } ?? .null,
                "note": .string(note.trimmingCharacters(in: .whitespacesAndNewlines))
            ],
            nutritionAdjustmentAppliedAt: run.nutritionAdjustmentAppliedAt,
            status: run.status,
            createdAt: run.createdAt,
            updatedAt: Date().ISO8601Format()
        )
        if let index = data.orbitRuns.firstIndex(where: { $0.id == run.id }) {
            data.orbitRuns[index] = updated
        }
        await persistUpsert(updated, table: "orbit_runs", onConflict: "user_id,client_idempotency_key")
        await adaptCampaignAfterRun(updated)
        return updated
    }

    func applyOrbitNutritionAdjustment(
        to run: OrbitRunRecord,
        foodSuggestion: OrbitFoodMemorySuggestion?
    ) async -> OrbitRunRecord {
        guard let profile, run.userID == profile.userID,
              run.nutritionAdjustmentAppliedAt == nil
        else { return run }
        let adjustment = OrbitIntegrations.nutritionAdjustment(run: run, weightKG: profile.weightKG)
        guard adjustment.kcal > 0 else { return run }

        guard let draft = OrbitIntegrations.nutritionMealDraft(run: run, suggestion: foodSuggestion) else {
            alertMessage = "Choose one of your saved foods before applying this Orbit adjustment."
            return run
        }
        do {
            try await saveStructuredMeal(draft)
        } catch {
            alertMessage = "The Orbit food adjustment was not applied. \(error.localizedDescription)"
            return run
        }

        let updated = OrbitRunRecord(
            id: run.id, userID: run.userID, clientIdempotencyKey: run.clientIdempotencyKey,
            localDate: run.localDate, startedAt: run.startedAt, endedAt: run.endedAt,
            mission: run.mission, routeID: run.routeID, campaignSessionID: run.campaignSessionID,
            shoeID: run.shoeID, samples: run.samples, pauses: run.pauses,
            manualLapsM: run.manualLapsM, metrics: run.metrics, checkIn: run.checkIn,
            nutritionAdjustmentAppliedAt: Date().ISO8601Format(), status: run.status,
            createdAt: run.createdAt, updatedAt: Date().ISO8601Format()
        )
        data.orbitRuns.removeAll { $0.id == run.id }
        data.orbitRuns.insert(updated, at: 0)
        await persistUpsert(updated, table: "orbit_runs", onConflict: "user_id,client_idempotency_key")
        return updated
    }

    func saveOrbitInduction(_ induction: OrbitInduction) async {
        if let index = data.orbitInductions.firstIndex(where: { $0.id == induction.id }) {
            data.orbitInductions[index] = induction
        } else {
            data.orbitInductions.insert(induction, at: 0)
        }
        await persistUpsert(induction, table: "orbit_inductions")
    }

    func completeOrbitInduction(_ induction: OrbitInduction) async -> OrbitCampaign {
        await saveOrbitInduction(induction)
        let generated = OrbitCampaignEngine.createCampaign(
            induction: induction,
            programDays: TrainingInduction.activeProgramDays(in: data),
            events: data.events
        )
        data.orbitCampaigns.removeAll { $0.id == generated.campaign.id }
        data.orbitCampaigns.insert(generated.campaign, at: 0)
        let generatedIDs = Set(generated.sessions.map(\.id))
        data.orbitCampaignSessions.removeAll { generatedIDs.contains($0.id) }
        data.orbitCampaignSessions.append(contentsOf: generated.sessions)
        await persistUpsert(
            generated.campaign,
            table: "orbit_campaigns",
            onConflict: "user_id,client_idempotency_key"
        )
        for item in generated.sessions {
            await persistUpsert(item, table: "orbit_campaign_sessions")
        }
        return generated.campaign
    }

    func markOrbitCampaignSessionMissed(_ session: OrbitCampaignSession) async {
        guard let campaign = data.orbitCampaigns.first(where: { $0.id == session.campaignID }) else { return }
        let bundle = OrbitCampaignEngine.adaptAfterMissed(
            campaign: campaign,
            sessions: data.orbitCampaignSessions.filter { $0.campaignID == campaign.id },
            missedID: session.id
        )
        await saveCampaignBundle(bundle.campaign, sessions: bundle.sessions)
    }

    func chooseOrbitCampaignVersion(_ session: OrbitCampaignSession, useOriginal: Bool) async {
        guard let campaignIndex = data.orbitCampaigns.firstIndex(where: { $0.id == session.campaignID }) else { return }
        var updatedSession = session
        if useOriginal { updatedSession.adapted = updatedSession.original }
        updatedSession.userOverride = true
        if useOriginal { updatedSession.adaptationReason = "User kept the original prescription." }
        updatedSession.updatedAt = Date().ISO8601Format()
        if let index = data.orbitCampaignSessions.firstIndex(where: { $0.id == session.id }) {
            data.orbitCampaignSessions[index] = updatedSession
        }

        var campaign = data.orbitCampaigns[campaignIndex]
        campaign.adaptations = campaign.adaptations.map { value in
            guard case .object(var object) = value,
                  object["session_id"]?.stringValue == session.id.uuidString.lowercased()
            else { return value }
            object["accepted"] = .bool(useOriginal == false)
            return .object(object)
        }
        campaign.updatedAt = Date().ISO8601Format()
        data.orbitCampaigns[campaignIndex] = campaign
        await persistUpsert(updatedSession, table: "orbit_campaign_sessions")
        await persistUpsert(campaign, table: "orbit_campaigns", onConflict: "user_id,client_idempotency_key")
    }

    func saveOrbitRoute(
        _ candidate: OrbitRouteCandidate,
        name: String,
        mission: String,
        surface: String,
        shape: String
    ) async -> OrbitRouteRecord? {
        guard let profile else { return nil }
        let id = UUID()
        let now = Date().ISO8601Format()
        let points = candidate.points.map { point in
            JSONValue.object([
                "lat": .number(point.lat),
                "lng": .number(point.lng),
                "elevation_m": point.elevationM.map { .number($0) } ?? .null
            ])
        }
        let route = OrbitRouteRecord(
            id: id,
            userID: profile.userID,
            clientIdempotencyKey: "ios-route-\(id.uuidString.lowercased())",
            name: name,
            note: candidate.explanation,
            points: points,
            distanceM: candidate.distanceM,
            elevationGainM: candidate.elevationGainM,
            surface: surface,
            terrain: candidate.terrain,
            shape: shape,
            navigationComplexity: candidate.navigationComplexity,
            familiarityPercent: nil,
            favourite: false,
            rating: nil,
            missionTags: [mission.lowercased().replacingOccurrences(of: " ", with: "_")],
            preferredSections: [],
            avoidedSections: [],
            provider: "BRouter and OpenStreetMap",
            attribution: "Route data © OpenStreetMap contributors · routing by BRouter",
            createdAt: now,
            updatedAt: now
        )
        data.orbitRoutes.insert(route, at: 0)
        await persistUpsert(route, table: "orbit_routes", onConflict: "user_id,client_idempotency_key")
        return route
    }

    func updateOrbitRoute(_ route: OrbitRouteRecord) async {
        var updated = route
        updated.updatedAt = Date().ISO8601Format()
        data.orbitRoutes.removeAll { $0.id == updated.id }
        data.orbitRoutes.insert(updated, at: 0)
        await persistUpsert(updated, table: "orbit_routes", onConflict: "user_id,client_idempotency_key")
    }

    func duplicateOrbitRoute(_ route: OrbitRouteRecord) async -> OrbitRouteRecord? {
        guard let profile else { return nil }
        var copy = route
        let id = UUID()
        let now = Date().ISO8601Format()
        copy = OrbitRouteRecord(
            id: id,
            userID: profile.userID,
            clientIdempotencyKey: "ios-route-\(id.uuidString.lowercased())",
            name: "\(route.name) copy",
            note: route.note,
            points: route.points,
            distanceM: route.distanceM,
            elevationGainM: route.elevationGainM,
            surface: route.surface,
            terrain: route.terrain,
            shape: route.shape,
            navigationComplexity: route.navigationComplexity,
            familiarityPercent: route.familiarityPercent,
            favourite: false,
            rating: route.rating,
            missionTags: route.missionTags,
            preferredSections: route.preferredSections,
            avoidedSections: route.avoidedSections,
            provider: route.provider,
            attribution: route.attribution,
            createdAt: now,
            updatedAt: now
        )
        data.orbitRoutes.insert(copy, at: 0)
        await persistUpsert(copy, table: "orbit_routes", onConflict: "user_id,client_idempotency_key")
        return copy
    }

    func saveOrbitShoe(
        id: UUID? = nil,
        name: String,
        brand: String,
        firstUseDate: Date,
        surfaces: [String],
        notes: String,
        archived: Bool = false
    ) async {
        guard let profile else { return }
        let identifier = id ?? UUID()
        let existing = data.orbitShoes.first { $0.id == identifier }
        let now = Date().ISO8601Format()
        let shoe = OrbitShoe(
            id: identifier,
            userID: profile.userID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            firstUseDate: firstUseDate.apexDateKey,
            preferredSurfaces: surfaces,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            archived: archived,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        data.orbitShoes.removeAll { $0.id == identifier }
        data.orbitShoes.append(shoe)
        await persistUpsert(shoe, table: "orbit_shoes")
    }

    func archiveOrbitShoe(_ shoe: OrbitShoe) async {
        await saveOrbitShoe(
            id: shoe.id,
            name: shoe.name,
            brand: shoe.brand,
            firstUseDate: ISO8601DateFormatter.apexDateOnly.date(from: shoe.firstUseDate) ?? .now,
            surfaces: shoe.preferredSurfaces,
            notes: shoe.notes,
            archived: true
        )
    }

    func saveOrbitSegment(
        route: OrbitRouteRecord,
        name: String,
        startDistanceM: Int,
        endDistanceM: Int
    ) async {
        guard let profile, endDistanceM > startDistanceM else { return }
        let now = Date().ISO8601Format()
        let segment = OrbitSegment(
            id: UUID(), userID: profile.userID, routeID: route.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            startDistanceM: max(0, startDistanceM),
            endDistanceM: min(route.distanceM, endDistanceM),
            createdAt: now, updatedAt: now
        )
        data.orbitSegments.append(segment)
        await persistUpsert(segment, table: "orbit_segments")
    }

    func saveOrbitPosterMetadata(
        run: OrbitRunRecord,
        style: String,
        privacyTrimM: Int,
        includeHeartRate: Bool,
        note: String
    ) async {
        guard let profile else { return }
        let poster = OrbitPoster(
            id: UUID(), userID: profile.userID, runID: run.id,
            style: style, privacyTrimM: max(0, privacyTrimM),
            includeHeartRate: includeHeartRate,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date().ISO8601Format()
        )
        data.orbitPosters.insert(poster, at: 0)
        await persistUpsert(poster, table: "orbit_posters")
    }

    private func adaptCampaignAfterRun(_ run: OrbitRunRecord) async {
        guard let campaignSessionID = run.campaignSessionID,
              let completedSession = data.orbitCampaignSessions.first(where: { $0.id == campaignSessionID }),
              let campaign = data.orbitCampaigns.first(where: { $0.id == completedSession.campaignID })
        else { return }
        let bundle = OrbitCampaignEngine.adaptAfterRun(
            campaign: campaign,
            sessions: data.orbitCampaignSessions.filter { $0.campaignID == campaign.id },
            run: run
        )
        guard bundle.campaign != campaign || bundle.sessions != data.orbitCampaignSessions.filter({ $0.campaignID == campaign.id }) else { return }
        await saveCampaignBundle(bundle.campaign, sessions: bundle.sessions)
    }

    private func integrateOrbitRun(_ run: OrbitRunRecord) async {
        guard let profile, run.userID == profile.userID else { return }
        let distanceKM = max(0, (run.metrics["distance_m"]?.numberValue ?? 0) / 1_000)
        let durationMinutes = max(1, Int(((run.metrics["moving_s"]?.numberValue ?? 0) / 60).rounded()))
        let id = APEXStableID.scopedUUID(
            namespace: "activity-log:orbit:\(run.id.uuidString.lowercased())",
            date: run.localDate,
            userID: profile.userID
        )
        let activity = ActivityLog(
            id: id, userID: profile.userID, date: run.localDate,
            typeID: "jog-run", quantity: 1,
            durationMinutes: durationMinutes, distanceKM: distanceKM,
            watchKcal: nil, computedKcal: (profile.weightKG * distanceKM).rounded(),
            source: "orbit", reconciled: true,
            createdAt: run.createdAt, updatedAt: run.updatedAt
        )
        data.activityLogs = OrbitIntegrations.reconciledActivityLogs(
            existing: data.activityLogs,
            generated: activity
        )
        await persistUpsert(activity, table: "activity_logs")

        let healthAlreadyRepresentsRun = data.importedActivities.contains {
            $0.date == run.localDate
                && $0.kind == "endurance"
                && $0.source == "Apple Health"
                && abs($0.durationMinutes - durationMinutes) <= 5
        }
        if healthAlreadyRepresentsRun == false {
            let importedID = APEXStableID.orbitUUID(userID: profile.userID, key: "imported:\(run.id.uuidString.lowercased())")
            let imported = ImportedActivity(
                id: importedID, userID: profile.userID, date: run.localDate,
                kind: "endurance",
                activity: "APEX Orbit: \(run.mission.replacingOccurrences(of: "_", with: " "))",
                durationMinutes: durationMinutes,
                source: "APEX Orbit"
            )
            data.importedActivities.removeAll { $0.id == importedID }
            data.importedActivities.append(imported)
            await persistUpsert(imported, table: "imported_activities")
        }

        let dayLogs = data.activityLogs.filter { $0.date == run.localDate }
        let targets = EnergyEngine.targets(
            profile: profile,
            logs: dayLogs,
            catalog: data.activityTypes,
            planContext: NutritionGoalPolicy.context(from: data.settings)
        )
        let existing = data.dailyLogs.first { $0.date == run.localDate }
        let daily = DailyLog(
            id: existing?.id ?? APEXStableID.scopedUUID(namespace: "daily-log", date: run.localDate, userID: profile.userID),
            userID: profile.userID, date: run.localDate,
            kcal: existing?.kcal, proteinG: existing?.proteinG,
            fatG: existing?.fatG, carbsG: existing?.carbsG,
            waterL: existing?.waterL ?? 0,
            estimatedTDEE: targets.tdee, computedPAL: targets.pal,
            activityMode: "precise", weightKG: existing?.weightKG ?? profile.weightKG,
            nutritionSource: existing?.nutritionSource ?? "manual",
            manualKcal: existing?.manualKcal, manualProteinG: existing?.manualProteinG,
            manualFatG: existing?.manualFatG, manualCarbsG: existing?.manualCarbsG
        )
        await updateDailyLog(daily)
    }

    private func saveCampaignBundle(_ campaign: OrbitCampaign, sessions: [OrbitCampaignSession]) async {
        data.orbitCampaigns.removeAll { $0.id == campaign.id }
        data.orbitCampaigns.insert(campaign, at: 0)
        let ids = Set(sessions.map(\.id))
        data.orbitCampaignSessions.removeAll { ids.contains($0.id) }
        data.orbitCampaignSessions.append(contentsOf: sessions)
        await persistUpsert(campaign, table: "orbit_campaigns", onConflict: "user_id,client_idempotency_key")
        for item in sessions { await persistUpsert(item, table: "orbit_campaign_sessions") }
    }

    // Save a custom session. Saving the same weekday twice replaces that day
    // rather than stacking a second one, matching the web builder.
    func saveCustomWorkout(
        name: String,
        weekday: Int,
        estimatedMinutes: Int,
        sessionMode: WorkoutSessionMode,
        picks: [CustomWorkoutBuilder.Pick]
    ) async {
        guard let profile else { return }
        let userID = profile.userID

        let program = data.programs.first { $0.slug == "custom" }
            ?? Program(
                id: UUID(),
                userID: userID,
                slug: "custom",
                name: "Custom workouts",
                description: "Your searchable exercise studio, saved privately."
            )
        let existingDay = data.programDays.first { $0.programID == program.id && $0.weekday == weekday }
        let day = ProgramDay(
            id: existingDay?.id ?? UUID(),
            userID: userID,
            programID: program.id,
            weekday: weekday,
            name: name,
            dayType: "custom",
            estimatedMinutes: estimatedMinutes,
            warmupNote: "Five minutes of pain-free joint preparation",
            sortOrder: weekday,
            sessionMode: sessionMode.rawValue
        )

        let replaced = data.exercises.filter { $0.programDayID == day.id }
        let rows = picks.enumerated().map { index, pick -> Exercise in
            return Exercise(
                id: UUID(),
                userID: userID,
                programDayID: day.id,
                name: pick.item.name,
                movementID: pick.item.movementID,
                sets: min(max(pick.sets, 1), 12),
                repMin: min(max(pick.reps, 1), 600),
                repMax: min(max(pick.reps, 1), 600),
                repUnit: pick.item.unit,
                perSide: pick.item.perSide,
                restSeconds: min(max(pick.rest, 0), 600),
                tempoUp: 1,
                tempoDown: 2,
                tempoPause: 0,
                tempoNote: "",
                notes: "\(pick.item.equipment) · \(pick.item.muscles.joined(separator: ", "))",
                incrementKG: pick.item.incrementKG,
                isLite: false,
                optional: false,
                sortOrder: index
            )
        }

        data.exercises.removeAll { $0.programDayID == day.id }
        if let index = data.programs.firstIndex(where: { $0.id == program.id }) {
            data.programs[index] = program
        } else {
            data.programs.append(program)
        }
        if let index = data.programDays.firstIndex(where: { $0.id == day.id }) {
            data.programDays[index] = day
        } else {
            data.programDays.append(day)
        }
        data.exercises.append(contentsOf: rows)

        for exercise in replaced { await persistDelete(table: "exercises", id: exercise.id) }
        await persistUpsert(program, table: "programs")
        await persistUpsert(day, table: "program_days")
        for row in rows { await persistUpsert(row, table: "exercises") }
    }

    /*
     * Save a session that was not on the plan. An edit reuses the rows it
     * replaces so the workout never briefly reads as empty, and the parents are
     * written before the stale rows are removed.
     */
    func saveManualWorkout(
        date: String,
        title: String,
        exercises: [ManualWorkout.ExerciseDraft],
        editing sessionID: UUID? = nil
    ) async -> Bool {
        guard let profile else { return false }
        let userID = profile.userID

        let valid = !exercises.isEmpty && exercises.allSatisfy { draft in
            if let treadmill = draft.treadmill {
                return treadmill.durationMinutes > 0 && treadmill.distanceKM > 0
            }
            let descriptor = ExerciseLogging.descriptor(
                movementNamed: draft.name,
                movementID: draft.movementID
            )
            return descriptor.isSupported && !draft.sets.isEmpty && draft.sets.allSatisfy {
                ManualWorkout.hasFacts($0, descriptor: descriptor)
            }
        }
        guard valid else { return false }
        let usable = exercises

        let existingProgram = data.programs.first { $0.slug == "custom" }
        let program = existingProgram ?? Program(
            id: UUID(),
            userID: userID,
            slug: "custom",
            name: "Custom workouts",
            description: "Your searchable exercise studio, saved privately."
        )
        let weekday = APEXDateMath.isoWeekday(date)
        let existingDay = data.programDays.first { $0.programID == program.id && $0.weekday == weekday }
        let day = existingDay ?? ProgramDay(
            id: UUID(),
            userID: userID,
            programID: program.id,
            weekday: weekday,
            name: "Manual workout",
            dayType: "custom",
            estimatedMinutes: 45,
            warmupNote: "Five minutes of pain-free joint preparation",
            sortOrder: weekday
        )

        let existingSession = sessionID.flatMap { id in data.workoutSessions.first { $0.id == id } }
        if sessionID != nil && existingSession == nil { return false }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: .now)

        let workout = WorkoutSession(
            id: existingSession?.id ?? UUID(),
            userID: userID,
            date: date,
            programDayID: existingSession?.programDayID ?? day.id,
            isLite: existingSession?.isLite ?? false,
            isDeload: existingSession?.isDeload ?? false,
            isEventRecovery: existingSession?.isEventRecovery ?? false,
            completed: true,
            qualityScore: 1,
            startedAt: existingSession?.startedAt ?? now,
            completedAt: now,
            notes: ManualWorkout.notes(title: title)
        )

        let existingLogs = existingSession
            .map { session in data.workoutLogs.filter { $0.sessionID == session.id } } ?? []
        /* Chronology is the durable identity here: give every exercise its own
           minute so a movement repeated later in the session never collapses
           into its earlier occurrence. */
        let existingTimes = existingLogs.compactMap { formatter.date(from: $0.createdAt)?.timeIntervalSince1970 }
        let base = existingTimes.min() ?? Date().timeIntervalSince1970

        let proposed = ManualWorkout.logs(
            userID: userID,
            sessionID: workout.id,
            exercises: usable,
            base: Date(timeIntervalSince1970: base)
        )

        let reconciled = ManualWorkout.reconcile(existing: existingLogs, next: proposed)

        if existingSession == nil, existingProgram == nil { data.programs.append(program) }
        if existingSession == nil, existingDay == nil { data.programDays.append(day) }
        if let index = data.workoutSessions.firstIndex(where: { $0.id == workout.id }) {
            data.workoutSessions[index] = workout
        } else {
            data.workoutSessions.append(workout)
        }
        data.workoutLogs.removeAll { $0.sessionID == workout.id }
        data.workoutLogs.append(contentsOf: reconciled.logs)

        if existingSession == nil, existingProgram == nil {
            await persistUpsert(program, table: "programs")
        }
        if existingSession == nil, existingDay == nil {
            await persistUpsert(day, table: "program_days")
        }
        await persistUpsert(workout, table: "workout_sessions")
        for log in reconciled.logs { await persistUpsert(log, table: "workout_logs") }
        for staleID in reconciled.staleIDs { await persistDelete(table: "workout_logs", id: staleID) }
        /* A completed session moves the stat line, so replay the brain. */
        recomputeBrain()
        return true
    }

    /*
     * Install a generated starter plan.
     *
     * This narrows every calendar to the generated days. The established
     * programme is not deleted and returns from Settings, but from the outside
     * it simply vanishes, which is indistinguishable from data loss. The caller
     * is responsible for confirming before this runs.
    */
    func installInductionPlan(_ input: TrainingInduction.Input) async {
        let accountToken = accountGeneration.token
        guard !isBusy else { return }
        isBusy = true
        defer {
            if accountGeneration.accepts(accountToken) { isBusy = false }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-first-run"),
           var settings = data.settings {
            if TrainingInduction.hasRestorableOverlay(in: data) {
                settings = TrainingInduction.invalidatingPlanMetadata(
                    settings,
                    additionalDayIDs: TrainingInduction.legacyGeneratedDayIDs(
                        in: data,
                        userID: settings.userID
                    )
                )
                data.settings = settings
            }
            let plan = TrainingInduction.generate(
                userID: settings.userID,
                input: input,
                existingPrograms: data.programs,
                generationRevision: TrainingInduction.generationRevision(settings)
            )
            settings = TrainingInduction.markingPendingPlan(settings, plan: plan)
            settings = TrainingInduction.Submission.answered(input)
                .applyingAccountMetadata(to: settings, plan: plan)
            applyInductionPlan(plan, settings: settings)
            return
        }
        #endif

        guard let userID = await service.currentUserID() else {
            guard accountGeneration.accepts(accountToken) else { return }
            alertMessage = "Sign in again to build your plan."
            return
        }
        guard accountGeneration.accepts(accountToken) else { return }
        do {
            var settings = try await service.createSettingsIfNeeded(userID: userID)
                .rebound(to: userID)
            guard accountGeneration.accepts(accountToken) else { return }

            /* Archive the current overlay before saving its replacement. The
               revision is persisted first, so a failed retry reuses the same
               new IDs without overwriting rows referenced by workout history. */
            var current = data
            current.settings = settings
            if TrainingInduction.hasRestorableOverlay(in: current) {
                settings = TrainingInduction.invalidatingPlanMetadata(
                    settings,
                    additionalDayIDs: TrainingInduction.legacyGeneratedDayIDs(
                        in: current,
                        userID: userID
                    )
                )
                try await service.upsert(settings, table: "settings", onConflict: "user_id")
                guard accountGeneration.accepts(accountToken) else { return }
                data.settings = settings
                await saveLocalSnapshot()
                guard accountGeneration.accepts(accountToken) else { return }
            }
            let plan = TrainingInduction.generate(
                userID: userID,
                input: input,
                existingPrograms: data.programs,
                generationRevision: TrainingInduction.generationRevision(settings)
            )
            settings = TrainingInduction.markingPendingPlan(settings, plan: plan)
            try await service.upsert(settings, table: "settings", onConflict: "user_id")
            guard accountGeneration.accepts(accountToken) else { return }
            data.settings = settings
            await saveLocalSnapshot()
            guard accountGeneration.accepts(accountToken) else { return }
            try await service.saveInductionPlan(plan)
            guard accountGeneration.accepts(accountToken) else { return }
            settings = TrainingInduction.Submission.answered(input)
                .applyingAccountMetadata(to: settings, plan: plan)
            try await service.upsert(settings, table: "settings", onConflict: "user_id")
            guard accountGeneration.accepts(accountToken) else { return }
            applyInductionPlan(plan, settings: settings)
            await saveLocalSnapshot()
            guard accountGeneration.accepts(accountToken) else { return }
        } catch {
            guard accountGeneration.accepts(accountToken) else { return }
            alertMessage = error.localizedDescription
        }
    }

    private func applyInductionPlan(
        _ plan: TrainingInduction.GeneratedPlan,
        settings: UserSettings
    ) {
        data = TrainingInduction.applyingGeneratedPlan(plan, settings: settings, to: data)
    }

    /// Puts the original programme back and removes only generated overlay rows.
    func restoreOriginalProgramme() async {
        let accountToken = accountGeneration.token
        guard !isBusy else { return }
        isBusy = true
        defer {
            if accountGeneration.accepts(accountToken) { isBusy = false }
        }
        guard let userID = profile?.userID ?? data.settings?.userID,
              let restoration = TrainingInduction.restoration(in: data, userID: userID),
              let restoredSettings = restoration.dashboard.settings else { return }
        do {
            try await service.upsert(restoredSettings, table: "settings", onConflict: "user_id")
            guard accountGeneration.accepts(accountToken) else { return }
            data = restoration.dashboard
            data.settings = restoredSettings
            await saveLocalSnapshot()
            guard accountGeneration.accepts(accountToken) else { return }
        } catch {
            guard accountGeneration.accepts(accountToken) else { return }
            alertMessage = error.localizedDescription
        }
    }

    /// Store a rewritten predefined list, keyed so an edit to one meal on one
    /// goal never quietly rewrites the others. An emptied list falls back to
    /// the protocol default.
    func saveMealProtocolOverride(key: String, lines: [String]) async {
        guard let profile, var settings = data.settings else { return }
        settings = settings.rebound(to: profile.userID)
        var overrides = settings.addons["meal_protocol_overrides"]?.objectValue ?? [:]
        if lines.isEmpty {
            overrides.removeValue(forKey: key)
        } else {
            overrides[key] = .array(lines.map { .string($0) })
        }
        settings.addons["meal_protocol_overrides"] = .object(overrides)
        data.settings = settings
        await persistUpsert(settings, table: "settings", onConflict: "user_id")
    }

    private func verifiedPersistenceOwnerID(_ expectedOwnerID: UUID? = nil) -> UUID? {
        guard let ownerID = expectedOwnerID ?? data.profile?.userID ?? data.settings?.userID,
              TrainingInduction.belongsToAccount(data, userID: ownerID) else {
            return nil
        }
        return ownerID
    }

    private func persistUpsert<T: Encodable & Sendable>(
        _ value: T,
        table: String,
        onConflict: String? = nil,
        ownerID: UUID? = nil,
        surfacePermanentFailure: Bool = true
    ) async {
        let persistenceOwnerID = verifiedPersistenceOwnerID(ownerID)
        await saveLocalSnapshot()
        do {
            try await service.upsert(value, table: table, onConflict: onConflict)
            lastSyncAt = .now
        } catch {
            guard let userID = persistenceOwnerID else { return }
            do {
                let operation = try OfflineOperation.upsert(value, table: table, onConflict: onConflict)
                switch SyncFailurePolicy.classify(error) {
                case .transient:
                    try await offlineStore.enqueue(operation, for: userID)
                    pendingSyncCount = (try? await offlineStore.pendingOperations(for: userID).count)
                        ?? pendingSyncCount + 1
                    /* Silent, like the other offline saves. Working without a
                       connection is the feature, not an incident report. */
                case .permanent:
                    try await offlineStore.recordFailure(
                        operation,
                        reason: error.localizedDescription,
                        for: userID
                    )
                    if surfacePermanentFailure {
                        alertMessage = "APEX could not sync that change. Please try again after refreshing your account."
                    }
                }
            } catch {
                if surfacePermanentFailure {
                    alertMessage = "APEX could not preserve that change offline. \(error.localizedDescription)"
                }
            }
        }
    }

    private func persistDelete(table: String, id: UUID, ownerID: UUID? = nil) async {
        let persistenceOwnerID = verifiedPersistenceOwnerID(ownerID)
        await saveLocalSnapshot()
        do {
            try await service.delete(table: table, id: id)
            lastSyncAt = .now
        } catch {
            guard let userID = persistenceOwnerID else { return }
            do {
                let operation = OfflineOperation.delete(table: table, id: id)
                switch SyncFailurePolicy.classify(error) {
                case .transient:
                    try await offlineStore.enqueue(operation, for: userID)
                    pendingSyncCount = (try? await offlineStore.pendingOperations(for: userID).count)
                        ?? pendingSyncCount + 1
                    /* Silent, like the other offline saves. Working without a
                       connection is the feature, not an incident report. */
                case .permanent:
                    try await offlineStore.recordFailure(
                        operation,
                        reason: error.localizedDescription,
                        for: userID
                    )
                    alertMessage = "APEX could not sync that change. Please try again after refreshing your account."
                }
            } catch {
                alertMessage = "APEX could not preserve that change offline. \(error.localizedDescription)"
            }
        }
    }

    private func saveLocalSnapshot() async {
        guard let userID = verifiedPersistenceOwnerID() else { return }
        try? await offlineStore.saveDashboard(data, for: userID)
    }

    private func recalculateLocalStructuredDay(_ date: String, userID: UUID) async {
        let meals = data.loggedMeals.filter { $0.localDate == date }
        let existing = data.dailyLogs.first { $0.date == date }
        let manualKcal = existing?.nutritionSource == "manual" ? existing?.kcal : existing?.manualKcal
        let manualProtein = existing?.nutritionSource == "manual" ? existing?.proteinG : existing?.manualProteinG
        let manualFat = existing?.nutritionSource == "manual" ? existing?.fatG : existing?.manualFatG
        let manualCarbs = existing?.nutritionSource == "manual" ? existing?.carbsG : existing?.manualCarbsG
        let row = DailyLog(
            id: existing?.id ?? APEXStableID.scopedUUID(namespace: "daily-log", date: date, userID: userID),
            userID: userID,
            date: date,
            kcal: meals.isEmpty ? manualKcal : Int(meals.reduce(0) { $0 + $1.totalKcal }.rounded()),
            proteinG: meals.isEmpty ? manualProtein : Int(meals.reduce(0) { $0 + $1.totalProteinG }.rounded()),
            fatG: meals.isEmpty ? manualFat : Int(meals.reduce(0) { $0 + $1.totalFatG }.rounded()),
            carbsG: meals.isEmpty ? manualCarbs : Int(meals.reduce(0) { $0 + $1.totalCarbsG }.rounded()),
            waterL: existing?.waterL ?? 0,
            estimatedTDEE: existing?.estimatedTDEE,
            computedPAL: existing?.computedPAL,
            activityMode: existing?.activityMode ?? "quick",
            weightKG: existing?.weightKG,
            nutritionSource: meals.isEmpty ? "manual" : "structured",
            manualKcal: manualKcal,
            manualProteinG: manualProtein,
            manualFatG: manualFat,
            manualCarbsG: manualCarbs
        )
        data.dailyLogs.removeAll { $0.date == date }
        data.dailyLogs.append(row)
        if let resolvedDate = ISO8601DateFormatter.apexDateOnly.date(from: date) {
            await syncFoodHydrationEvent(on: resolvedDate, ownerID: userID)
        }
        if HealthKitManager.shared.waterWriteState == .authorized,
           let resolvedDate = ISO8601DateFormatter.apexDateOnly.date(from: date) {
            try? await HealthKitManager.shared.syncFoodWater(
                liters: foodHydrationLiters(on: resolvedDate),
                on: resolvedDate,
                accountID: userID
            )
        }
    }

    private func plannedMealSlot(_ meal: Meal) -> String {
        let lower = meal.name.lowercased()
        if lower.contains("snack") || lower.contains("shake") { return "snack" }
        let hour = Int(meal.time.split(separator: ":").first ?? "0") ?? 0
        if hour < 11 { return "breakfast" }
        if hour < 16 { return "lunch" }
        return "dinner"
    }

    private func considerWeeklyCalibration() async {
        guard var profile else { return }
        let today = Date().apexDateKey
        guard profile.calibrationHistory.last?.appliedAt.hasPrefix(today) != true else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -13, to: .now)?.apexDateKey ?? today
        let samples = data.dailyLogs
            .filter {
                $0.date >= cutoff && $0.date <= today
                    && $0.kcal != nil && $0.weightKG != nil && $0.estimatedTDEE != nil
            }
            .sorted { $0.date < $1.date }
        guard samples.count >= 12,
              let firstDate = ISO8601DateFormatter.apexDateOnly.date(from: samples.first?.date ?? ""),
              let lastDate = ISO8601DateFormatter.apexDateOnly.date(from: samples.last?.date ?? "")
        else { return }

        let ema = EnergyEngine.weightEMA(samples.compactMap(\.weightKG))
        guard let startWeight = ema.first, let endWeight = ema.last else { return }
        let elapsedDays = max(1, Calendar.current.dateComponents([.day], from: firstDate, to: lastDate).day ?? 1)
        let meanIntake = samples.reduce(0) { $0 + Double($1.kcal ?? 0) } / Double(samples.count)
        let predicted = samples.reduce(0) { $0 + Double($1.estimatedTDEE ?? 0) } / Double(samples.count)
        let next = EnergyEngine.calibratedK(
            currentK: profile.calibrationK,
            meanDailyIntake: meanIntake,
            predictedDailyTDEE: predicted,
            startingEMAWeight: startWeight,
            endingEMAWeight: endWeight,
            elapsedDays: elapsedDays
        )
        guard abs(next - profile.calibrationK) >= 0.001 else { return }
        let storedPerDay = (endWeight - startWeight) * 7_700 / Double(elapsedDays)
        let observed = meanIntake - storedPerDay
        let previous = profile.calibrationK
        profile.calibrationK = next
        profile.calibrationHistory.append(.init(
            appliedAt: Date().ISO8601Format(),
            previousK: previous,
            nextK: next,
            observedTDEE: observed,
            predictedTDEE: predicted,
            sampleDays: samples.count
        ))
        profile.calibrationHistory = Array(profile.calibrationHistory.suffix(52))
        profile.updatedAt = Date().ISO8601Format()
        data.profile = profile
        await persistUpsert(profile, table: "profile", onConflict: "user_id")
    }

    private func flushPendingChanges(for userID: UUID) async {
        guard let operations = try? await offlineStore.pendingOperations(for: userID) else { return }
        pendingSyncCount = operations.count
        let report = await OfflineQueueDrainer.drain(
            operations,
            replay: { [service] operation in
                try await service.replay(operation)
            },
            remove: { [offlineStore] operation in
                try await offlineStore.removeOperation(operation.id, for: userID)
            },
            quarantine: { [offlineStore] operation, reason in
                try await offlineStore.quarantine(operation, reason: reason, for: userID)
            },
            classify: SyncFailurePolicy.classify
        )
        pendingSyncCount = (try? await offlineStore.pendingOperations(for: userID).count) ?? max(
            0,
            operations.count - report.succeeded - report.quarantined
        )
        if report.succeeded > 0 { lastSyncAt = .now }
    }

    private func startRealtimeSync() async {
        HealthKitManager.shared.startBackgroundMonitoring { [weak self] snapshot in
            await self?.applyHealthSnapshot(snapshot)
        }
        do {
            try await service.startRealtime { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleRealtimeRefresh()
                }
            }
        } catch {
            // Foreground refresh and the offline outbox remain available if
            // Realtime is temporarily unavailable.
        }
    }

    private func scheduleRealtimeRefresh() {
        realtimeDebounceTask?.cancel()
        realtimeDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard Task.isCancelled == false else { return }
            await self?.refresh()
        }
    }

    private func importHealthWorkoutIfNeeded(_ workout: HealthWorkoutSnapshot) async {
        guard let profile else { return }
        guard data.importedActivities.contains(where: { $0.id == workout.id }) == false else { return }

        let overlapsOrbit = data.orbitRuns.contains { run in
            guard let start = ISO8601DateFormatter().date(from: run.startedAt) else { return false }
            return abs(start.timeIntervalSince(workout.startedAt)) < 5 * 60
        }
        guard overlapsOrbit == false else { return }

        let avatarKind: String
        switch workout.kind {
        case "run", "walk", "hiit": avatarKind = "endurance"
        case "strength": avatarKind = "strength"
        case "mobility": avatarKind = "mobility"
        default: avatarKind = "mobility"
        }

        let imported = ImportedActivity(
            id: workout.id,
            userID: profile.userID,
            date: workout.date,
            kind: avatarKind,
            activity: workout.activityName,
            durationMinutes: workout.durationMinutes,
            source: "Apple Health"
        )
        data.importedActivities.append(imported)
        await persistUpsert(imported, table: "imported_activities")

        guard data.activityLogs.contains(where: { $0.id == workout.id }) == false else { return }

        let type: ActivityType?
        switch workout.kind {
        case "run": type = data.activityTypes.first { $0.id == "jog-run" }
        case "walk":
            type = data.activityTypes.first {
                $0.id == (workout.distanceKM == nil ? "casual-walk" : "walking-distance")
            }
        case "strength": type = data.activityTypes.first { $0.id == "apex-strength" }
        case "hiit": type = data.activityTypes.first { $0.id == "focus-hiit" }
        case "mobility": type = data.activityTypes.first { $0.id == "mobility" }
        default: type = nil
        }
        guard let type else { return }
        let now = Date().ISO8601Format()
        let computed = EnergyEngine.blockCalories(
            type: type,
            quantity: 1,
            durationMinutes: workout.durationMinutes,
            distanceKM: workout.distanceKM,
            watchKcal: workout.activeEnergyKcal,
            weightKG: profile.weightKG
        )
        let log = ActivityLog(
            id: workout.id,
            userID: profile.userID,
            date: workout.date,
            typeID: type.id,
            quantity: 1,
            durationMinutes: type.inputStyle == .duration ? workout.durationMinutes : nil,
            distanceKM: workout.distanceKM,
            watchKcal: workout.activeEnergyKcal,
            computedKcal: computed,
            source: "workout_module",
            reconciled: true,
            createdAt: now,
            updatedAt: now
        )
        data.activityLogs.append(log)
        await persistUpsert(log, table: "activity_logs")
    }
}
