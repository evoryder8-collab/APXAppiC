import Foundation
import AuthenticationServices
import Supabase

enum APEXRuntimeEnvironment {
    static func usesLocalUITestFixture(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        arguments.contains("-apex-ui-test")
            || arguments.contains("-apex-ui-test-first-run")
        #else
        false
        #endif
    }
}

struct ProfileCreationRequest: Encodable, Sendable {
    let id: UUID
    let userID: UUID
    let goal: String?
    let sex: String?
    let weightKG: Double?
    let heightCM: Double?
    let birthdate: String?
    let activityLevel: ActivityLevel?
    let profileKind = ProfileIntegrityPolicy.Kind.standard
    let displayName = "APEX Athlete"
    let seedVersion = SeedVersion.current

    init(
        userID: UUID,
        goal: String?,
        baseline: TrainingInduction.BodyBaseline? = nil,
        activityLevel: ActivityLevel? = nil
    ) {
        /* One account owns one profile. Reusing the authenticated UUID makes
           retries deterministic and satisfies the schema's non-null primary
           key without inventing a second account identity. */
        id = userID
        self.userID = userID
        self.goal = goal
        sex = baseline?.sex
        weightKG = baseline?.weightKG
        heightCM = baseline?.heightCM
        birthdate = baseline?.birthdate
        self.activityLevel = activityLevel
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case goal
        case sex
        case weightKG = "weight_kg"
        case heightCM = "height_cm"
        case birthdate
        case activityLevel = "activity_level"
        case profileKind = "profile_kind"
        case displayName = "display_name"
        case seedVersion = "seed_version"
    }
}

struct SettingsCreationRequest: Encodable, Sendable {
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

actor SupabaseService {
    static let shared = SupabaseService()

    private func assertRemoteMutationAllowed(_ function: StaticString = #function) {
        #if DEBUG
        precondition(
            APEXRuntimeEnvironment.usesLocalUITestFixture() == false,
            "Local UI-test fixture attempted a remote Supabase mutation in \(function)."
        )
        #endif
    }

    struct RealtimeSubscription: Equatable, Sendable {
        let table: String
        let filterColumn: String
        let filterValue: UUID
    }

    /// The smallest server row that can identify an APEX-authored HealthKit
    /// mirror. Receipt details and set logs stay on the bounded dashboard;
    /// historical reconciliation only needs this account-owned identity.
    struct WorkoutSessionIdentityRow: Decodable, Equatable, Sendable {
        let id: UUID
        let userID: UUID
        let date: String
        let startedAt: String?
        let completedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, date
            case userID = "user_id"
            case startedAt = "started_at"
            case completedAt = "completed_at"
        }
    }

    private func optionalSchemaRows<Value: Decodable & Sendable>(
        _ load: @Sendable () async throws -> [Value]
    ) async throws -> [Value] {
        do {
            return try await load()
        } catch let error as PostgrestError where error.code == "PGRST205"
            || error.localizedDescription.localizedCaseInsensitiveContains("schema cache")
            || error.localizedDescription.localizedCaseInsensitiveContains("could not find the table") {
            return []
        }
    }

    nonisolated let client: SupabaseClient?
    private var realtimeTasks: [Task<Void, Never>] = []
    private var realtimeChannel: RealtimeChannelV2?

    init() {
        if let url = APEXConfiguration.supabaseURL, let key = APEXConfiguration.supabaseKey {
            client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: key,
                options: .init(
                    auth: .init(
                        redirectToURL: URL(string: "apex://auth-callback"),
                        emitLocalSessionAsInitialSession: true
                    ),
                    global: .init(headers: ["x-apex-client": "ios-native"])
                )
            )
        } else {
            client = nil
        }
    }

    nonisolated static func realtimeSubscriptions(userID: UUID) -> [RealtimeSubscription] {
        [
            "profile", "settings", "meals", "meal_logs", "supplements", "supplement_logs",
            "programs", "program_days", "exercises", "workout_sessions", "workout_logs",
            "deload_marks", "activity_logs", "daily_logs", "hydration_events", "hydration_presets",
            "hydration_preferences", "events", "food_preferences",
            "meal_presets", "meal_preset_items", "logged_meals", "logged_food_entries",
            "rpg_snapshots", "health_metrics", "fitness_evidence", "imported_activities", "progress_photos",
            "orbit_routes", "orbit_runs", "orbit_shoes", "orbit_segments", "orbit_posters",
            "orbit_inductions", "orbit_campaigns", "orbit_campaign_sessions",
        ].map { RealtimeSubscription(table: $0, filterColumn: "user_id", filterValue: userID) }
    }

    nonisolated static func collectPaginatedRows<Row>(
        pageSize: Int = 500,
        fetch: (_ range: ClosedRange<Int>) async throws -> [Row]
    ) async rethrows -> [Row] {
        precondition(pageSize > 0)
        var rows: [Row] = []
        var offset = 0

        while true {
            let page = try await fetch(offset ... (offset + pageSize - 1))
            guard page.isEmpty == false else { return rows }
            rows.append(contentsOf: page)
            // Advance by what the server actually returned. PostgREST may
            // enforce a smaller maximum than the requested page size.
            offset += page.count
        }
    }

    nonisolated static func collectWorkoutSessionIdentities(
        ownerID: UUID,
        pageSize: Int = 250,
        fetch: (
            _ scopedOwnerID: UUID,
            _ range: ClosedRange<Int>
        ) async throws -> [WorkoutSessionIdentityRow]
    ) async rethrows -> [ExternalWorkoutImport.APEXSessionIdentity] {
        let rows = try await collectPaginatedRows(pageSize: pageSize) { range in
            try await fetch(ownerID, range)
        }
        return rows.compactMap { row in
            guard row.userID == ownerID,
                  let startedAt = ExternalWorkoutImport.parseTimestamp(
                      row.startedAt ?? row.completedAt
                  ) else { return nil }
            return .init(id: row.id, startedAt: startedAt)
        }
    }

    func currentUserID() async -> UUID? {
        guard let client else { return nil }
        return try? await client.auth.session.user.id
    }

    func loadWorkoutSessionIdentities(
        ownerID: UUID
    ) async throws -> [ExternalWorkoutImport.APEXSessionIdentity] {
        guard let client else { throw APEXServiceError.configurationMissing }
        return try await Self.collectWorkoutSessionIdentities(ownerID: ownerID) {
            scopedOwnerID,
            range in
            try await client
                .from("workout_sessions")
                .select("id,user_id,date,started_at,completed_at")
                .eq("user_id", value: scopedOwnerID)
                .eq("completed", value: true)
                .order("date", ascending: false)
                .order("id", ascending: false)
                .range(from: range.lowerBound, to: range.upperBound)
                .execute()
                .value
        }
    }

    func refreshAuthenticationSession() async throws {
        guard let client else { throw APEXServiceError.configurationMissing }
        _ = try await client.auth.refreshSession()
    }

    func signIn(email: String, password: String) async throws -> UUID {
        guard let client else { throw APEXServiceError.configurationMissing }
        let session = try await client.auth.signIn(email: email, password: password)
        return session.user.id
    }

    /// Create an account with an email and a password.
    /// What happened when an account was created.
    ///
    /// Supabase returns a user either way, so the user id alone cannot tell
    /// these apart. Only the session can: it is nil when the address still has
    /// to be confirmed, and nil again when the address was already registered,
    /// which Supabase does deliberately so that signing up cannot be used to
    /// discover who has an account.
    enum SignUpOutcome {
        case signedIn(UUID)
        case awaitingEmailConfirmation
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        guard let client else { throw APEXServiceError.configurationMissing }
        let response = try await client.auth.signUp(email: email, password: password)
        guard response.session != nil else { return .awaitingEmailConfirmation }
        return .signedIn(response.user.id)
    }

    /// Sign in with Apple, using the identity token the system hands back.
    ///
    /// Native rather than web based, so the sheet is the one iOS draws and the
    /// user never leaves the app. The nonce is passed through unhashed because
    /// Supabase compares it against the hashed copy inside the token.
    func signInWithApple(idToken: String, nonce: String) async throws -> UUID {
        guard let client else { throw APEXServiceError.configurationMissing }
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        return session.user.id
    }

    func signOut() async throws {
        guard let client else { return }
        await stopRealtime()
        try await client.auth.signOut()
    }

    func handleAuthCallback(_ url: URL) async throws -> UUID {
        guard let client else { throw APEXServiceError.configurationMissing }
        return try await client.auth.session(from: url).user.id
    }

    /// Create the profile row for a brand-new account, or return the one that
    /// is already there.
    ///
    /// First-run body facts are supplied only after the person explicitly
    /// enters them. Legacy recovery calls may omit the baseline and retain the
    /// database defaults rather than guessing new facts client side.
    func createProfileIfNeeded(
        userID: UUID,
        goal: String?,
        baseline: TrainingInduction.BodyBaseline? = nil,
        activityLevel: ActivityLevel? = nil
    ) async throws -> Profile {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        let existing: [Profile] = try await client.from("profile")
            .select().eq("user_id", value: userID).limit(1).execute().value
        if let profile = existing.first { return profile }

        let inserted: [Profile] = try await client.from("profile")
            .insert(ProfileCreationRequest(
                userID: userID,
                goal: goal,
                baseline: baseline,
                activityLevel: activityLevel
            ))
            .select()
            .execute().value
        guard let profile = inserted.first else { throw APEXServiceError.configurationMissing }
        return profile
    }

    /// A skipped questionnaire still needs writable account settings so the
    /// plan builder it leaves behind can install a programme later.
    func createSettingsIfNeeded(userID: UUID) async throws -> UserSettings {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        let existing: [UserSettings] = try await client.from("settings")
            .select().eq("user_id", value: userID).limit(1).execute().value
        if let settings = existing.first { return settings }

        let inserted: [UserSettings] = try await client.from("settings")
            .insert(SettingsCreationRequest(userID: userID))
            .select()
            .execute().value
        guard let settings = inserted.first else { throw APEXServiceError.configurationMissing }
        return settings
    }

    /// Write the generated first twelve weeks.
    func saveInductionPlan(_ plan: TrainingInduction.GeneratedPlan) async throws {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        /* Ordered deliberately: days reference programmes and exercises
           reference days, so a partial failure never leaves an orphan row. */
        try await client.from("programs").upsert(plan.programs, onConflict: "id").execute()
        try await client.from("program_days").upsert(plan.programDays, onConflict: "id").execute()
        try await client.from("exercises").upsert(plan.exercises, onConflict: "id").execute()
    }

    /// Claim a beta code for the signed-in account.
    ///
    /// Only the hash leaves the device, and the database only ever stores the
    /// hash, so neither a network log nor a copy of the table hands anyone a
    /// code they can type in. The claim itself is one statement server side,
    /// so two devices racing the same code cannot both win.
    func redeemBetaCode(hash: String) async throws -> String {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable { let p_code_hash: String }
        return try await client
            .rpc("redeem_beta_code", params: Params(p_code_hash: hash))
            .execute()
            .value
    }

    func loadDashboard() async throws -> DashboardData {
        guard let client else { throw APEXServiceError.configurationMissing }

        async let profile: [Profile] = client.from("profile").select().limit(1).execute().value
        async let settings: [UserSettings] = client.from("settings").select().limit(1).execute().value
        async let meals: [Meal] = client.from("meals").select().order("sort_order").execute().value
        async let mealLogs: [MealLog] = client.from("meal_logs").select().execute().value
        async let supplements: [Supplement] = client.from("supplements").select().order("sort_order").execute().value
        async let supplementLogs: [SupplementLog] = client.from("supplement_logs").select().execute().value
        async let programs: [Program] = client.from("programs").select().execute().value
        async let programDays: [ProgramDay] = client.from("program_days").select().order("sort_order").execute().value
        async let exercises: [Exercise] = client.from("exercises").select().order("sort_order").execute().value
        async let workoutSessions = loadAllWorkoutSessions(client: client)
        async let workoutLogs = loadAllWorkoutLogs(client: client)
        async let deloadMarks: [DeloadMark] = client.from("deload_marks").select().order("date", ascending: false).limit(180).execute().value
        async let activityTypes: [ActivityType] = client.from("activity_types").select().execute().value
        async let activityLogs: [ActivityLog] = client.from("activity_logs").select().order("date", ascending: false).limit(360).execute().value
        async let dailyLogs: [DailyLog] = client.from("daily_logs").select().order("date", ascending: false).limit(90).execute().value
        async let hydrationEvents: [HydrationEvent] = optionalSchemaRows {
            try await client.from("hydration_events").select().order("occurred_at", ascending: false).limit(1000).execute().value
        }
        async let hydrationPresets: [HydrationPreset] = optionalSchemaRows {
            try await client.from("hydration_presets").select().order("sort_order").execute().value
        }
        async let hydrationPreferences: [HydrationAccountPreferences] = optionalSchemaRows {
            try await client.from("hydration_preferences").select().limit(1).execute().value
        }
        async let events: [EventRecord] = client.from("events").select().order("start_date", ascending: false).limit(180).execute().value
        async let foods: [Food] = client.from("foods").select().order("updated_at", ascending: false).limit(250).execute().value
        async let foodPreferences: [FoodPreference] = client.from("food_preferences").select().order("last_used_at", ascending: false).limit(250).execute().value
        async let mealPresets: [MealPreset] = client.from("meal_presets").select().eq("archived", value: false).execute().value
        async let mealPresetItems: [MealPresetItem] = client.from("meal_preset_items").select().order("sort_order").execute().value
        async let loggedMeals: [LoggedMeal] = client.from("logged_meals").select().order("logged_at", ascending: false).limit(360).execute().value
        async let loggedFoodEntries: [LoggedFoodEntry] = client.from("logged_food_entries").select().order("created_at", ascending: false).limit(1000).execute().value
        async let snapshots: [RPGSnapshot] = client.from("rpg_snapshots").select().order("date", ascending: false).limit(180).execute().value
        async let healthMetrics: [HealthMetric] = client.from("health_metrics").select().order("date", ascending: false).limit(180).execute().value
        async let fitnessEvidence: [FitnessEvidenceRecord] = optionalSchemaRows {
            try await Self.collectPaginatedRows { range in
                try await client
                    .from("fitness_evidence").select()
                    .order("measured_at", ascending: false)
                    .order("id", ascending: true)
                    .range(from: range.lowerBound, to: range.upperBound)
                    .execute()
                    .value
            }
        }
        async let importedActivities: [ImportedActivity] = Self.collectPaginatedRows { range in
            try await client
                .from("imported_activities")
                .select()
                .order("date", ascending: false)
                .order("id", ascending: false)
                .range(from: range.lowerBound, to: range.upperBound)
                .execute()
                .value
        }
        async let progressPhotos: [ProgressPhoto] = client.from("progress_photos").select().order("local_date", ascending: false).limit(120).execute().value
        async let orbitRoutes: [OrbitRouteRecord] = client.from("orbit_routes").select().order("updated_at", ascending: false).limit(120).execute().value
        async let orbitRuns: [OrbitRunRecord] = client.from("orbit_runs").select().order("local_date", ascending: false).limit(180).execute().value
        async let orbitShoes: [OrbitShoe] = client.from("orbit_shoes").select().order("updated_at", ascending: false).limit(80).execute().value
        async let orbitSegments: [OrbitSegment] = client.from("orbit_segments").select().order("updated_at", ascending: false).limit(240).execute().value
        async let orbitPosters: [OrbitPoster] = client.from("orbit_posters").select().order("created_at", ascending: false).limit(180).execute().value
        async let orbitInductions: [OrbitInduction] = client.from("orbit_inductions").select().order("updated_at", ascending: false).limit(20).execute().value
        async let orbitCampaigns: [OrbitCampaign] = client.from("orbit_campaigns").select().order("updated_at", ascending: false).limit(20).execute().value
        async let orbitCampaignSessions: [OrbitCampaignSession] = client.from("orbit_campaign_sessions").select().order("date").limit(800).execute().value

        return try await DashboardData(
            profile: profile.first,
            settings: settings.first,
            meals: meals,
            mealLogs: mealLogs,
            supplements: supplements,
            supplementLogs: supplementLogs,
            programs: programs,
            programDays: programDays,
            exercises: exercises,
            workoutSessions: workoutSessions,
            workoutLogs: workoutLogs,
            deloadMarks: deloadMarks,
            activityTypes: activityTypes,
            activityLogs: activityLogs,
            dailyLogs: dailyLogs,
            hydrationEvents: hydrationEvents,
            hydrationPresets: hydrationPresets,
            hydrationPreferences: hydrationPreferences.first,
            events: events,
            foods: foods,
            foodPreferences: foodPreferences,
            mealPresets: mealPresets,
            mealPresetItems: mealPresetItems,
            loggedMeals: loggedMeals,
            loggedFoodEntries: loggedFoodEntries,
            snapshots: snapshots,
            healthMetrics: healthMetrics,
            fitnessEvidence: fitnessEvidence,
            importedActivities: importedActivities,
            progressPhotos: progressPhotos,
            orbitRoutes: orbitRoutes,
            orbitRuns: orbitRuns,
            orbitShoes: orbitShoes,
            orbitSegments: orbitSegments,
            orbitPosters: orbitPosters,
            orbitInductions: orbitInductions,
            orbitCampaigns: orbitCampaigns,
            orbitCampaignSessions: orbitCampaignSessions
        )
    }

    private func loadAllWorkoutSessions(client: SupabaseClient) async throws -> [WorkoutSession] {
        try await Self.collectPaginatedRows { range in
            try await client
                .from("workout_sessions")
                .select()
                .order("date", ascending: false)
                .order("id", ascending: false)
                .range(from: range.lowerBound, to: range.upperBound)
                .execute()
                .value
        }
    }

    private func loadAllWorkoutLogs(client: SupabaseClient) async throws -> [WorkoutLog] {
        try await Self.collectPaginatedRows { range in
            try await client
                .from("workout_logs")
                .select()
                .order("created_at", ascending: false)
                .order("id", ascending: false)
                .range(from: range.lowerBound, to: range.upperBound)
                .execute()
                .value
        }
    }

    func upsert<T: Encodable & Sendable>(_ value: T, table: String, onConflict: String? = nil) async throws {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        if table == "profile" {
            let payload = try RemoteProfilePayload(value)
            if let onConflict {
                try await client.from(table).upsert(payload, onConflict: onConflict).execute()
            } else {
                try await client.from(table).upsert(payload).execute()
            }
            return
        }
        if let onConflict {
            try await client.from(table).upsert(value, onConflict: onConflict).execute()
        } else {
            try await client.from(table).upsert(value).execute()
        }
    }

    func delete(table: String, id: UUID) async throws {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        try await client.from(table).delete().eq("id", value: id.uuidString).execute()
    }

    func recordUserFitnessEvidence(
        _ evidence: NormalizedFitnessEvidence
    ) async throws -> FitnessEvidenceRecord {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        guard evidence.confidence == .low,
              evidence.source == .structuredSelfReport
                || evidence.source == .userEnteredExternalResult else {
            throw FitnessEvidenceRecordingError.trustedSourceRequiresIngestion
        }
        return try await client
            .rpc("record_user_fitness_evidence", params: RecordUserFitnessEvidenceParameters(evidence))
            .execute()
            .value
    }

    func replay(_ operation: OfflineOperation) async throws {
        assertRemoteMutationAllowed()
        switch operation.kind {
        case .upsert:
            guard let payload = operation.payload else { throw APEXServiceError.invalidOfflineOperation }
            let value = try JSONDecoder().decode(JSONValue.self, from: payload)
            try await upsert(value, table: operation.table, onConflict: operation.onConflict)
        case .delete:
            guard let id = operation.recordID else { throw APEXServiceError.invalidOfflineOperation }
            try await delete(table: operation.table, id: id)
        case .rpc:
            guard let function = operation.rpcFunction, let payload = operation.payload, let client
            else { throw APEXServiceError.invalidOfflineOperation }
            let params = try JSONDecoder().decode(JSONValue.self, from: payload)
            try await client.rpc(function, params: params).execute()
        }
    }

    func lookupFood(barcode: String) async throws -> FoodLookupEnvelope {
        guard let client else { throw APEXServiceError.configurationMissing }
        return try await client.functions.invoke(
            "food-lookup",
            options: .init(body: ["barcode": barcode])
        )
    }

    func searchFoods(query: String) async throws -> FoodLookupEnvelope {
        guard let client else { throw APEXServiceError.configurationMissing }
        return try await client.functions.invoke(
            "food-lookup",
            options: .init(body: ["query": query])
        )
    }

    func logStructuredMeal(
        meal: StructuredMealRequest,
        entries: [StructuredFoodEntryRequest]
    ) async throws -> UUID {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        let params = StructuredMealRPCPayload(pMeal: meal, pEntries: entries)
        return try await client.rpc("log_structured_meal", params: params).execute().value
    }

    func deleteStructuredMeal(_ id: UUID) async throws {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        let _: Bool = try await client
            .rpc("delete_structured_meal", params: ["p_meal_id": id.uuidString])
            .execute()
            .value
    }

    func saveMealPreset(
        preset: MealPresetRequest,
        items: [MealPresetItemRequest],
        expectedVersion: Int
    ) async throws -> UUID {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        let params = MealPresetRPCPayload(
            pPreset: preset,
            pItems: items,
            pExpectedVersion: expectedVersion
        )
        return try await client.rpc("save_meal_preset", params: params).execute().value
    }

    func deleteMealPreset(_ id: UUID) async throws {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        let _: Bool = try await client
            .rpc("delete_meal_preset", params: ["p_preset_id": id.uuidString])
            .execute()
            .value
    }

    func loadCoachContext() async throws -> CoachAccountContext {
        guard let client else { throw APEXServiceError.configurationMissing }
        return try await client.rpc("coach_get_my_context").execute().value
    }

    func loadCoachRoster(query: String = "") async throws -> [CoachRosterEntry] {
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable, Sendable { let p_query: String? }
        return try await client
            .rpc("coach_get_roster", params: Params(p_query: query.isEmpty ? nil : query))
            .execute()
            .value
    }

    func createCoachInvitation(
        email: String,
        scopes: Set<CoachConsentScope>,
        visualProgressRequested: Bool
    ) async throws -> CoachInvitationReceipt {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable, Sendable {
            let p_email: String
            let p_scopes: [String]
            let p_visual_progress_requested: Bool
        }
        return try await client.rpc("coach_create_invitation", params: Params(
            p_email: email,
            p_scopes: scopes.map(\.rawValue).sorted(),
            p_visual_progress_requested: visualProgressRequested
        )).execute().value
    }

    func previewCoachInvitation(token: String) async throws -> CoachInvitationPreview {
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable, Sendable { let p_token: String }
        return try await client
            .rpc("coach_preview_invitation", params: Params(p_token: token))
            .execute()
            .value
    }

    func acceptCoachInvitation(
        token: String,
        scopes: Set<CoachConsentScope>,
        visualProgressConsent: Bool
    ) async throws -> CoachAccountContext {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable, Sendable {
            let p_token: String
            let p_scopes: [String]
            let p_visual_progress_consent: Bool
        }
        return try await client.rpc("coach_accept_invitation", params: Params(
            p_token: token,
            p_scopes: scopes.map(\.rawValue).sorted(),
            p_visual_progress_consent: visualProgressConsent
        )).execute().value
    }

    func loadCoachClientOverview(relationshipID: UUID) async throws -> CoachClientOverview {
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable, Sendable { let p_relationship_id: UUID }
        return try await client
            .rpc("coach_get_client_overview", params: Params(p_relationship_id: relationshipID))
            .execute()
            .value
    }

    func saveCoachPlan(
        relationshipID: UUID,
        plan: CoachPlanDraft,
        expectedVersion: Int,
        publish: Bool
    ) async throws -> CoachPlanVersionReceipt {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable, Sendable {
            let p_relationship_id: UUID
            let p_plan: CoachPlanDraft
            let p_expected_version: Int
        }
        let function = publish ? "coach_publish_plan" : "coach_save_plan_draft"
        return try await client.rpc(function, params: Params(
            p_relationship_id: relationshipID,
            p_plan: plan,
            p_expected_version: expectedVersion
        )).execute().value
    }

    func acknowledgeCoachPlan(planVersionID: UUID) async throws -> Bool {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable, Sendable { let p_plan_version_id: UUID }
        return try await client
            .rpc("client_acknowledge_coach_plan", params: Params(p_plan_version_id: planVersionID))
            .execute()
            .value
    }

    func activateCoachPlan(planVersionID: UUID) async throws -> CoachPlanActivationReceipt {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable, Sendable { let p_plan_version_id: UUID }
        return try await client
            .rpc("client_activate_coach_plan", params: Params(p_plan_version_id: planVersionID))
            .execute()
            .value
    }

    func updateCoachScopes(
        relationshipID: UUID,
        scopes: Set<CoachConsentScope>,
        visualProgressConsent: Bool
    ) async throws -> CoachAccountContext {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable, Sendable {
            let p_relationship_id: UUID
            let p_scopes: [String]
            let p_visual_progress_consent: Bool
        }
        return try await client.rpc("client_update_coach_scopes", params: Params(
            p_relationship_id: relationshipID,
            p_scopes: scopes.map(\.rawValue).sorted(),
            p_visual_progress_consent: visualProgressConsent
        )).execute().value
    }

    func endCoachRelationship(relationshipID: UUID) async throws -> Bool {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        struct Params: Encodable, Sendable { let p_relationship_id: UUID }
        return try await client
            .rpc("end_coach_relationship", params: Params(p_relationship_id: relationshipID))
            .execute()
            .value
    }

    func startRealtime(onChange: @escaping @Sendable () -> Void) async throws {
        guard let client else { throw APEXServiceError.configurationMissing }
        await stopRealtime()
        let userID = try await client.auth.session.user.id
        await client.realtimeV2.connect()
        let channel = client.realtimeV2.channel("apex-native-\(UUID().uuidString.lowercased())")
        realtimeChannel = channel
        realtimeTasks = Self.realtimeSubscriptions(userID: userID).map { subscription in
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: subscription.table,
                filter: .eq(subscription.filterColumn, value: subscription.filterValue)
            )
            return Task {
                for await _ in changes {
                    guard Task.isCancelled == false else { return }
                    onChange()
                }
            }
        }
        do {
            try await channel.subscribeWithError()
        } catch {
            await stopRealtime()
            throw error
        }
    }

    func stopRealtime() async {
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks.removeAll()
        if let realtimeChannel { await realtimeChannel.unsubscribe() }
        realtimeChannel = nil
    }

    func uploadProgressPhoto(
        row: ProgressPhoto,
        original: Data,
        thumbnail: Data
    ) async throws {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        let bucket = client.storage.from("apex-progress")
        do {
            try await bucket.upload(
                row.storagePath,
                data: original,
                options: .init(cacheControl: "31536000", contentType: "image/jpeg", upsert: false)
            )
            try await bucket.upload(
                row.thumbnailPath,
                data: thumbnail,
                options: .init(cacheControl: "31536000", contentType: "image/jpeg", upsert: false)
            )
            try await upsert(row, table: "progress_photos", onConflict: "user_id,client_idempotency_key")
        } catch {
            _ = try? await bucket.remove(paths: [row.storagePath, row.thumbnailPath])
            throw error
        }
    }

    /// Upload a prepared avatar and return the path it was stored at.
    ///
    /// Overwrites in place rather than accumulating one file per change: a
    /// profile picture has exactly one current value, and old ones are not
    /// history anybody wants kept.
    func uploadAvatar(userID: UUID, data: Data) async throws -> String {
        assertRemoteMutationAllowed()
        guard let client else { throw APEXServiceError.configurationMissing }
        let path = "\(userID.uuidString.lowercased())/avatar.jpg"
        try await client.storage.from("apex-progress").upload(
            path,
            data: data,
            options: .init(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
        )
        return path
    }

    func signedProgressURL(path: String, expiresIn: Int = 3_600) async throws -> URL {
        guard let client else { throw APEXServiceError.configurationMissing }
        return try await client.storage
            .from("apex-progress")
            .createSignedURL(path: path, expiresIn: expiresIn)
    }
}

enum APEXServiceError: LocalizedError {
    case configurationMissing
    case personaMismatch(expected: Persona, actual: Persona)
    case invalidOfflineOperation
    case incompleteFood

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            "The native Supabase configuration is missing."
        case .personaMismatch(let expected, let actual):
            "Those credentials belong to \(actual.displayName). Choose that profile to continue as \(expected.displayName)."
        case .invalidOfflineOperation:
            "A queued offline change could not be decoded."
        case .incompleteFood:
            "This food does not contain enough portion or nutrition data to log accurately."
        }
    }
}
