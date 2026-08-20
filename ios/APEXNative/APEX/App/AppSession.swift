import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppSession {
    var route: AppRoute = .launching
    var selectedPersona: Persona?
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
    private var bootstrapped = false
    private var realtimeDebounceTask: Task<Void, Never>?

    var profile: Profile? { data.profile }
    var isAuthenticated: Bool { data.profile != nil }
    var interfaceMode: PortalUIMode { PortalUIMode.current(from: data.settings) }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true

        #if DEBUG
        /* Jump straight to a first-run screen for visual checking. Debug only,
           and it never touches the network, so inspecting the questionnaire
           does not leave a stray account behind. */
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-apex-preview"),
           index + 1 < ProcessInfo.processInfo.arguments.count {
            switch ProcessInfo.processInfo.arguments[index + 1] {
            case "welcome": route = .welcome
            case "induction": route = .induction
            case "consent": route = .consent
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
            selectedPersona = .constantine
            route = .portal
            return
        }
        #endif

        if let userID = await service.currentUserID() {
            if let cached = try? await offlineStore.loadDashboard(for: userID),
               cached.profile?.userID == userID {
                data = cached
                selectedPersona = cached.profile?.persona
                route = .portal
            }
            do {
                await flushPendingChanges(for: userID)
                try await refreshDashboard(expectedUserID: userID)
                selectedPersona = data.profile?.persona
                route = .portal
                await startRealtimeSync()
                return
            } catch {
                if data.profile?.userID == userID {
                    alertMessage = "APEX is offline. Your last synced data and new entries remain available."
                    return
                }
            }
        }

        /* No session: the public front door, not the portrait wall. The four
           bespoke accounts reach their portraits from a link on it. */
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
        isBusy = true
        defer { isBusy = false }
        do {
            let userID = try await service.signIn(email: email, password: password)
            try await refreshDashboard(expectedUserID: userID)
            /* The portrait entrance promises a particular person, so it still
               checks. The public email door promises nothing and skips it. */
            if let expected = selectedPersona {
                guard let actual = data.profile?.persona else {
                    throw APEXServiceError.configurationMissing
                }
                guard actual == expected else {
                    try await service.signOut()
                    data = .empty
                    throw APEXServiceError.personaMismatch(expected: expected, actual: actual)
                }
            }
            if let persona = data.profile?.persona {
                defaults.set(persona.rawValue, forKey: "apex.lastPersona")
            }
            route = data.profile == nil ? .induction : .portal
            await startRealtimeSync()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// Create an account, then send it straight into the questionnaire: there
    /// is nothing to show a new account until it has answered.
    func signUp(email: String, password: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await service.signUp(email: email, password: password)
            selectedPersona = nil
            data = .empty
            route = .induction
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let userID = try await service.signInWithApple(idToken: idToken, nonce: nonce)
            selectedPersona = nil
            try await refreshDashboard(expectedUserID: userID)
            /* A returning Apple account already has a profile and goes home. A
               first-time one has none, and answers the questionnaire instead. */
            route = data.profile == nil ? .induction : .portal
            await startRealtimeSync()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// Turn the questionnaire into a profile and a first twelve weeks.
    func completeInduction(_ input: TrainingInduction.Input) async {
        isBusy = true
        defer { isBusy = false }
        guard let userID = await service.currentUserID() else {
            alertMessage = "Sign in again to continue."
            route = .welcome
            return
        }
        do {
            /* The row is created with the column defaults and only the answers
               that map onto it, rather than inventing a height and a weight
               nobody gave. Those are asked for later, in the body profile. */
            let profile = try await service.createProfileIfNeeded(
                userID: userID,
                goal: TrainingInduction.goalColumn(for: input.goal)
            )
            data.profile = profile

            let plan = TrainingInduction.generate(userID: userID, input: input)
            try await service.saveInductionPlan(plan)
            try await refreshDashboard(expectedUserID: userID)
            await resolveEntitlements()
            route = .consent
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// The last step of a first run: permissions have been offered, the trial
    /// is running, and the app opens for real.
    func finishOnboarding() async {
        route = .portal
        await startRealtimeSync()
        await refreshNudges()
    }

    func signOut() async {
        isBusy = true
        defer { isBusy = false }
        do { try await service.signOut() }
        catch { alertMessage = error.localizedDescription }
        data = .empty
        pendingSyncCount = 0
        navigationPath.removeAll()
        selectedPersona = nil
        route = .welcome
    }

    func refreshDashboard(expectedUserID: UUID? = nil) async throws {
        isRefreshing = true
        defer { isRefreshing = false }
        let next = try await service.loadDashboard()
        if let expectedUserID, next.profile?.userID != expectedUserID {
            throw APEXServiceError.configurationMissing
        }
        data = next
        lastSyncAt = .now
        if let userID = next.profile?.userID {
            try? await offlineStore.saveDashboard(next, for: userID)
            pendingSyncCount = (try? await offlineStore.pendingOperations(for: userID).count) ?? 0
        }
        await considerWeeklyCalibration()
        await resolveEntitlements()
    }

    /// Work out what this account may use, and start the trial clock on the
    /// first open rather than at account creation, so an account made in
    /// advance does not expire sitting unopened.
    func resolveEntitlements() async {
        guard var profile else { return }
        if profile.foundingMember != true, profile.trialStartedAt == nil {
            profile.trialStartedAt = Date().ISO8601Format()
            profile.updatedAt = Date().ISO8601Format()
            data.profile = profile
            await persistUpsert(profile, table: "profile", onConflict: "user_id")
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
            alertMessage = "APEX is using its last local view. \(error.localizedDescription)"
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
        await refresh()
    }

    func handleAuthCallback(_ url: URL) async {
        do {
            try await service.handleAuthCallback(url)
            try await refreshDashboard()
            selectedPersona = data.profile?.persona
            route = .portal
        } catch {
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
        recalculateLocalStructuredDay(day, userID: profile.userID)
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
        let targets = EnergyEngine.targets(profile: profile, logs: logs, catalog: data.activityTypes)
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

    func updateDailyLog(_ row: DailyLog) async {
        if let index = data.dailyLogs.firstIndex(where: { $0.id == row.id }) {
            data.dailyLogs[index] = row
        } else {
            data.dailyLogs.append(row)
        }
        await persistUpsert(row, table: "daily_logs", onConflict: "user_id,date")
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
        guard var settings = data.settings else { return }
        transform(&settings)
        data.settings = settings
        await persistUpsert(settings, table: "settings", onConflict: "user_id")
    }

    func setInterfaceMode(_ mode: PortalUIMode) async {
        /* Simple and Advanced swap the *root* of the navigation stack, so
           switching while somewhere pushed -- Nutrition, Training, anywhere --
           changed the screen underneath and left the pushed one on top. From
           the outside the toggle simply did nothing. Returning to the root is
           what the switch is asking for: show me that mode. */
        navigationPath = []
        await updateSettings { settings in
            settings.addons["uiMode"] = .string(mode.rawValue)
        }
    }

    static func waterWatermarkKey(_ date: String) -> String { "apex.hk.water.applied.\(date)" }

    /*
     * Every water change flows through here so the HealthKit watermark stays
     * consistent. Additions are mirrored into HealthKit and raise the
     * watermark by the same amount, so the next sync sees no new water and
     * cannot double count. Reductions stay local: HealthKit samples APEX did
     * not author are not ours to delete, and leaving the watermark where it
     * is means the removed amount is never re-imported.
     */
    @discardableResult
    func adjustWater(deltaLiters: Double, on date: Date) async -> Double {
        guard let profile else { return 0 }
        let key = date.apexDateKey
        let existing = data.dailyLogs.first { $0.date == key }
        let current = existing?.waterL ?? 0
        let next = min(6, max(0, ((current + deltaLiters) * 100).rounded() / 100))
        guard next != current else { return current }

        var row = existing ?? DailyLog(
            id: APEXStableID.scopedUUID(namespace: "daily-log", date: key, userID: profile.userID),
            userID: profile.userID, date: key,
            kcal: nil, proteinG: nil, fatG: nil, carbsG: nil, waterL: 0,
            estimatedTDEE: nil, computedPAL: nil,
            activityMode: data.activityLogs.contains { $0.date == key } ? "precise" : "quick",
            weightKG: nil
        )
        row.waterL = next
        await updateDailyLog(row)

        let applied = next - current
        if applied > 0 {
            try? await HealthKitManager.shared.saveWater(liters: applied, date: date)
            let defaults = UserDefaults.standard
            let watermark = defaults.object(forKey: Self.waterWatermarkKey(key)) as? Double
            if let watermark {
                defaults.set(watermark + applied, forKey: Self.waterWatermarkKey(key))
            }
        }
        return next
    }

    func setWaterTotal(_ liters: Double, on date: Date) async {
        let key = date.apexDateKey
        let current = data.dailyLogs.first { $0.date == key }?.waterL ?? 0
        await adjustWater(deltaLiters: liters - current, on: date)
    }

    func applyHealthSnapshot(_ snapshot: HealthSnapshot) async {
        guard let profile else { return }
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
        }

        if let dietaryWaterL = snapshot.dietaryWaterL, dietaryWaterL > 0 {
            let existing = data.dailyLogs.first { $0.date == snapshot.date }
            /*
             * Import only water HealthKit has learned since the last sync.
             * Taking max(local, healthKit) ratcheted the total upward forever:
             * APEX writes its own additions into HealthKit, so any manual
             * decrease was restored on the next refresh and could never stick.
             * The watermark keeps the person's edit authoritative while water
             * logged elsewhere (the Watch, another app) still arrives.
             */
            let watermarkKey = Self.waterWatermarkKey(snapshot.date)
            let defaults = UserDefaults.standard
            let previouslyApplied = defaults.object(forKey: watermarkKey) as? Double
            var nextWater = existing?.waterL ?? 0
            if let previouslyApplied {
                let newlyLogged = dietaryWaterL - previouslyApplied
                if newlyLogged > 0.001 {
                    nextWater = min(6, ((nextWater + newlyLogged) * 100).rounded() / 100)
                }
            } else {
                /* First sight of this date on this device: adopt whichever
                   record is richer, then track from there. */
                nextWater = max(nextWater, dietaryWaterL)
            }
            defaults.set(dietaryWaterL, forKey: watermarkKey)

            if nextWater != existing?.waterL || existing == nil {
                let row = DailyLog(
                    id: existing?.id ?? UUID(), userID: profile.userID, date: snapshot.date,
                    kcal: existing?.kcal, proteinG: existing?.proteinG,
                    fatG: existing?.fatG, carbsG: existing?.carbsG,
                    waterL: nextWater,
                    estimatedTDEE: existing?.estimatedTDEE,
                    computedPAL: existing?.computedPAL,
                    activityMode: existing?.activityMode ?? "quick",
                    weightKG: snapshot.weightKG ?? existing?.weightKG
                )
                await updateDailyLog(row)
            }
        }

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
        }

        for workout in snapshot.workouts {
            await importHealthWorkoutIfNeeded(workout)
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
        let envelope = try await service.lookupFood(barcode: barcode)
        return FoodLookupEnvelope(
            state: envelope.state,
            source: envelope.source,
            food: envelope.food.map(FoodHydration.resolved),
            results: envelope.results?.map(FoodHydration.resolved),
            message: envelope.message
        )
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

        let key = "ios-meal-\(draft.id.uuidString.lowercased())"
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
            loggedAs: draft.loggedAs,
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
            loggedAs: draft.loggedAs,
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
                waterML: item.waterML100.map { $0 * item.equivalentAmount / 100 }
            )
        }

        if let replaced = draft.replaceMealID {
            data.loggedMeals.removeAll { $0.id == replaced }
            data.loggedFoodEntries.removeAll { $0.mealID == replaced }
        }
        data.loggedMeals.removeAll { $0.id == draft.id }
        data.loggedMeals.insert(localMeal, at: 0)
        await refreshNudges()
        data.loggedFoodEntries.removeAll { $0.mealID == draft.id }
        data.loggedFoodEntries.insert(contentsOf: localEntries, at: 0)
        recalculateLocalStructuredDay(draft.localDate, userID: profile.userID)
        await saveLocalSnapshot()

        do {
            _ = try await service.logStructuredMeal(meal: request, entries: entryRequests)
            try await refreshDashboard()
        } catch {
            let payload = StructuredMealRPCPayload(pMeal: request, pEntries: entryRequests)
            try await offlineStore.enqueue(.rpc("log_structured_meal", params: payload), for: profile.userID)
            pendingSyncCount = (try? await offlineStore.pendingOperations(for: profile.userID).count) ?? pendingSyncCount + 1
            /* Saved offline and queued. Deliberately silent: this is the app
               working, not an event, and pendingSyncCount already shows it.
               Naming the backend on a user's screen helps nobody. */
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
            recalculateLocalStructuredDay(key, userID: userID)
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
            waterML: food.waterML100.map { $0 * equivalentAmount / 100 }
        )

        data.loggedMeals.insert(localMeal, at: 0)
        await refreshNudges()
        data.loggedFoodEntries.insert(localEntry, at: 0)
        recalculateLocalStructuredDay(date.apexDateKey, userID: profile.userID)
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
    }

    func deleteLoggedMeal(_ meal: LoggedMeal) async {
        guard let profile else { return }
        data.loggedMeals.removeAll { $0.id == meal.id }
        data.loggedFoodEntries.removeAll { $0.mealID == meal.id }
        recalculateLocalStructuredDay(meal.localDate, userID: profile.userID)
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
                alertMessage = "Meal removal is queued and will sync automatically."
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

    func completeWorkout(day: ProgramDay, exercises: [Exercise], lite: Bool) async {
        let inputs = exercises.flatMap { exercise in
            (1...max(exercise.sets, 1)).map { set in
                WorkoutSetInput(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    setNumber: set,
                    weightKG: nil,
                    reps: exercise.repMax > 0 ? exercise.repMax : nil,
                    rir: 2,
                    skipped: false
                )
            }
        }
        await completeWorkout(day: day, setInputs: inputs, lite: lite, startedAt: .now)
    }

    /// Returns the finished session's id so the caller can show its receipt.
    @discardableResult
    func completeWorkout(
        day: ProgramDay,
        setInputs: [WorkoutSetInput],
        lite: Bool,
        startedAt: Date
    ) async -> UUID? {
        guard let profile else { return nil }
        let now = Date().ISO8601Format()
        let isDeload = TrainingAdjustmentEngine.isDeload(
            on: Date().apexDateKey,
            marks: data.deloadMarks ?? []
        )
        let workout = WorkoutSession(
            id: UUID(), userID: profile.userID, date: Date().apexDateKey,
            programDayID: day.id, isLite: lite, isDeload: isDeload,
            isEventRecovery: false, completed: true, qualityScore: 1,
            startedAt: startedAt.ISO8601Format(), completedAt: now, notes: "Completed in APEX iOS"
        )
        let logs = setInputs.map { input in
            WorkoutLog(
                id: UUID(), userID: profile.userID, sessionID: workout.id,
                exerciseID: input.exerciseID, exerciseName: input.exerciseName,
                setNumber: input.setNumber, weightKG: input.weightKG,
                reps: input.reps, rir: input.rir, skipped: input.skipped,
                overrideFlag: false, createdAt: now
            )
        }
        data.workoutSessions.append(workout)
        data.workoutLogs.append(contentsOf: logs)
        await persistUpsert(workout, table: "workout_sessions")
        for log in logs {
            await persistUpsert(log, table: "workout_logs")
        }
        if let activityType = data.activityTypes.first(where: { $0.id == "apex-strength" }) {
            let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
            await addActivity(type: activityType, date: .now, durationMinutes: elapsed)
        }
        return workout.id
    }

    func toggleDeload(on date: Date = .now) async {
        guard let profile else { return }
        let day = date.apexDateKey
        if let existing = (data.deloadMarks ?? []).first(where: { $0.date == day }) {
            data.deloadMarks?.removeAll { $0.id == existing.id }
            await persistDelete(table: "deload_marks", id: existing.id)
        } else {
            let mark = DeloadMark(id: UUID(), userID: profile.userID, date: day)
            if data.deloadMarks == nil { data.deloadMarks = [] }
            data.deloadMarks?.append(mark)
            await persistUpsert(mark, table: "deload_marks", onConflict: "user_id,date")
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

        let kcal = Int((foodSuggestion?.nutrients.kcal ?? Double(adjustment.kcal)).rounded())
        let protein = Int((foodSuggestion?.nutrients.proteinG ?? Double(adjustment.proteinG)).rounded())
        let fat = Int((foodSuggestion?.nutrients.fatG ?? Double(adjustment.fatG)).rounded())
        let carbs = Int((foodSuggestion?.nutrients.carbsG ?? Double(adjustment.carbsG)).rounded())
        let existing = data.dailyLogs.first { $0.date == run.localDate }
        let day = DailyLog(
            id: existing?.id ?? APEXStableID.scopedUUID(namespace: "daily-log", date: run.localDate, userID: profile.userID),
            userID: profile.userID,
            date: run.localDate,
            kcal: (existing?.kcal ?? 0) + kcal,
            proteinG: (existing?.proteinG ?? 0) + protein,
            fatG: (existing?.fatG ?? 0) + fat,
            carbsG: (existing?.carbsG ?? 0) + carbs,
            waterL: existing?.waterL ?? 0,
            estimatedTDEE: existing?.estimatedTDEE,
            computedPAL: existing?.computedPAL,
            activityMode: existing?.activityMode ?? "precise",
            weightKG: existing?.weightKG ?? profile.weightKG,
            nutritionSource: "manual",
            manualKcal: (existing?.manualKcal ?? existing?.kcal ?? 0) + kcal,
            manualProteinG: (existing?.manualProteinG ?? existing?.proteinG ?? 0) + protein,
            manualFatG: (existing?.manualFatG ?? existing?.fatG ?? 0) + fat,
            manualCarbsG: (existing?.manualCarbsG ?? existing?.carbsG ?? 0) + carbs
        )
        await updateDailyLog(day)

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
            programDays: data.programDays,
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
        let overlapping = data.activityLogs.filter {
            $0.date == run.localDate
                && ($0.typeID == "jog-run" || ($0.typeID == "watch-kcal" && $0.source != "orbit"))
        }
        for log in overlapping {
            data.activityLogs.removeAll { $0.id == log.id }
            await persistDelete(table: "activity_logs", id: log.id)
        }

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
        data.activityLogs.removeAll { $0.id == id }
        data.activityLogs.append(activity)
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
        let targets = EnergyEngine.targets(profile: profile, logs: dayLogs, catalog: data.activityTypes)
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
            sortOrder: weekday
        )

        let replaced = data.exercises.filter { $0.programDayID == day.id }
        let rows = picks.enumerated().map { index, pick -> Exercise in
            return Exercise(
                id: UUID(),
                userID: userID,
                programDayID: day.id,
                name: pick.item.name,
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

        let usable = exercises.filter { draft in
            if let treadmill = draft.treadmill { return treadmill.durationMinutes > 0 }
            return draft.sets.contains { $0.reps > 0 }
        }
        guard !usable.isEmpty else { return false }

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

        var proposed: [WorkoutLog] = []
        for (index, draft) in usable.enumerated() {
            let exerciseTime = base + Double(index) * 60
            if let treadmill = draft.treadmill {
                proposed.append(
                    WorkoutLog(
                        id: UUID(),
                        userID: userID,
                        sessionID: workout.id,
                        exerciseID: nil,
                        exerciseName: ManualWorkout.encodeTreadmill(name: draft.name, metrics: treadmill),
                        setNumber: 1,
                        weightKG: nil,
                        reps: nil,
                        rir: nil,
                        skipped: false,
                        overrideFlag: false,
                        createdAt: formatter.string(from: Date(timeIntervalSince1970: exerciseTime))
                    )
                )
                continue
            }
            for (setIndex, set) in draft.sets.filter({ $0.reps > 0 }).enumerated() {
                proposed.append(
                    WorkoutLog(
                        id: UUID(),
                        userID: userID,
                        sessionID: workout.id,
                        exerciseID: nil,
                        exerciseName: draft.name,
                        setNumber: setIndex + 1,
                        weightKG: set.weightKG > 0 ? set.weightKG : nil,
                        reps: set.reps,
                        rir: nil,
                        skipped: false,
                        overrideFlag: false,
                        createdAt: formatter.string(
                            from: Date(timeIntervalSince1970: exerciseTime + Double(setIndex) * 0.1)
                        )
                    )
                )
            }
        }

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
        guard let profile, var settings = data.settings else { return }
        let plan = TrainingInduction.generate(
            userID: profile.userID,
            input: input,
            existingPrograms: data.programs
        )

        for program in plan.programs {
            if let index = data.programs.firstIndex(where: { $0.id == program.id }) {
                data.programs[index] = program
            } else {
                data.programs.append(program)
            }
        }
        for day in plan.programDays {
            if let index = data.programDays.firstIndex(where: { $0.id == day.id }) {
                data.programDays[index] = day
            } else {
                data.programDays.append(day)
            }
        }
        for exercise in plan.exercises {
            if let index = data.exercises.firstIndex(where: { $0.id == exercise.id }) {
                data.exercises[index] = exercise
            } else {
                data.exercises.append(exercise)
            }
        }
        settings.addons["newbie_mode"] = .bool(true)
        settings.addons["training_induction"] = .object(plan.induction)
        data.settings = settings

        for program in plan.programs { await persistUpsert(program, table: "programs") }
        for day in plan.programDays { await persistUpsert(day, table: "program_days") }
        for exercise in plan.exercises { await persistUpsert(exercise, table: "exercises") }
        await persistUpsert(settings, table: "settings", onConflict: "user_id")
    }

    /// Puts the original programme back by clearing the generated overlay.
    func restoreOriginalProgramme() async {
        guard var settings = data.settings else { return }
        settings.addons["newbie_mode"] = .bool(false)
        settings.addons.removeValue(forKey: "training_induction")
        data.settings = settings
        await persistUpsert(settings, table: "settings", onConflict: "user_id")
    }

    /// Store a rewritten predefined list, keyed so an edit to one meal on one
    /// goal never quietly rewrites the others. An emptied list falls back to
    /// the protocol default.
    func saveMealProtocolOverride(key: String, lines: [String]) async {
        guard var settings = data.settings else { return }
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

    private func persistUpsert<T: Encodable & Sendable>(
        _ value: T,
        table: String,
        onConflict: String? = nil
    ) async {
        await saveLocalSnapshot()
        do {
            try await service.upsert(value, table: table, onConflict: onConflict)
            lastSyncAt = .now
        } catch {
            guard let userID = profile?.userID else { return }
            do {
                let operation = try OfflineOperation.upsert(value, table: table, onConflict: onConflict)
                try await offlineStore.enqueue(operation, for: userID)
                pendingSyncCount = (try? await offlineStore.pendingOperations(for: userID).count) ?? pendingSyncCount + 1
                alertMessage = "Saved on this iPhone. APEX will sync it automatically when the connection returns."
            } catch {
                alertMessage = "APEX could not preserve that change offline. \(error.localizedDescription)"
            }
        }
    }

    private func persistDelete(table: String, id: UUID) async {
        await saveLocalSnapshot()
        do {
            try await service.delete(table: table, id: id)
            lastSyncAt = .now
        } catch {
            guard let userID = profile?.userID else { return }
            do {
                try await offlineStore.enqueue(.delete(table: table, id: id), for: userID)
                pendingSyncCount = (try? await offlineStore.pendingOperations(for: userID).count) ?? pendingSyncCount + 1
                alertMessage = "Saved on this iPhone. APEX will sync it automatically when the connection returns."
            } catch {
                alertMessage = "APEX could not preserve that change offline. \(error.localizedDescription)"
            }
        }
    }

    private func saveLocalSnapshot() async {
        guard let userID = profile?.userID else { return }
        try? await offlineStore.saveDashboard(data, for: userID)
    }

    private func recalculateLocalStructuredDay(_ date: String, userID: UUID) {
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
        for operation in operations {
            do {
                try await service.replay(operation)
                try await offlineStore.removeOperation(operation.id, for: userID)
                pendingSyncCount -= 1
            } catch {
                return
            }
        }
        if operations.isEmpty == false { lastSyncAt = .now }
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
