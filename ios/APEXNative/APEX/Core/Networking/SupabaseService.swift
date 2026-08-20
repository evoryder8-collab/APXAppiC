import Foundation
import AuthenticationServices
import Supabase

actor SupabaseService {
    static let shared = SupabaseService()

    nonisolated let client: SupabaseClient?
    private var realtimeTask: Task<Void, Never>?
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

    func currentUserID() async -> UUID? {
        guard let client else { return nil }
        return try? await client.auth.session.user.id
    }

    func signIn(email: String, password: String) async throws -> UUID {
        guard let client else { throw APEXServiceError.configurationMissing }
        let session = try await client.auth.signIn(email: email, password: password)
        return session.user.id
    }

    /// Create an account with an email and a password.
    func signUp(email: String, password: String) async throws -> UUID {
        guard let client else { throw APEXServiceError.configurationMissing }
        let response = try await client.auth.signUp(email: email, password: password)
        return response.user.id
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

    func handleAuthCallback(_ url: URL) async throws {
        guard let client else { throw APEXServiceError.configurationMissing }
        _ = try await client.auth.session(from: url)
    }

    /// Create the profile row for a brand-new account, or return the one that
    /// is already there.
    ///
    /// Only the goal is written. Every other column has a database default, and
    /// inventing a height and a weight for someone who has not given them would
    /// put made-up numbers behind every calorie target in the app.
    func createProfileIfNeeded(userID: UUID, goal: String) async throws -> Profile {
        guard let client else { throw APEXServiceError.configurationMissing }
        let existing: [Profile] = try await client.from("profile")
            .select().eq("user_id", value: userID).limit(1).execute().value
        if let profile = existing.first { return profile }

        struct NewProfile: Encodable {
            let user_id: UUID
            let goal: String
            let trial_started_at: String
        }
        let inserted: [Profile] = try await client.from("profile")
            .insert(NewProfile(
                user_id: userID,
                goal: goal,
                trial_started_at: ISO8601DateFormatter().string(from: .now)
            ))
            .select()
            .execute().value
        guard let profile = inserted.first else { throw APEXServiceError.configurationMissing }
        return profile
    }

    /// Write the generated first twelve weeks.
    func saveInductionPlan(_ plan: TrainingInduction.GeneratedPlan) async throws {
        guard let client else { throw APEXServiceError.configurationMissing }
        /* Ordered deliberately: days reference programmes and exercises
           reference days, so a partial failure never leaves an orphan row. */
        try await client.from("programs").upsert(plan.programs, onConflict: "id").execute()
        try await client.from("program_days").upsert(plan.programDays, onConflict: "id").execute()
        try await client.from("exercises").upsert(plan.exercises, onConflict: "id").execute()
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
        async let workoutSessions: [WorkoutSession] = client.from("workout_sessions").select().order("date", ascending: false).limit(180).execute().value
        async let workoutLogs: [WorkoutLog] = client.from("workout_logs").select().order("created_at", ascending: false).limit(2000).execute().value
        async let deloadMarks: [DeloadMark] = client.from("deload_marks").select().order("date", ascending: false).limit(180).execute().value
        async let activityTypes: [ActivityType] = client.from("activity_types").select().execute().value
        async let activityLogs: [ActivityLog] = client.from("activity_logs").select().order("date", ascending: false).limit(360).execute().value
        async let dailyLogs: [DailyLog] = client.from("daily_logs").select().order("date", ascending: false).limit(90).execute().value
        async let events: [EventRecord] = client.from("events").select().order("start_date", ascending: false).limit(180).execute().value
        async let foods: [Food] = client.from("foods").select().order("updated_at", ascending: false).limit(250).execute().value
        async let foodPreferences: [FoodPreference] = client.from("food_preferences").select().order("last_used_at", ascending: false).limit(250).execute().value
        async let mealPresets: [MealPreset] = client.from("meal_presets").select().eq("archived", value: false).execute().value
        async let mealPresetItems: [MealPresetItem] = client.from("meal_preset_items").select().order("sort_order").execute().value
        async let loggedMeals: [LoggedMeal] = client.from("logged_meals").select().order("logged_at", ascending: false).limit(360).execute().value
        async let loggedFoodEntries: [LoggedFoodEntry] = client.from("logged_food_entries").select().order("created_at", ascending: false).limit(1000).execute().value
        async let snapshots: [RPGSnapshot] = client.from("rpg_snapshots").select().order("date", ascending: false).limit(180).execute().value
        async let healthMetrics: [HealthMetric] = client.from("health_metrics").select().order("date", ascending: false).limit(180).execute().value
        async let importedActivities: [ImportedActivity] = client.from("imported_activities").select().order("date", ascending: false).limit(360).execute().value
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
            events: events,
            foods: foods,
            foodPreferences: foodPreferences,
            mealPresets: mealPresets,
            mealPresetItems: mealPresetItems,
            loggedMeals: loggedMeals,
            loggedFoodEntries: loggedFoodEntries,
            snapshots: snapshots,
            healthMetrics: healthMetrics,
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

    func upsert<T: Encodable & Sendable>(_ value: T, table: String, onConflict: String? = nil) async throws {
        guard let client else { throw APEXServiceError.configurationMissing }
        if let onConflict {
            try await client.from(table).upsert(value, onConflict: onConflict).execute()
        } else {
            try await client.from(table).upsert(value).execute()
        }
    }

    func delete(table: String, id: UUID) async throws {
        guard let client else { throw APEXServiceError.configurationMissing }
        try await client.from(table).delete().eq("id", value: id.uuidString).execute()
    }

    func replay(_ operation: OfflineOperation) async throws {
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
        guard let client else { throw APEXServiceError.configurationMissing }
        let params = StructuredMealRPCPayload(pMeal: meal, pEntries: entries)
        return try await client.rpc("log_structured_meal", params: params).execute().value
    }

    func deleteStructuredMeal(_ id: UUID) async throws {
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
        guard let client else { throw APEXServiceError.configurationMissing }
        let params = MealPresetRPCPayload(
            pPreset: preset,
            pItems: items,
            pExpectedVersion: expectedVersion
        )
        return try await client.rpc("save_meal_preset", params: params).execute().value
    }

    func deleteMealPreset(_ id: UUID) async throws {
        guard let client else { throw APEXServiceError.configurationMissing }
        let _: Bool = try await client
            .rpc("delete_meal_preset", params: ["p_preset_id": id.uuidString])
            .execute()
            .value
    }

    func startRealtime(onChange: @escaping @Sendable () -> Void) async throws {
        guard let client else { throw APEXServiceError.configurationMissing }
        await stopRealtime()
        await client.realtimeV2.connect()
        let channel = client.realtimeV2.channel("apex-native-\(UUID().uuidString.lowercased())")
        let changes = channel.postgresChange(AnyAction.self, schema: "public")
        realtimeChannel = channel
        realtimeTask = Task {
            for await _ in changes {
                guard Task.isCancelled == false else { return }
                onChange()
            }
        }
        try await channel.subscribeWithError()
    }

    func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let realtimeChannel { await realtimeChannel.unsubscribe() }
        realtimeChannel = nil
    }

    func uploadProgressPhoto(
        row: ProgressPhoto,
        original: Data,
        thumbnail: Data
    ) async throws {
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
