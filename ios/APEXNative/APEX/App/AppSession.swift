import Foundation
import Observation
import Supabase
import UIKit
import CoreFoundation

struct AccountGenerationGate: Sendable {
    private(set) var token: UInt64 = 0

    mutating func advance() {
        token &+= 1
    }

    func accepts(_ candidate: UInt64) -> Bool {
        candidate == token
    }
}

/// The account whose settings row this session has loaded from the server. A row restored
/// from the offline cache can be older than the server's, so a whole-row save the person
/// did not ask for waits until the server's copy is on screen.
struct ServerSettingsGate: Sendable {
    /// An Apple Health read, as the change it makes to the settings addons.
    typealias HealthRead = @Sendable (inout [String: JSONValue]) -> Void

    private var ownerID: UUID?
    // shortcut: reads wait one by one, a few an hour while the server's row is not in memory;
    // merge them per day if a session ever stays that way for weeks.
    private var waitingReads: [HealthRead] = []

    /// Opens the gate for the account whose server row is now in memory. Health reads that
    /// waited are re-applied to that row; the addons to send come back, or nil when nothing changed.
    @discardableResult
    mutating func serverCopyLoaded(for ownerID: UUID?, addons: [String: JSONValue]? = nil) -> [String: JSONValue]? {
        self.ownerID = ownerID
        guard ownerID != nil, let addons, !waitingReads.isEmpty else { return nil }
        var carried = addons
        for read in waitingReads { read(&carried) }
        waitingReads = []
        return carried == addons ? nil : carried
    }

    mutating func reset() {
        ownerID = nil
        waitingReads = []
    }

    func allowsSave(for ownerID: UUID) -> Bool {
        self.ownerID == ownerID
    }

    /// Whether a Health read already applied in memory is sent now. Over an older row it waits,
    /// so the phone's copy never replaces settings changed on the website since.
    mutating func sends(_ read: @escaping HealthRead, for ownerID: UUID) -> Bool {
        if allowsSave(for: ownerID) { return true }
        waitingReads.append(read)
        return false
    }
}

/// An opaque proof of which authenticated account initiated a UI action.
/// Views capture it synchronously, before creating an unstructured Task, so
/// delayed work can never adopt whichever account happens to be active later.
struct AccountOperationLease: Sendable, Equatable {
    let ownerID: UUID
    fileprivate let generation: UInt64
}

enum StructuredMealDeletionError: LocalizedError, Equatable {
    case targetChanged
    case durabilityUnavailable

    var errorDescription: String? {
        switch self {
        case .targetChanged:
            "That meal changed before it could be removed. Refresh and try again."
        case .durabilityUnavailable:
            "That meal could not be removed safely. Refresh and try again."
        }
    }
}

enum ConfirmedMealDeletionPersistence {
    enum Outcome: Equatable {
        case remote
        case queued
    }

    /// A confirmed destructive edit is complete only when its local snapshot
    /// is durable and the server either accepted it or the outbox retained it.
    @MainActor
    static func persist(
        local: @MainActor () async throws -> Void,
        remote: @MainActor () async throws -> Void,
        enqueue: @MainActor () async throws -> Void
    ) async throws -> Outcome {
        do {
            try await local()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StructuredMealDeletionError.durabilityUnavailable
        }

        return try await synchronize(remote: remote, enqueue: enqueue)
    }

    @MainActor
    static func synchronize(
        remote: @MainActor () async throws -> Void,
        enqueue: @MainActor () async throws -> Void
    ) async throws -> Outcome {
        do {
            try await remote()
            return .remote
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            do {
                try await enqueue()
                return .queued
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw StructuredMealDeletionError.durabilityUnavailable
            }
        }
    }

    @MainActor
    static func persistMergedBeforePublishing(
        snapshot: @MainActor () -> (revision: UInt64, dashboard: DashboardData),
        merge: @MainActor (DashboardData) throws -> DashboardData,
        persist: @MainActor (DashboardData) async throws -> Void
    ) async throws -> DashboardData {
        while true {
            let base = snapshot()
            let proposed = try merge(base.dashboard)
            do {
                try await persist(proposed)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as StructuredMealDeletionError {
                throw error
            } catch {
                throw StructuredMealDeletionError.durabilityUnavailable
            }
            guard snapshot().revision == base.revision else { continue }
            return proposed
        }
    }
}

struct StructuredMealDeletionScope: Sendable, Equatable {
    let ownerID: UUID
    let mealID: UUID
    let localDate: String

    init?(meal: LoggedMeal, ownerID: UUID) {
        guard meal.userID == ownerID else { return nil }
        self.ownerID = ownerID
        mealID = meal.id
        localDate = meal.localDate
    }

    func removeConfirmedMeal(from data: inout DashboardData) throws {
        let currentTargets = data.loggedMeals.filter { meal in
            meal.id == mealID && meal.userID == ownerID
        }
        guard currentTargets.count == 1,
              currentTargets[0].localDate == localDate else {
            throw StructuredMealDeletionError.targetChanged
        }
        data.loggedMeals.removeAll { meal in
            meal.id == mealID
                && meal.userID == ownerID
                && meal.localDate == localDate
        }
        data.loggedFoodEntries.removeAll { entry in
            entry.mealID == mealID && entry.userID == ownerID
        }
    }
}

enum StructuredNutritionDayProjection {
    static func apply(
        date: String,
        ownerID: UUID,
        to data: inout DashboardData
    ) {
        let meals = data.loggedMeals.filter {
            $0.userID == ownerID && $0.localDate == date
        }
        let existing = data.dailyLogs.first {
            $0.userID == ownerID && $0.date == date
        }
        let manualKcal = existing?.nutritionSource == "manual" ? existing?.kcal : existing?.manualKcal
        let manualProtein = existing?.nutritionSource == "manual" ? existing?.proteinG : existing?.manualProteinG
        let manualFat = existing?.nutritionSource == "manual" ? existing?.fatG : existing?.manualFatG
        let manualCarbs = existing?.nutritionSource == "manual" ? existing?.carbsG : existing?.manualCarbsG
        let row = DailyLog(
            id: existing?.id ?? APEXStableID.scopedUUID(
                namespace: "daily-log",
                date: date,
                userID: ownerID
            ),
            userID: ownerID,
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
        data.dailyLogs.removeAll {
            $0.userID == ownerID && $0.date == date
        }
        data.dailyLogs.append(row)
    }
}

struct StructuredMealDeletionChange: Sendable {
    let scope: StructuredMealDeletionScope
    private let removedMeal: LoggedMeal
    private let removedMealIndex: Int
    private let removedEntries: [LoggedFoodEntry]

    init(scope: StructuredMealDeletionScope, data: DashboardData) throws {
        let matches = data.loggedMeals.enumerated().filter { _, meal in
            meal.id == scope.mealID && meal.userID == scope.ownerID
        }
        guard matches.count == 1,
              matches[0].element.localDate == scope.localDate else {
            throw StructuredMealDeletionError.targetChanged
        }
        self.scope = scope
        removedMeal = matches[0].element
        removedMealIndex = matches[0].offset
        removedEntries = data.loggedFoodEntries.filter {
            $0.mealID == scope.mealID && $0.userID == scope.ownerID
        }
    }

    func deleting(from base: DashboardData) throws -> DashboardData {
        let currentMeals = base.loggedMeals.filter {
            $0.id == scope.mealID && $0.userID == scope.ownerID
        }
        let currentEntries = base.loggedFoodEntries.filter {
            $0.mealID == scope.mealID && $0.userID == scope.ownerID
        }
        guard currentMeals == [removedMeal],
              Set(currentEntries) == Set(removedEntries) else {
            throw StructuredMealDeletionError.targetChanged
        }

        var proposed = base
        try scope.removeConfirmedMeal(from: &proposed)
        StructuredNutritionDayProjection.apply(
            date: scope.localDate,
            ownerID: scope.ownerID,
            to: &proposed
        )
        return proposed
    }

    /// Restores only this change's rows over the latest dashboard. Unrelated
    /// nutrition, hydration, workout, and profile mutations stay intact.
    func restoring(in base: DashboardData) -> DashboardData {
        let targetExists = base.loggedMeals.contains {
            $0.id == scope.mealID && $0.userID == scope.ownerID
        }
        let targetEntriesExist = base.loggedFoodEntries.contains {
            $0.mealID == scope.mealID && $0.userID == scope.ownerID
        }
        guard targetExists == false, targetEntriesExist == false else { return base }

        var restored = base
        restored.loggedMeals.insert(
            removedMeal,
            at: min(removedMealIndex, restored.loggedMeals.endIndex)
        )
        restored.loggedFoodEntries.append(contentsOf: removedEntries)
        StructuredNutritionDayProjection.apply(
            date: scope.localDate,
            ownerID: scope.ownerID,
            to: &restored
        )
        return restored
    }
}

private struct SyncAccountBoundaryError: Error, Sendable {}

private enum AccountAccessValidationError: Error, Sendable {
    case invalidEnvelope
}

private struct PendingHydrationMutationRetry: Codable, Sendable {
    let mutation: HydrationCompanionMutation
    var attempts: Int
}

typealias FoodSearchProvider = @Sendable (String) async throws -> FoodLookupEnvelope

@MainActor
@Observable
final class AppSession {
    @ObservationIgnored private var dashboardMutationRevision: UInt64 = 0
    var route: AppRoute = .launching
    /// Shown briefly after a bespoke account signs in by email.
    var greetingPersona: Persona?
    /// The address a confirmation link was just sent to, if any. Held so the
    /// sign-up screen can say what happened rather than appear to do nothing.
    var awaitingConfirmationFor: String?
    /// Debug only: opens access recovery straight away for visual checking.
    var previewAccessRecovery = false
    var data: DashboardData = .empty {
        didSet {
            dashboardMutationRevision &+= 1
            recomputeBrain()
        }
    }
    private var coachRefreshRevision: UInt64 = 0
    var coachContext: CoachAccountContext = .empty
    /* Receipts from the interconnection engine, for the Avatar feed */
    var brainSynergies: [FBSynergyEvent] = []
    private(set) var avatarDomainScores: [String: Double] = [:]
    @ObservationIgnored private var lastAvatarPublication: AvatarScorePublication?
    @ObservationIgnored private var avatarPublicationTask: Task<Void, Never>?
    @ObservationIgnored private var brainRecomputing = false
    var isBusy = false
    var isRefreshing = false
    var alertMessage: String?
    var lastSyncAt: Date?
    var pendingSyncCount = 0
    var failedSyncCount = 0
    var failedSyncOperations: [FailedOfflineOperation] = []
    var navigationPath: [PortalDestination] = []
    /// Shared UI date survives Simple/Advanced navigation, never crosses accounts.
    var browsingDate = Date()
    @ObservationIgnored private var followedToday = Date().apexDateKey
    @ObservationIgnored private var browsingDateHeld = false


    private func updateSandboxPlanReceipt(planVersionID: UUID, activate: Bool, ownerID: UUID) throws {
        guard let plan = coachContext.currentPlan, plan.id == planVersionID,
              coachClientPolicy.canFollowCoachPlan else { throw CancellationError() }
        let updated = CoachCurrentPlan(id: plan.id, relationshipID: plan.relationshipID,
            version: plan.version, status: plan.status, title: plan.title,
            objective: plan.objective, coachNote: plan.coachNote, reviewDate: plan.reviewDate,
            checklist: plan.checklist, plan: plan.plan, publishedAt: plan.publishedAt,
            acknowledgedAt: plan.acknowledgedAt ?? Date().ISO8601Format(),
            activatedAt: activate ? Date().ISO8601Format() : plan.activatedAt)
        coachContext = CoachAccountContext(coach: coachContext.coach,
            sponsorship: coachContext.sponsorship, currentPlan: updated,
            capabilities: coachContext.capabilities)
        guard activate else { return }
        let slug = "coach"
        let previousIDs = Set(data.programs.filter { $0.slug == slug }.map(\.id))
        let previousDays = Set(data.programDays.filter { previousIDs.contains($0.programID) }.map(\.id))
        data.exercises.removeAll { previousDays.contains($0.programDayID) }
        data.programDays.removeAll { previousIDs.contains($0.programID) }
        data.programs.removeAll { previousIDs.contains($0.id) }
        let program = Program(id: UUID(), userID: ownerID, slug: slug, name: plan.title, description: plan.objective)
        data.programs.append(program)
        for (index, template) in plan.plan.sessions.enumerated() {
            let day = ProgramDay(id: template.id, userID: ownerID, programID: program.id,
                weekday: template.weekday, name: template.name, dayType: "coach",
                estimatedMinutes: template.estimatedMinutes, warmupNote: template.warmupNote, sortOrder: index)
            data.programDays.append(day)
            for (order, item) in template.exercises.enumerated() {
                data.exercises.append(Exercise(id: item.id, userID: ownerID, programDayID: day.id,
                    name: item.name, movementID: item.movementID, workGroupID: item.groupID,
                    workGroupPosition: item.groupPosition, sets: item.sets,
                    repMin: item.targetMin, repMax: item.targetMax, repUnit: item.unit, perSide: item.perSide,
                    restSeconds: item.restSeconds, tempoUp: item.tempoUpSeconds,
                    tempoDown: item.tempoDownSeconds, tempoPause: item.tempoPauseSeconds,
                    tempoNote: "", notes: item.notes, incrementKG: 1, isLite: false,
                    optional: item.optional, sortOrder: order))
            }
        }
    }

    private let service: SupabaseService
    let developerSandboxRole: DeveloperSandboxRole?
    var isDeveloperSandbox: Bool { developerSandboxRole != nil }
    @ObservationIgnored private let sandboxSamples: DeveloperSandboxSamples?
    @ObservationIgnored private let foodSearchProvider: FoodSearchProvider
    private let offlineStore: OfflineStore
    let defaults: UserDefaults
    @ObservationIgnored private let sandboxDefaultsSuiteName: String?
    /// A sandbox delete returns at once. A test waits here to act while one is still on its way to the server.
    @ObservationIgnored var sandboxDeleteInFlight: (@MainActor () async -> Void)?
    @ObservationIgnored private let hydrationConnectivity: HydrationPhoneConnectivity?
    @ObservationIgnored private let hydrationMutationQueue = HydrationMutationQueue()
    @ObservationIgnored private let supplementMutationQueue = SupplementMutationQueue()
    @ObservationIgnored private var hydrationMutationsInFlight: Set<UUID> = []
    private var bootstrapped = false
    private var realtimeDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var workoutSyncTask: Task<Void, Never>?
    @ObservationIgnored private var accountGeneration = AccountGenerationGate()
    @ObservationIgnored private var syncDrainGate = OfflineQueueDrainGate()
    @ObservationIgnored private var authenticatedOwnerID: UUID?
    private var customWorkoutMutationGate = CustomWorkoutMutationGate()
    @ObservationIgnored private var serverSettings = ServerSettingsGate()
    @ObservationIgnored private var lastShadowObservationSignature: String?
    @ObservationIgnored private var suspendedAccessOwnerID: UUID?
    @ObservationIgnored private var accessServiceSuspensionTask: Task<Void, Never>?

    #if DEBUG
    private static let firstRunFixtureOwnerID = UUID(
        uuidString: "7d3e70bf-c420-4b66-90ae-5a103465f1c1"
    )!
    #endif

    init(
        developerSandboxRole: DeveloperSandboxRole? = nil,
        offlineStore: OfflineStore? = nil,
        foodSearchProvider: @escaping FoodSearchProvider = { query in
            try await SupabaseService.shared.searchFoods(query: query)
        }
    ) {
        self.developerSandboxRole = developerSandboxRole
        let isSandbox = developerSandboxRole != nil
        service = isSandbox ? SupabaseService(localOnly: true) : .shared
        self.offlineStore = offlineStore ?? (isSandbox ? OfflineStore(memoryOnly: true) : .shared)
        let suiteName = isSandbox ? "apex.developer-sandbox.\(UUID().uuidString)" : nil
        sandboxDefaultsSuiteName = suiteName
        defaults = suiteName.map { UserDefaults(suiteName: $0)! } ?? .standard
        hydrationConnectivity = isSandbox ? nil : HydrationPhoneConnectivity()
        sandboxSamples = isSandbox ? DeveloperSandboxSamples() : nil
        self.foodSearchProvider = isSandbox ? { @Sendable query in
            let matches = DeveloperSandboxSamples.catalogue.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            return FoodLookupEnvelope(state: "ok", source: "sample", food: nil, results: matches, message: nil)
        } : foodSearchProvider
        if let developerSandboxRole {
            let ownerID = UUID()
            authenticatedOwnerID = ownerID
            data = DeveloperSandboxSamples.dashboard(ownerID: ownerID, name: "Sample")
            if developerSandboxRole.startsWithOnboarding {
                data = .empty
                route = .induction
            } else {
                switch developerSandboxRole {
                case .coach: coachContext = sandboxSamples!.coachWorkspaceContext()
                case .invitedClient: coachContext = sandboxSamples!.coachPlanContext()
                default: coachContext = .empty
                }
                route = .portal
            }
            return
        }
        EntitlementStore.shared.setAccessDeniedHandler { [weak self] ownerID in
            self?.routeToAccessRecoveryBoundary(for: ownerID)
        }
        hydrationConnectivity?.mutationHandler = { [weak self] mutation in
            await self?.handleHydrationMutation(mutation)
        }
        hydrationConnectivity?.supplementMutationHandler = { [weak self] mutation in
            await self?.handleWatchSupplementMutation(mutation)
        }
        hydrationConnectivity?.companionRefreshHandler = { [weak self] in
            self?.publishHydrationState()
        }
    }

    @discardableResult
    func beginAccountBoundary() -> UInt64 {
        if isDeveloperSandbox {
            invalidateDeveloperSandbox()
            return accountGeneration.token
        }
        accountGeneration.advance()
        authenticatedOwnerID = nil
        browsingDate = .now
        browsingDateHeld = false
        suspendedAccessOwnerID = nil
        EntitlementStore.shared.resetAccount()
        OrbitLocationManager.shared.releaseForAccountBoundary()
        NudgeCenter.shared.clearAccountBoundary()
        HealthKitManager.shared.resetAccountBoundary()
        /* Authentication is an immediate privacy boundary. Do not leave the
           previous person's portrait, Avatar evidence, navigation history or
           transient messages visible while the next network request is in
           flight. The account's persisted cache remains owner-scoped and can
           be restored only after that owner authenticates again. */
        data = .empty
        brainSynergies = []
        avatarDomainScores = [:]
        lastAvatarPublication = nil
        avatarPublicationTask?.cancel()
        avatarPublicationTask = nil
        navigationPath.removeAll()
        greetingPersona = nil
        awaitingConfirmationFor = nil
        alertMessage = nil
        hydrationConnectivity?.publishDisconnected()
        realtimeDebounceTask?.cancel()
        realtimeDebounceTask = nil
        workoutSyncTask?.cancel()
        workoutSyncTask = nil
        pendingSyncCount = 0
        failedSyncCount = 0
        failedSyncOperations = []
        coachContext = .empty
        customWorkoutMutationGate.reset()
        serverSettings.reset()
        lastShadowObservationSignature = nil
        isBusy = false
        isRefreshing = false
        return accountGeneration.token
    }

    var customWorkoutMutationIsActive: Bool {
        customWorkoutMutationGate.isActive
    }

    private func beginCustomWorkoutMutation() -> UUID? {
        customWorkoutMutationGate.begin()
    }

    private func finishCustomWorkoutMutation(_ token: UUID) {
        customWorkoutMutationGate.finish(token)
    }

    @discardableResult
    private func completeAccountBoundary() -> UInt64 {
        accountGeneration.advance()
        return accountGeneration.token
    }

    private func hydrationOperationIsCurrent(ownerID: UUID, token: UInt64) -> Bool {
        accountGeneration.accepts(token) && verifiedPersistenceOwnerID() == ownerID
    }

    private func requireCurrentSyncAccount(ownerID: UUID, token: UInt64) throws {
        guard accountGeneration.accepts(token),
              verifiedPersistenceOwnerID(ownerID) == ownerID else {
            throw SyncAccountBoundaryError()
        }
    }

    func accountOperationLease() -> AccountOperationLease? {
        guard let ownerID = authenticatedOwnerID ?? verifiedPersistenceOwnerID() else { return nil }
        return AccountOperationLease(ownerID: ownerID, generation: accountGeneration.token)
    }

    func accountOperationIsCurrent(_ operation: AccountOperationLease) -> Bool {
        guard accountGeneration.accepts(operation.generation) else { return false }
        if let authenticatedOwnerID {
            guard authenticatedOwnerID == operation.ownerID else { return false }
            let hasNoDashboardIdentity = data.profile == nil && data.settings == nil
            return hasNoDashboardIdentity
                || TrainingInduction.belongsToAccount(data, userID: operation.ownerID)
        }
        return verifiedPersistenceOwnerID(operation.ownerID) == operation.ownerID
    }

    private func requireCurrentAccountOperation(_ operation: AccountOperationLease) throws {
        guard accountOperationIsCurrent(operation) else { throw CancellationError() }
    }

    static func healthImportOptInKey(ownerID: UUID) -> String {
        "apex.health-import.opt-in.\(ownerID.uuidString.lowercased())"
    }

    var healthImportIsEnabledForCurrentAccount: Bool {
        if isDeveloperSandbox { return false }
        guard let ownerID = authenticatedOwnerID ?? verifiedPersistenceOwnerID() else { return false }
        return defaults.bool(forKey: Self.healthImportOptInKey(ownerID: ownerID))
    }

    private func healthImportIsEnabled(operation: AccountOperationLease) -> Bool {
        !isDeveloperSandbox && accountOperationIsCurrent(operation)
            && defaults.bool(forKey: Self.healthImportOptInKey(ownerID: operation.ownerID))
    }

    private func enableHealthImport(operation: AccountOperationLease) throws {
        guard !isDeveloperSandbox else { throw CancellationError() }
        try requireCurrentAccountOperation(operation)
        defaults.set(true, forKey: Self.healthImportOptInKey(ownerID: operation.ownerID))
    }

    var profile: Profile? { data.profile }
    var isAuthenticated: Bool { authenticatedOwnerID != nil }

    var canOpenDeveloperSandbox: Bool {
        guard !isDeveloperSandbox, let owner = authenticatedOwnerID,
              let profile = data.profile, profile.userID == owner else { return false }
        #if DEBUG
        if ProcessInfo.processInfo.environment["APEX_UI_TESTING"] == "1",
           ProcessInfo.processInfo.arguments.contains("-apex-ui-test-developer-mode") { return true }
        #endif
        return ProfileIntegrityPolicy.authorizedProtocol(for: profile) == .constantineV85
    }

    var developerSandboxHasExternalDependencies: Bool {
        service.client != nil || hydrationConnectivity != nil
    }

    func invalidateDeveloperSandbox() {
        guard isDeveloperSandbox else { return }
        accountGeneration.advance()
        authenticatedOwnerID = nil
        realtimeDebounceTask?.cancel()
        workoutSyncTask?.cancel()
        data = .empty
        coachContext = .empty
        navigationPath = []
        if let sandboxDefaultsSuiteName {
            defaults.removePersistentDomain(forName: sandboxDefaultsSuiteName)
        }
    }

    private func accountAccessAllowsPrivateWork(for ownerID: UUID) -> Bool {
        if isDeveloperSandbox { return false }
        let entitlements = EntitlementStore.shared
        return authenticatedOwnerID == ownerID
            && entitlements.resolvedUserID == ownerID
            && entitlements.isUnlocked
    }

    /// Move an authenticated but denied account onto a protected route so the
    /// root can present recovery without exposing or loading private content.
    private func routeToAccessRecoveryBoundary(for ownerID: UUID) {
        guard authenticatedOwnerID == ownerID else { return }
        if suspendedAccessOwnerID != ownerID {
            suspendedAccessOwnerID = ownerID
            accountGeneration.advance()
            OrbitLocationManager.shared.releaseForAccountBoundary()
            HealthKitManager.shared.suspendPrivateWorkForAccessDenial()
            hydrationConnectivity?.publishDisconnected()
            realtimeDebounceTask?.cancel()
            realtimeDebounceTask = nil
            workoutSyncTask?.cancel()
            workoutSyncTask = nil
            // Denial deliberately advances the account generation. Clear
            // activity flags synchronously because their old-token defers must
            // not mutate this new protected boundary.
            isBusy = false
            isRefreshing = false
            accessServiceSuspensionTask = Task { [service] in
                await service.stopRealtime()
            }
        }
        route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
            ? .portal : .induction
    }

    var interfaceMode: PortalUIMode { PortalUIMode.current(from: data.settings) }
    /// Presentation-only sample access never changes the server-owned entitlement store.
    var interfaceAccess: Entitlement.Access {
        guard let developerSandboxRole else { return EntitlementStore.shared.access }
        switch developerSandboxRole {
        case .individual: return .subscribed(.premium)
        case .coach: return .subscribed(.coach)
        case .trial: return .beta
        case .invitedClient, .unsubscribed:
            return coachContext.sponsorship?.relationshipStatus == .active
                && coachContext.sponsorship?.seatState == .active ? .sponsored : .locked
        }
    }
    var coachClientPolicy: CoachClientPolicy {
        CoachClientPolicy.resolve(
            relationshipStatus: coachContext.sponsorship?.relationshipStatus,
            seatState: coachContext.sponsorship?.seatState,
            consentedScopes: coachContext.sponsorship?.consentedScopes ?? [],
            individualAccess: developerSandboxRole.map(\.hasIndividualAccess)
                ?? EntitlementStore.shared.hasIndividualAccess
        )
    }

    func portalDestinationIsAllowed(_ destination: PortalDestination) -> Bool {
        if isDeveloperSandbox && !Entitlement.isUnlocked(interfaceAccess) { return false }
        return coachClientPolicy.allows(
            destination,
            accountCapabilities: coachContext.capabilities
        )
    }

    @discardableResult
    func openPortalDestination(_ destination: PortalDestination) -> Bool {
        guard portalDestinationIsAllowed(destination) else {
            alertMessage = LanguageState.shared.text(
                "Your sponsored account keeps nutrition, Avatar and the coach plan focused. An individual subscription restores personal builders and Orbit."
            )
            return false
        }
        navigationPath.append(destination)
        return true
    }

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
        if isDeveloperSandbox { return }
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
                authenticatedOwnerID = Self.firstRunFixtureOwnerID
            }
            switch ProcessInfo.processInfo.arguments[index + 1] {
            case "welcome": route = .welcome
            case "induction": route = .induction
            case "consent": route = .consent
            case "persona": route = .persona
            case "access-recovery":
                route = .persona
                previewAccessRecovery = true
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
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("apex.baseline-calibration.v1.") {
                defaults.removeObject(forKey: key)
            }
            LanguageState.shared.language = .english
            if ProcessInfo.processInfo.arguments.contains("-fitr-ui-test-june-sunday") {
                data = APEXDebugFixture.juneSunday()
                browsingDate = APEXDateMath.date(from: "2026-11-08")!
            } else {
                data = APEXDebugFixture.dashboard()
            }
            if ProcessInfo.processInfo.arguments.contains("-fitr-ui-test-completion-repair"),
               var exercise = data.exercises.first {
                exercise.sets = 2
                data.exercises.removeAll { $0.programDayID == exercise.programDayID }
                data.exercises.append(exercise)
                data.settings?.voiceOn = false
                // A pre-update completed draft with the first set absent.
                // It must reopen, request explicit facts, and survive failed saving.
                PlayerTimeline.DraftStore.save(PlayerTimeline.SessionDraft(
                    userID: exercise.userID, dayID: exercise.programDayID,
                    date: Date().apexDateKey, lite: false, exerciseIDs: [exercise.id],
                    phase: "complete", currentIndex: 0, currentSet: 2,
                    actualReps: 8, currentWeight: 0,
                    timerRemaining: 0, timerTotal: 0, paused: false,
                    setInputs: [WorkoutSetInput(
                        exerciseID: exercise.id, exerciseName: exercise.name,
                        setNumber: 2, weightKG: nil, reps: 8, rir: nil,
                        movementID: exercise.movementID, skipped: false
                    )],
                    startedAt: Date().addingTimeInterval(-120),
                    repElapsed: 0, announcedRep: 8, persistedAt: Date().ISO8601Format()
                ))
            }
            if ProcessInfo.processInfo.arguments.contains("-fitr-ui-test-warmup-walk"),
               let program = data.programs.first(where: { $0.slug == "transition" }),
               let index = data.programDays.firstIndex(where: { $0.programID == program.id }) {
                data.settings?.voiceOn = false
                var day = data.programDays[index]
                day.name = "Rest · Full recovery"
                day.warmupNote = "Full rest. A gentle walk is optional."
                day.dayType = "mobility"
                day.estimatedMinutes = 0
                day.weekday = APEXDateMath.isoWeekday(Date().apexDateKey)
                data.programDays.removeAll { $0.programID == program.id }
                data.programDays.append(day)
                data.exercises.removeAll { $0.programDayID == day.id }
                PlayerTimeline.DraftStore.save(.init(
                    userID: day.userID, dayID: day.id, date: Date().apexDateKey, lite: false, exerciseIDs: [],
                    phase: "complete", currentIndex: 0, currentSet: 1, actualReps: 0, currentWeight: 0,
                    timerRemaining: 60, timerTotal: 180, paused: false, setInputs: [],
                    startedAt: Date().addingTimeInterval(-3600), repElapsed: 0, announcedRep: 0,
                    persistedAt: Date().addingTimeInterval(-3480).ISO8601Format()
                ))
            }
            if ProcessInfo.processInfo.arguments.contains("-fitr-ui-test-unilateral"),
               !data.exercises.isEmpty {
                data.settings?.voiceOn = false
                data.exercises[0].name = "Bulgarian Split Squat"
                data.exercises[0].perSide = true
                data.exercises[0].sets = 2
                data.exercises[0].repMin = 2
                data.exercises[0].repMax = 2
                data.exercises[0].restSeconds = 120
            }
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-bespoke-v85") {
                let owner = UUID(uuidString: "9a0fffbc-bb02-40ac-834a-d4e339b32574")!
                data = APEXDebugFixture.dashboard(userID: owner)
                data.profile?.profileKind = .bespoke
                data.profile?.bespokeProtocolID = .constantineV85
                data.profile?.seedVersion = 7
                data.settings?.addons["training_protocol"] = .object([
                    "version": .number(83), "start_date": .string(Date().apexDateKey)
                ])
                if let upgrade = try? BespokeProgrammeUpgrade.prepare(in: data, authenticatedOwnerID: owner) {
                    data = upgrade.dashboard
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-close-dayline-meals"),
               var settings = data.settings {
                settings.addons["meal_blocks"] = .object([
                    "blocks": .array([
                        .object(["id": .string("breakfast"), "time": .string("07:00"), "enabled": .bool(true)]),
                        .object(["id": .string("lunch"), "time": .string("07:10"), "enabled": .bool(true)]),
                    ]),
                ])
                data.settings = settings
            }
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-installed-plan"),
               var settings = data.settings {
                // The installed-plan walkthrough checks the controls of a prescribed Monday.
                let date = "2026-11-02"
                browsingDate = APEXDateMath.date(from: date)!
                let generated = TrainingInduction.generate(
                    userID: settings.userID,
                    input: TrainingInduction.Input(startDate: date),
                    existingPrograms: data.programs
                )
                settings.addons["training_induction"] = .object(generated.induction)
                data = TrainingInduction.applyingGeneratedPlan(
                    generated,
                    settings: settings,
                    to: data
                )
            }
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
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-open-water"),
               var settings = data.settings {
                settings.addons["uiMode"] = .string(PortalUIMode.simple.rawValue)
                data.settings = settings
            }
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-coach-workspace") {
                coachContext = APEXDebugFixture.coachWorkspaceContext()
                navigationPath = [.coachWorkspace]
            }
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-coach-plan") {
                coachContext = APEXDebugFixture.coachPlanContext()
                navigationPath = [.coachPlan]
            }
            if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-failed-sync"),
               let debugProfile = data.profile,
               let operationID = UUID(uuidString: "B72E51D1-5D0B-4585-B361-9AF511F98964"),
               let recordID = UUID(uuidString: "B5325F4F-BCB4-48A2-AF63-2CD80312A14E") {
                let rejectedWrite = OfflineOperation(
                    id: operationID,
                    kind: .delete,
                    table: "meal_logs",
                    payload: nil,
                    recordID: recordID,
                    onConflict: nil,
                    rpcFunction: nil,
                    createdAt: .now
                )
                try? await offlineStore.recordFailure(
                    rejectedWrite,
                    reason: "UI fixture: server rejected this write",
                    for: debugProfile.userID
                )
                failedSyncCount = (try? await offlineStore.failedOperations(for: debugProfile.userID).count) ?? 1
            }
            if let debugProfile = data.profile {
                authenticatedOwnerID = debugProfile.userID
                EntitlementStore.shared.prepareForAccount(debugProfile.userID)
                let sponsored = coachContext.sponsorship?.relationshipStatus == .active
                    && coachContext.sponsorship?.seatState == .active
                EntitlementStore.shared.resolveDebugFixture(
                    userID: debugProfile.userID,
                    sponsoredSeatActive: sponsored
                )
            }
            route = .portal
            return
        }
        #endif

        if let userID = await service.currentUserID() {
            guard accountGeneration.accepts(accountToken) else { return }
            authenticatedOwnerID = userID
            EntitlementStore.shared.prepareForAccount(userID)
            if let cachedAccess = try? await offlineStore.loadAccountAccess(for: userID) {
                _ = EntitlementStore.shared.resolve(
                    cached: cachedAccess,
                    expectedUserID: userID,
                    currentBuild: Self.clientBuildNumber
                )
            }
            if accountAccessAllowsPrivateWork(for: userID) {
                let cached = try? await offlineStore.loadDashboard(for: userID)
                guard accountGeneration.accepts(accountToken) else { return }
                if let cached, TrainingInduction.belongsToAccount(cached, userID: userID) {
                    var hydratedCache = cached
                    let migratedRestingEnergySettings = RestingEnergyPolicy.migrateLegacyProfileValue(
                        in: &hydratedCache,
                        ownerID: userID
                    )
                    hydratedCache.foods = hydratedCache.foods.map(FoodHydration.resolved)
                    data = hydratedCache
                    route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                        ? .portal : .induction
                    if migratedRestingEnergySettings != nil {
                        try? await offlineStore.saveDashboard(hydratedCache, for: userID)
                        guard accountGeneration.accepts(accountToken) else { return }
                    }
                }
            }
            do {
                do {
                    try await refreshAccountAccess(expectedUserID: userID)
                } catch {
                    EntitlementStore.shared.markUnavailable(expectedUserID: userID)
                }
                guard accountGeneration.accepts(accountToken) else { return }
                guard accountAccessAllowsPrivateWork(for: userID) else {
                    routeToAccessRecoveryBoundary(for: userID)
                    return
                }
                if data.profile == nil,
                   data.settings == nil,
                   let cached = try? await offlineStore.loadDashboard(for: userID),
                   TrainingInduction.belongsToAccount(cached, userID: userID) {
                    var hydratedCache = cached
                    let migratedRestingEnergySettings = RestingEnergyPolicy.migrateLegacyProfileValue(
                        in: &hydratedCache,
                        ownerID: userID
                    )
                    hydratedCache.foods = hydratedCache.foods.map(FoodHydration.resolved)
                    data = hydratedCache
                    route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                        ? .portal : .induction
                    if migratedRestingEnergySettings != nil {
                        try? await offlineStore.saveDashboard(hydratedCache, for: userID)
                        guard accountGeneration.accepts(accountToken) else { return }
                    }
                }
                await flushPendingChanges(for: userID)
                guard accountGeneration.accepts(accountToken) else { return }
                try await refreshDashboard(expectedUserID: userID, refreshAccess: false)
                guard accountGeneration.accepts(accountToken) else { return }
                route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                    ? .portal : .induction
                guard let operation = accountOperationLease() else { return }
                await startRealtimeSync(operation: operation)
                guard accountGeneration.accepts(accountToken) else { return }
                await importHealthQuietly(operation: operation)
                return
            } catch {
                guard accountGeneration.accepts(accountToken) else { return }
                guard accountAccessAllowsPrivateWork(for: userID) else {
                    routeToAccessRecoveryBoundary(for: userID)
                    return
                }
                if TrainingInduction.belongsToAccount(data, userID: userID) {
                    /* No alert: the sync indicator already shows this, and a modal on
                       every launch without signal trains people to dismiss modals. */
                    /* Health still imports. It comes off the phone, not the
                       network, so a failed refresh is no reason to leave the
                       day's steps unread. */
                    guard let operation = accountOperationLease() else { return }
                    await importHealthQuietly(operation: operation)
                    return
                }
                route = .induction
                return
            }
        }

        /* No session: the public front door, not the portrait wall. The four
           bespoke accounts reach their portraits from a link on it. */
        guard accountGeneration.accepts(accountToken) else { return }
        route = .welcome
    }

    func choose(_ persona: Persona) {
        route = .login(persona)
    }

    func returnToPersonas() {
        route = .persona
    }

    func signIn(email: String, password: String) async {
        if isDeveloperSandbox { return }
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
            authenticatedOwnerID = userID
            try await refreshDashboard(expectedUserID: userID)
            guard accountGeneration.accepts(accountToken) else { return }
            if let profile = data.profile, profile.foundingMember == true, route != .login(profile.persona) {
                greetingPersona = profile.persona
            }
            route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                ? .portal : .induction
            guard let operation = accountOperationLease() else { return }
            await startRealtimeSync(operation: operation)
        } catch is CancellationError {
            return
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
        if isDeveloperSandbox { return }
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
                authenticatedOwnerID = userID
                EntitlementStore.shared.prepareForAccount(userID)
                do {
                    try await refreshAccountAccess(expectedUserID: userID)
                } catch {
                    EntitlementStore.shared.markUnavailable(expectedUserID: userID)
                }
                guard accountGeneration.accepts(accountToken) else { return }
                data = .empty
                route = .induction
            case .awaitingEmailConfirmation:
                awaitingConfirmationFor = email
            }
        } catch is CancellationError {
            return
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
        if isDeveloperSandbox { return }
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
            authenticatedOwnerID = userID
            try await refreshDashboard(expectedUserID: userID)
            guard accountGeneration.accepts(accountToken) else { return }
            /* A returning Apple account already has a profile and goes home. A
               first-time one has none, and answers the questionnaire instead. */
            route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                ? .portal : .induction
            guard let operation = accountOperationLease() else { return }
            await startRealtimeSync(operation: operation)
        } catch is CancellationError {
            return
        } catch {
            guard accountGeneration.accepts(accountToken) else { return }
            if !boundaryCompleted {
                accountToken = completeAccountBoundary()
                boundaryCompleted = true
            }
            alertMessage = error.localizedDescription
        }
    }

    var inductionRequiresStartingPoints: Bool {
        coachClientPolicy.canUseAvatar && (profile?.needsAvatarStartingPoints ?? true)
    }

    /// Turn questionnaire answers into a profile and a first twelve weeks.
    func completeInduction(
        _ input: TrainingInduction.Input,
        operation: AccountOperationLease
    ) async {
        await submitInduction(.answered(input), operation: operation)
    }

    /// Keep the facts required for honest nutrition, but leave every optional
    /// workout answer unclaimed when the person skips the remaining pages.
    func skipRemainingInduction(
        _ input: TrainingInduction.Input,
        operation: AccountOperationLease
    ) async {
        guard accountOperationIsCurrent(operation) else { return }
        guard TrainingInduction.canSkipRemaining(step: 3, input: input) else {
            alertMessage = "Complete consent, body details and your goal first."
            return
        }
        await submitInduction(.baselineOnly(input), operation: operation)
    }

    /// Continue without turning questionnaire defaults into claimed facts.
    /// Only an account-scoped settings marker is stored; there is deliberately
    /// no profile, generated programme or derived fitness snapshot.
    func skipInduction(operation: AccountOperationLease) async {
        await submitInduction(.skipped, operation: operation)
    }

    private func submitInduction(
        _ submission: TrainingInduction.Submission,
        operation: AccountOperationLease
    ) async {
        guard accountOperationIsCurrent(operation) else { return }
        if inductionRequiresStartingPoints && submission.avatarStartingPoints == nil {
            alertMessage = "Choose starting points"
            return
        }
        if isDeveloperSandbox {
            let baseline = DeveloperSandboxSamples.dashboard(ownerID: operation.ownerID, name: "Sample")
            var settings = data.settings ?? baseline.settings!
            let plan = submission.generatedPlan(userID: operation.ownerID, existingPrograms: data.programs)
            settings = submission.applyingAccountMetadata(to: settings, plan: plan, existingData: data)
            data.foods = baseline.foods
            data.profile = submission.requiresProfile ? baseline.profile : nil
            data.profile?.avatarStartingPointsRequired = true
            data.profile?.avatarStartingPoints = submission.avatarStartingPoints
            if let goal = submission.profileGoal.flatMap(Goal.init(rawValue:)) { data.profile?.goal = goal }
            if let facts = submission.profileBaseline {
                data.profile?.sex = facts.sex
                data.profile?.weightKG = facts.weightKG
                data.profile?.heightCM = facts.heightCM
                data.profile?.birthdate = facts.birthdate
            }
            if let activity = submission.profileActivityLevel { data.profile?.activityLevel = activity }
            data.settings = settings
            if let plan { applyInductionPlan(plan, settings: settings) }
            try? await recordSignUpWeighIn(submission, operation: operation)
            await persistInductionEvidence(submission, operation: operation)
            guard accountOperationIsCurrent(operation) else { return }
            InductionView.clearDraft(operation.ownerID)
            route = .consent
            return
        }
        do { try requireCurrentAccountOperation(operation) }
        catch { return }
        guard !isBusy else { return }
        isBusy = true
        defer {
            if accountOperationIsCurrent(operation) { isBusy = false }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-first-run") {
            submitInductionToFirstRunFixture(submission, operation: operation)
            return
        }
        #endif
        guard let userID = await service.currentUserID() else {
            guard accountOperationIsCurrent(operation) else { return }
            alertMessage = "Sign in again to continue."
            route = .welcome
            return
        }
        guard accountOperationIsCurrent(operation), userID == operation.ownerID else { return }
        do {
            var settings = try await service.createSettingsIfNeeded(userID: userID).rebound(to: userID)
            try requireCurrentAccountOperation(operation)

            let plan = submission.generatedPlan(
                userID: userID,
                existingPrograms: data.programs,
                generationRevision: TrainingInduction.generationRevision(settings)
            )
            if let plan {
                settings = TrainingInduction.markingPendingPlan(settings, plan: plan)
                try await service.upsert(settings, table: "settings", onConflict: "user_id")
                try requireCurrentAccountOperation(operation)
                data.settings = settings
                try await saveLocalSnapshot(operation: operation)
                try await service.saveInductionPlan(plan)
                try requireCurrentAccountOperation(operation)
            }
            settings = submission.applyingAccountMetadata(
                to: settings,
                plan: plan,
                existingData: data
            )
            try await service.upsert(settings, table: "settings", onConflict: "user_id")
            try requireCurrentAccountOperation(operation)
            if let plan { applyInductionPlan(plan, settings: settings) }
            else { data.settings = settings }
            if submission.requiresProfile {
                let profile = try await service.createProfileIfNeeded(
                    userID: userID,
                    goal: submission.profileGoal,
                    baseline: submission.profileBaseline,
                    activityLevel: submission.profileActivityLevel,
                    avatarStartingPoints: submission.avatarStartingPoints
                )
                try requireCurrentAccountOperation(operation)
                guard profile.userID == operation.ownerID else { throw CancellationError() }
                data.profile = profile
                try await recordSignUpWeighIn(submission, operation: operation)
            }
            await persistInductionEvidence(submission, operation: operation)
            try await saveLocalSnapshot(operation: operation)
            do { try await refreshDashboard(expectedUserID: userID) }
            catch {
                try requireCurrentAccountOperation(operation)
                lastSyncAt = .now
            }
            try requireCurrentAccountOperation(operation)
            await resolveEntitlements()
            try requireCurrentAccountOperation(operation)
            InductionView.clearDraft(operation.ownerID)
            route = .consent
        } catch is CancellationError {
            return
        } catch {
            guard accountOperationIsCurrent(operation) else { return }
            alertMessage = error.localizedDescription
        }
    }

    private func persistInductionEvidence(
        _ submission: TrainingInduction.Submission,
        operation: AccountOperationLease
    ) async {
        let userID = operation.ownerID
        let importedAt = ISO8601DateFormatter().string(from: .now)
        for draft in submission.fitnessEvidenceDrafts(userID: userID, importedAt: importedAt) {
            guard accountOperationIsCurrent(operation),
                  case .accepted(let evidence) = FitnessEvidenceNormalizer.normalize(
                    draft,
                    admission: .user,
                    referenceNow: importedAt
                  ) else { return }
            do {
                try await recordFitnessEvidence(evidence, operation: operation)
            } catch is CancellationError {
                return
            } catch {
                // Raw answers remain in account-owned induction metadata and
                // transient RPC failures are already queued by the ledger.
                // A baseline sync issue must never strand a new account after
                // its profile and programme have been committed.
                continue
            }
        }
    }

    /// The weight typed at sign-up is that day's weigh-in, so a later reading is ordered against a dated one.
    private func recordSignUpWeighIn(
        _ submission: TrainingInduction.Submission,
        operation: AccountOperationLease
    ) async throws {
        // An account that already had a profile keeps its weight, and gets no weigh-in it never gave.
        guard let typed = submission.profileBaseline?.weightKG, data.profile?.weightKG == typed else { return }
        try await saveMorningWeight(typed, on: .now, operation: operation)
    }

    #if DEBUG
    /// Deterministic authenticated first-run account used only by UI tests.
    /// It exercises the real submission and routing decisions without touching
    /// production Supabase data or allowing a preview-only no-op to pass.
    private func submitInductionToFirstRunFixture(
        _ submission: TrainingInduction.Submission,
        operation: AccountOperationLease
    ) {
        guard accountOperationIsCurrent(operation),
              operation.ownerID == Self.firstRunFixtureOwnerID else { return }
        let userID = operation.ownerID
        let fixture = APEXDebugFixture.dashboard(userID: userID)
        var settings = fixture.settings!
        settings.addons = [:]
        let plan = submission.generatedPlan(userID: userID, existingPrograms: [])
        settings = submission.applyingAccountMetadata(to: settings, plan: plan, existingData: data)

        data.profile = submission.requiresProfile ? fixture.profile : nil
        data.profile?.avatarStartingPointsRequired = true
        data.profile?.avatarStartingPoints = submission.avatarStartingPoints
        if let goal = submission.profileGoal.flatMap(Goal.init(rawValue:)) {
            data.profile?.goal = goal
        }
        if let baseline = submission.profileBaseline {
            data.profile?.sex = baseline.sex
            data.profile?.weightKG = baseline.weightKG
            data.profile?.heightCM = baseline.heightCM
            data.profile?.birthdate = baseline.birthdate
        }
        if let activityLevel = submission.profileActivityLevel {
            data.profile?.activityLevel = activityLevel
        }
        data.settings = settings
        data.programs = plan?.programs ?? []
        data.programDays = plan?.programDays ?? []
        data.exercises = plan?.exercises ?? []
        data.snapshots = []
        EntitlementStore.shared.prepareForAccount(userID)
        if let profile = data.profile {
            EntitlementStore.shared.resolveDebugFixture(userID: profile.userID)
        }
        route = .consent
    }
    #endif

    /// The last step of a first run: permissions have been offered and the
    /// authenticated account opens for real.
    func finishOnboarding(operation: AccountOperationLease) async {
        guard accountOperationIsCurrent(operation) else { return }
        route = .portal
        await startRealtimeSync(operation: operation)
        guard accountOperationIsCurrent(operation) else { return }
        try? await refreshNudges(operation: operation)
        guard accountOperationIsCurrent(operation) else { return }
    }

    private static let recoveryEmailKey = "fitr.pending-recovery.email"
    private static let recoveryExpiryKey = "fitr.pending-recovery.expiry"

    func requestPasswordReset(_ email: String) async throws {
        try await service.requestPasswordReset(email: email)
        UserDefaults.standard.set(email.lowercased(), forKey: Self.recoveryEmailKey)
        UserDefaults.standard.set(Date().addingTimeInterval(3600), forKey: Self.recoveryExpiryKey)
    }

    func finishPasswordReset(_ password: String) async throws {
        guard route == .resetPassword, let owner = authenticatedOwnerID else { throw CancellationError() }
        try await service.updateRecoveredPassword(password, owner: owner)
        guard authenticatedOwnerID == owner else { throw CancellationError() }
        await signOut(scope: .global)
        alertMessage = "Password updated. Sign in with your new password."
    }

    func deleteMyAccount(operation: AccountOperationLease) async throws {
        try requireCurrentAccountOperation(operation)
        guard !isDeveloperSandbox, !APEXRuntimeEnvironment.usesLocalUITestFixture() else { throw CancellationError() }
        try await service.deleteAuthenticatedAccount(owner: operation.ownerID)
        if accountOperationIsCurrent(operation) { await signOut() }
        let ownerKey = operation.ownerID.uuidString.lowercased()
        for key in defaults.dictionaryRepresentation().keys where key.lowercased().contains(ownerKey) {
            defaults.removeObject(forKey: key)
        }
        try await offlineStore.eraseAccount(operation.ownerID)
    }

    func signOut(scope: SignOutScope = .local) async {
        if let owner = accountOperationLease()?.ownerID { InductionView.clearDraft(owner) }
        UserDefaults.standard.removeObject(forKey: Self.recoveryEmailKey)
        UserDefaults.standard.removeObject(forKey: Self.recoveryExpiryKey)
        if isDeveloperSandbox { invalidateDeveloperSandbox(); route = .welcome; return }
        var accountToken = beginAccountBoundary()
        accountToken = completeAccountBoundary()
        route = .welcome
        isBusy = true
        defer {
            if accountGeneration.accepts(accountToken) { isBusy = false }
        }
        do {
            try await service.signOut(scope: scope)
        } catch {
            /* The local privacy boundary and exit are already complete. If the
               network sign-out fails, keep the user safely outside rather than
               resurrecting the account or trapping them behind recovery. */
            guard accountGeneration.accepts(accountToken) else { return }
        }
    }

    func refreshDashboard(
        expectedUserID: UUID? = nil,
        refreshAccess: Bool = true
    ) async throws {
        if isDeveloperSandbox { return }
        let accountToken = accountGeneration.token
        isRefreshing = true
        defer {
            if accountGeneration.accepts(accountToken) { isRefreshing = false }
        }
        guard let ownerID = expectedUserID ?? authenticatedOwnerID else {
            throw CancellationError()
        }
        if refreshAccess {
            await resolveEntitlements()
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
        }
        guard accountAccessAllowsPrivateWork(for: ownerID) else {
            routeToAccessRecoveryBoundary(for: ownerID)
            throw CancellationError()
        }
        var followUpRefreshAvailable = true
        var refreshedUserID: UUID?
        while true {
        let supplementRefreshRevision = watchSupplementJournal(ownerID: ownerID).revision
        let pendingSupplementsAtStart = ((try? await offlineStore.pendingOperations(for: ownerID)) ?? [])
            .filter { $0.table == "supplement_logs" }
        guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
        var next = try await service.loadDashboard()
        var keptCachedDashboard = false
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
        refreshedUserID = authenticatedUserID
        if let authenticatedUserID,
           let bootstrap = TrainingInduction.missingProfileBootstrap(
               in: next,
               authenticatedUserID: authenticatedUserID
           ) {
            next.profile = try await service.createProfileIfNeeded(
                userID: bootstrap.userID,
                goal: bootstrap.goal
            )
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
        }
        if let authenticatedUserID {
            EntitlementStore.shared.prepareForAccount(authenticatedUserID)
            next.settings = next.settings?.rebound(to: authenticatedUserID)
        }
        if let authenticatedUserID,
           let installation = try BespokeProgrammeUpgrade.prepare(in: next, authenticatedOwnerID: authenticatedUserID) {
            try await service.installBespokeProgramme(installation)
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
            next = installation.dashboard
        }
        var cachedDashboardForLegacyMigration: DashboardData?
        var pendingAfterReconciliation: [OfflineOperation]?
        var failuresAfterReconciliation: [FailedOfflineOperation]?
        if let userID = authenticatedUserID {
            let cachedDashboard = try? await offlineStore.loadDashboard(for: userID)
            cachedDashboardForLegacyMigration = cachedDashboard
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
            let reconciliation = try? await offlineStore.reconcileFailures(
                for: userID,
                dashboard: next
            )
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
            let requeuedOperationIDs = reconciliation?.requeuedOperationIDs ?? []
            if requeuedOperationIDs.isEmpty == false {
                await flushPendingChanges(for: userID)
                guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
                pendingAfterReconciliation = try? await offlineStore.pendingOperations(for: userID)
                guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
                failuresAfterReconciliation = try? await offlineStore.failedOperations(for: userID)
                guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
                switch OfflineFailureReplayRefreshPlan.make(
                    requeuedOperationIDs: requeuedOperationIDs,
                    pendingOperationIDs: pendingAfterReconciliation.map { Set($0.map(\.id)) },
                    failedOperationIDs: failuresAfterReconciliation.map { Set($0.map(\.id)) },
                    hasCachedDashboard: cachedDashboard != nil
                ) {
                case .reloadRemote:
                    if followUpRefreshAvailable {
                        followUpRefreshAvailable = false
                        continue
                    }
                    if let cachedDashboard { next = cachedDashboard; keptCachedDashboard = true }
                case .preserveCached:
                    if let cachedDashboard { next = cachedDashboard; keptCachedDashboard = true }
                case .useRemote:
                    break
                }
            }
        }
        let repairedPlanSettings: UserSettings?
        if let repaired = TrainingInduction.repairingProtectedOriginalProgramme(in: next) {
            next = repaired
            repairedPlanSettings = repaired.settings
        } else {
            repairedPlanSettings = nil
        }
        let migratedRestingEnergySettings: UserSettings?
        if let authenticatedUserID {
            migratedRestingEnergySettings = RestingEnergyPolicy.migrateLegacyProfileValue(
                in: &next,
                ownerID: authenticatedUserID,
                fallbackProfile: cachedDashboardForLegacyMigration?.profile
            )
        } else {
            migratedRestingEnergySettings = nil
        }
        next = await preservingPendingSupplementLogs(in: next, ownerID: ownerID,
            startedAtRevision: supplementRefreshRevision, pendingAtStart: pendingSupplementsAtStart)
        guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
        next.foods = next.foods.map(FoodHydration.resolved)
        var settingsWithWaitingHealthReads: UserSettings?
        if !keptCachedDashboard,
           let addons = serverSettings.serverCopyLoaded(for: authenticatedUserID, addons: next.settings?.addons) {
            // Health reads made over the older row go onto the server's row and are sent with it.
            next.settings?.addons = addons
            settingsWithWaitingHealthReads = next.settings
        }
        data = next
        if let settingsToPersist = settingsWithWaitingHealthReads ?? migratedRestingEnergySettings ?? repairedPlanSettings {
            await persistUpsert(
                settingsToPersist,
                table: "settings",
                onConflict: "user_id",
                ownerID: settingsToPersist.userID,
                expectedAccountToken: accountToken,
                surfacePermanentFailure: false
            )
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
        }
        if let authenticatedUserID {
            await ensureHydrationDefaults(ownerID: authenticatedUserID)
            publishHydrationState()
        }
        lastSyncAt = .now
        if let userID = authenticatedUserID {
            try? await offlineStore.saveDashboard(data, for: userID)
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
            let count: Int?
            if let pendingAfterReconciliation {
                count = pendingAfterReconciliation.count
            } else {
                count = try? await offlineStore.pendingOperations(for: userID).count
            }
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
            pendingSyncCount = count ?? 0
            let failures: [FailedOfflineOperation]?
            if let failuresAfterReconciliation {
                failures = failuresAfterReconciliation
            } else {
                failures = try? await offlineStore.failedOperations(for: userID)
            }
            guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
            if let failures {
                failedSyncOperations = failures
                failedSyncCount = failures.count
            }
        }
        break
        }
        if let operation = accountOperationLease() {
            try? await considerWeeklyCalibration(operation: operation)
        }
        guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
        await refreshCoachContext(expectedUserID: refreshedUserID)
        guard accountGeneration.accepts(accountToken) else { throw CancellationError() }
    }

    /// Store a new profile picture.
    ///
    /// Uploaded first, recorded second: a profile pointing at a file that was
    /// never stored would show a broken picture on every device the account
    /// opens on.
    func setAvatar(data: Data, operation: AccountOperationLease) async throws {
        if isDeveloperSandbox { throw CancellationError() }
        try requireCurrentAccountOperation(operation)
        guard verifiedPersistenceOwnerID(operation.ownerID) == operation.ownerID,
              var profile,
              profile.userID == operation.ownerID else { throw CancellationError() }
        let path: String
        do {
            path = try await service.uploadAvatar(userID: profile.userID, data: data)
        } catch {
                try requireCurrentAccountOperation(operation)
                throw error
        }
        try requireCurrentAccountOperation(operation)
        profile.avatarPath = path
        profile.updatedAt = Date().ISO8601Format()
        self.data.profile = profile
        await persistUpsert(
            profile,
            table: "profile",
            onConflict: "user_id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func signedAvatarURL(operation: AccountOperationLease) async throws -> URL {
        if isDeveloperSandbox { throw CancellationError() }
        try requireCurrentAccountOperation(operation)
        guard let profile, profile.userID == operation.ownerID,
              let path = profile.avatarPath,
              path.hasPrefix(operation.ownerID.uuidString.lowercased() + "/") else {
            throw CancellationError()
        }
        let url = try await service.signedProgressURL(path: path)
        try requireCurrentAccountOperation(operation)
        return url
    }

    /// Pull today's activity from Apple Health on open, without prompting.
    ///
    /// The phone records steps by itself, and a watch writes to the same place,
    /// so there is nothing to wait for and no reason to make anyone press a
    /// button for data the system already has.
    func importHealthQuietly(operation: AccountOperationLease) async {
        if isDeveloperSandbox { return }
        guard accountAccessAllowsPrivateWork(for: operation.ownerID),
              healthImportIsEnabled(operation: operation) else { return }
        await HealthKitManager.shared.requestNewReadAccessIfNeeded()
        guard accountOperationIsCurrent(operation) else { return }
        await mirrorFoodWaterToHealth(on: .now, operation: operation)
        guard accountOperationIsCurrent(operation) else { return }
        if let snapshot = await HealthKitManager.shared.silentRefresh(ownerID: operation.ownerID) {
            guard accountOperationIsCurrent(operation) else { return }
            await applyHealthSnapshot(snapshot, operation: operation)
        } else {
            guard accountOperationIsCurrent(operation) else { return }
            await importHealthWorkoutChanges(operation: operation)
        }
    }

    func connectHealth(operation: AccountOperationLease) async -> Bool {
        if isDeveloperSandbox { return false }
        do {
            try enableHealthImport(operation: operation)
        } catch {
            return false
        }
        let snapshot = await HealthKitManager.shared.requestAccessAndImport(
            ownerID: operation.ownerID
        )
        guard accountOperationIsCurrent(operation) else { return false }
        bindHealthBackgroundMonitoring(operation: operation)
        guard let snapshot else { return false }
        await applyHealthSnapshot(snapshot, operation: operation)
        return accountOperationIsCurrent(operation)
    }

    func reconnectHealthWaterAccess(operation: AccountOperationLease) async {
        if isDeveloperSandbox { return }
        do { try enableHealthImport(operation: operation) }
        catch { return }
        await HealthKitManager.shared.reconnectWaterAccess()
        guard accountOperationIsCurrent(operation) else { return }
        if HealthKitManager.shared.waterWriteState == .authorized {
            await importHealthQuietly(operation: operation)
        }
    }

    func startWatchWorkout(
        day: ProgramDay,
        exercises: [Exercise],
        launchID: UUID,
        operation: AccountOperationLease
    ) async {
        if isDeveloperSandbox { return }
        guard Task.isCancelled == false,
              accountOperationIsCurrent(operation),
              TrainingInduction.workoutOwnerID(in: data, day: day) == operation.ownerID,
              exercises.allSatisfy({
                  $0.userID == operation.ownerID && $0.programDayID == day.id
              }) else { return }
        let kind = WatchWorkoutHandoff.resolve(
            dayType: day.dayType,
            name: day.name,
            exerciseNames: exercises.map(\.name)
        )
        // Preserve the request's causal time across the asynchronous HealthKit
        // handoff. If an account disconnect lands while this await is pending,
        // the Watch can reject the older launch even if its command arrives late.
        let launchCommand = WatchWorkoutCommand.starting(
            ownerID: operation.ownerID,
            launchID: launchID
        )
        let started = await HealthKitManager.shared.startWatchWorkout(kind)
        guard started else { return }
        // The Watch queues an early HKWorkoutConfiguration until this identity
        // arrives. Sending only after a successful handoff also prevents a
        // failed launch intent from consuming a later configuration.
        hydrationConnectivity?.send(launchCommand)
        guard Task.isCancelled == false,
              accountOperationIsCurrent(operation) else {
            /* Stop may have been sent while HealthKit was still launching the
               Watch app. Repeat it after a late successful launch so a
               dismissed or previous-account workout cannot remain active. */
            stopWatchWorkout(launchID: launchID, operation: operation)
            return
        }
    }

    func stopWatchWorkout(
        launchID: UUID,
        operation: AccountOperationLease
    ) {
        if isDeveloperSandbox { return }
        /* Disappearance can be caused by an account boundary. Owner plus launch
           identity means a delayed stop cannot terminate a newer session for
           that same owner. */
        hydrationConnectivity?.send(.stopping(
            ownerID: operation.ownerID,
            launchID: launchID
        ))
    }

    private static var clientBuildNumber: Int {
        let bundleVersionKey = kCFBundleVersionKey as String
        if let number = Bundle.main.object(forInfoDictionaryKey: bundleVersionKey) as? NSNumber {
            return number.intValue
        }
        if let string = Bundle.main.object(forInfoDictionaryKey: bundleVersionKey) as? String {
            return Int(string) ?? 0
        }
        return 0
    }

    /// Refresh the small account-access fact independently of the dashboard.
    /// This keeps a profileless first run and a slow/failed dashboard fetch
    /// from being misreported as an access denial.
    func refreshAccountAccess(expectedUserID: UUID? = nil) async throws {
        if isDeveloperSandbox { return }
        let accountToken = accountGeneration.token
        guard let ownerID = expectedUserID ?? authenticatedOwnerID,
              authenticatedOwnerID == ownerID else {
            throw CancellationError()
        }
        EntitlementStore.shared.prepareForAccount(ownerID)
        let envelope = try await service.loadAccountAccess(
            platform: "ios",
            build: Self.clientBuildNumber
        )
        guard accountGeneration.accepts(accountToken),
              authenticatedOwnerID == ownerID else { throw CancellationError() }
        guard EntitlementStore.shared.resolve(
            envelope: envelope,
            expectedUserID: ownerID
        ) else {
            EntitlementStore.shared.markUnavailable(expectedUserID: ownerID)
            throw AccountAccessValidationError.invalidEnvelope
        }
        if EntitlementStore.shared.isUnlocked {
            suspendedAccessOwnerID = nil
        }
        try? await offlineStore.saveAccountAccess(envelope, for: ownerID)
    }

    func resolveEntitlements() async {
        if isDeveloperSandbox { return }
        guard let ownerID = authenticatedOwnerID else { return }
        do {
            try await refreshAccountAccess(expectedUserID: ownerID)
        } catch is CancellationError {
            return
        } catch {
            EntitlementStore.shared.markUnavailable(expectedUserID: ownerID)
        }
    }

    /// Rebuild account services only after recovery has obtained a fresh,
    /// owner-matched grant. Sensor and realtime work were stopped at denial.
    func resumePrivateWorkAfterAccessRecovery(
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard accountAccessAllowsPrivateWork(for: operation.ownerID) else {
            throw AccountAccessValidationError.invalidEnvelope
        }
        if let accessServiceSuspensionTask {
            await accessServiceSuspensionTask.value
            self.accessServiceSuspensionTask = nil
        }
        try requireCurrentAccountOperation(operation)
        try await refreshDashboard(
            expectedUserID: operation.ownerID,
            refreshAccess: false
        )
        try requireCurrentAccountOperation(operation)
        route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
            ? .portal : .induction
        if route == .portal {
            await startRealtimeSync(operation: operation)
            try requireCurrentAccountOperation(operation)
            await importHealthQuietly(operation: operation)
        }
    }

    func refreshCoachContext(expectedUserID: UUID? = nil) async {
        if isDeveloperSandbox { return }
        guard let ownerID = verifiedPersistenceOwnerID(), expectedUserID == nil || expectedUserID == ownerID else {
            return
        }
        coachRefreshRevision &+= 1
        let revision = coachRefreshRevision
        let token = accountGeneration.token
        do {
            let context = try await service.loadCoachContext()
            guard coachRefreshRevision == revision, accountGeneration.accepts(token), verifiedPersistenceOwnerID(ownerID) == ownerID else { return }
            coachContext = context
        } catch is CancellationError {
            return
        } catch {
            // Preserve the last server-authoritative answer during a transient
            // outage. Account boundaries clear it synchronously above.
        }
    }

    func loadCoachRoster(
        query: String = "",
        operation: AccountOperationLease
    ) async throws -> [CoachRosterEntry] {
        if let sandboxSamples {
            try requireCurrentAccountOperation(operation)
            return sandboxSamples.coachRoster().filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
        }
        try requireCurrentAccountOperation(operation)
        #if DEBUG
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            let roster = APEXDebugFixture.coachRoster()
            let result = query.isEmpty
                ? roster
                : roster.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
            try requireCurrentAccountOperation(operation)
            return result
        }
        #endif
        do {
            let roster = try await service.loadCoachRoster(query: query)
            try requireCurrentAccountOperation(operation)
            return roster
        } catch {
            try requireCurrentAccountOperation(operation)
            throw error
        }
    }

    func createCoachInvitation(
        email: String,
        scopes: Set<CoachConsentScope>,
        visualProgressRequested: Bool,
        operation: AccountOperationLease
    ) async throws -> CoachInvitationReceipt {
        if isDeveloperSandbox {
            try requireCurrentAccountOperation(operation)
            return CoachInvitationReceipt(invitationID: UUID(), token: "sample-only-\(UUID().uuidString)",
                expiresAt: Date().addingTimeInterval(86400).ISO8601Format())
        }
        try requireCurrentAccountOperation(operation)
        do {
            let receipt = try await service.createCoachInvitation(
                email: email,
                scopes: scopes,
                visualProgressRequested: visualProgressRequested
            )
            try requireCurrentAccountOperation(operation)
            return receipt
        } catch {
            try requireCurrentAccountOperation(operation)
            throw error
        }
    }

    func previewCoachInvitation(
        token: String,
        operation: AccountOperationLease
    ) async throws -> CoachInvitationPreview {
        if isDeveloperSandbox {
            try requireCurrentAccountOperation(operation)
            guard token.hasPrefix("sample-only-") else { throw CancellationError() }
            return CoachInvitationPreview(coachDisplayName: LanguageState.shared.text("Sample coach"),
                requestedScopes: [.nutrition, .workouts, .hydration, .avatar],
                visualProgressRequested: false, expiresAt: Date().addingTimeInterval(86400).ISO8601Format())
        }
        try requireCurrentAccountOperation(operation)
        do {
            let preview = try await service.previewCoachInvitation(token: token)
            try requireCurrentAccountOperation(operation)
            return preview
        } catch {
            try requireCurrentAccountOperation(operation)
            throw error
        }
    }

    func acceptCoachInvitation(
        token: String,
        scopes: Set<CoachConsentScope>,
        visualProgressConsent: Bool,
        operation: AccountOperationLease
    ) async throws {
        if let sandboxSamples {
            try requireCurrentAccountOperation(operation)
            guard token.hasPrefix("sample-only-") else { throw CancellationError() }
            coachContext = sandboxSamples.coachPlanContext()
            try await updateCoachScopes(relationshipID: sandboxSamples.relationshipID, scopes: scopes,
                visualProgressConsent: false, operation: operation)
            return
        }
        try requireCurrentAccountOperation(operation)
        let context: CoachAccountContext
        do {
            context = try await service.acceptCoachInvitation(
                token: token,
                scopes: scopes,
                visualProgressConsent: visualProgressConsent
            )
        } catch {
                try requireCurrentAccountOperation(operation)
                throw error
        }
        try requireCurrentAccountOperation(operation)
        coachContext = context
        try await refreshAccountAccess(expectedUserID: operation.ownerID)
        try requireCurrentAccountOperation(operation)
    }

    func loadCoachClientOverview(
        relationshipID: UUID,
        operation: AccountOperationLease
    ) async throws -> CoachClientOverview {
        if let sandboxSamples {
            try requireCurrentAccountOperation(operation)
            guard let overview = sandboxSamples.coachClientOverview(), overview.relationshipID == relationshipID else { throw CancellationError() }
            return overview
        }
        try requireCurrentAccountOperation(operation)
        #if DEBUG
        if APEXRuntimeEnvironment.usesLocalUITestFixture(),
           let overview = APEXDebugFixture.coachClientOverview(),
           overview.relationshipID == relationshipID {
            try requireCurrentAccountOperation(operation)
            return overview
        }
        #endif
        do {
            let overview = try await service.loadCoachClientOverview(relationshipID: relationshipID)
            try requireCurrentAccountOperation(operation)
            return overview
        } catch {
            try requireCurrentAccountOperation(operation)
            throw error
        }
    }

    func saveCoachPlan(
        relationshipID: UUID,
        plan: CoachPlanDraft,
        expectedVersion: Int,
        operation: AccountOperationLease
    ) async throws -> CoachPlanVersionReceipt {
        if let sandboxSamples {
            try requireCurrentAccountOperation(operation)
            return try sandboxSamples.save(plan: plan, relationshipID: relationshipID, expectedVersion: expectedVersion, publish: false)
        }
        try requireCurrentAccountOperation(operation)
        do {
            let receipt = try await service.saveCoachPlan(
                relationshipID: relationshipID,
                plan: plan,
                expectedVersion: expectedVersion,
                publish: false
            )
            try requireCurrentAccountOperation(operation)
            return receipt
        } catch {
            try requireCurrentAccountOperation(operation)
            throw error
        }
    }

    func publishCoachPlan(
        relationshipID: UUID,
        plan: CoachPlanDraft,
        expectedVersion: Int,
        operation: AccountOperationLease
    ) async throws -> CoachPlanVersionReceipt {
        if let sandboxSamples {
            try requireCurrentAccountOperation(operation)
            return try sandboxSamples.save(plan: plan, relationshipID: relationshipID, expectedVersion: expectedVersion, publish: true)
        }
        try requireCurrentAccountOperation(operation)
        do {
            let receipt = try await service.saveCoachPlan(
                relationshipID: relationshipID,
                plan: plan,
                expectedVersion: expectedVersion,
                publish: true
            )
            try requireCurrentAccountOperation(operation)
            return receipt
        } catch {
            try requireCurrentAccountOperation(operation)
            throw error
        }
    }

    func acknowledgeCoachPlan(
        planVersionID: UUID,
        operation: AccountOperationLease
    ) async throws {
        if isDeveloperSandbox {
            try requireCurrentAccountOperation(operation)
            try updateSandboxPlanReceipt(planVersionID: planVersionID, activate: false, ownerID: operation.ownerID)
            return
        }
        try requireCurrentAccountOperation(operation)
        do {
            _ = try await service.acknowledgeCoachPlan(planVersionID: planVersionID)
        } catch {
            try requireCurrentAccountOperation(operation)
            throw error
        }
        try requireCurrentAccountOperation(operation)
        await refreshCoachContext()
        try requireCurrentAccountOperation(operation)
    }

    func activateCoachPlan(
        planVersionID: UUID,
        operation: AccountOperationLease
    ) async throws {
        if isDeveloperSandbox {
            try requireCurrentAccountOperation(operation)
            try updateSandboxPlanReceipt(planVersionID: planVersionID, activate: true, ownerID: operation.ownerID)
            return
        }
        try requireCurrentAccountOperation(operation)
        do {
            _ = try await service.activateCoachPlan(planVersionID: planVersionID)
        } catch {
            try requireCurrentAccountOperation(operation)
            throw error
        }
        try requireCurrentAccountOperation(operation)
        do {
            try await refreshDashboard()
            try requireCurrentAccountOperation(operation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try requireCurrentAccountOperation(operation)
            // Activation already succeeded server-side. Preserve that causal
            // result and refresh the coach envelope independently instead of
            // surfacing a retry that could imply the activation failed.
            await refreshCoachContext()
            try requireCurrentAccountOperation(operation)
        }
    }

    func updateCoachScopes(
        relationshipID: UUID,
        scopes: Set<CoachConsentScope>,
        visualProgressConsent: Bool,
        operation: AccountOperationLease
    ) async throws {
        if isDeveloperSandbox {
            try requireCurrentAccountOperation(operation)
            guard let sponsorship = coachContext.sponsorship, sponsorship.relationshipID == relationshipID else { throw CancellationError() }
            let updated = CoachSponsorshipSummary(relationshipID: relationshipID,
                coachDisplayName: sponsorship.coachDisplayName,
                relationshipStatus: sponsorship.relationshipStatus, seatState: sponsorship.seatState,
                offeredScopes: sponsorship.offeredScopes, consentedScopes: scopes.intersection(sponsorship.offeredScopes),
                graceEndsAt: sponsorship.graceEndsAt)
            coachContext = CoachAccountContext(coach: coachContext.coach, sponsorship: updated,
                currentPlan: coachContext.currentPlan, capabilities: coachContext.capabilities)
            return
        }
        try requireCurrentAccountOperation(operation)
        let context: CoachAccountContext
        do {
            context = try await service.updateCoachScopes(
                relationshipID: relationshipID,
                scopes: scopes,
                visualProgressConsent: visualProgressConsent
            )
        } catch {
                try requireCurrentAccountOperation(operation)
                throw error
        }
        try requireCurrentAccountOperation(operation)
        coachContext = context
    }

    func endCoachRelationship(
        relationshipID: UUID,
        operation: AccountOperationLease
    ) async throws {
        if isDeveloperSandbox {
            try requireCurrentAccountOperation(operation)
            guard coachContext.sponsorship?.relationshipID == relationshipID else { throw CancellationError() }
            coachContext = .empty
            route = .welcome
            return
        }
        try requireCurrentAccountOperation(operation)
        do {
            _ = try await service.endCoachRelationship(relationshipID: relationshipID)
        } catch {
            try requireCurrentAccountOperation(operation)
            throw error
        }
        try requireCurrentAccountOperation(operation)
        coachRefreshRevision &+= 1
        if let previous = coachContext.sponsorship, previous.relationshipID == relationshipID {
            let archive = CoachSponsorshipSummary(relationshipID: relationshipID,
                coachDisplayName: previous.coachDisplayName, relationshipStatus: .grace, seatState: .grace,
                offeredScopes: previous.offeredScopes, consentedScopes: [], graceEndsAt: nil)
            coachContext = CoachAccountContext(coach: coachContext.coach, sponsorship: archive, currentPlan: coachContext.currentPlan,
                capabilities: .init(coachWorkspace: coachContext.capabilities.coachWorkspace, sponsoredClient: false))
        }
        await refreshCoachContext()
        try requireCurrentAccountOperation(operation)
        await resolveEntitlements()
        try requireCurrentAccountOperation(operation)
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
        guard !brainRecomputing else { return }
        #if DEBUG
        // This explicit visual fixture supplies synthetic history; replaying
        // its single day of sample logs would replace the 90 plotted dates.
        if ProcessInfo.processInfo.arguments.contains("-apex-ui-test"),
           ProcessInfo.processInfo.arguments.contains("-fitr-ui-test-avatar-history") {
            brainSynergies = []
            return
        }
        #endif
        let goals = DailyWaterTargets(data: data, coachManaged: coachContext.capabilities.sponsoredClient && !coachClientPolicy.canCreateCustomWorkouts,
                                      followsCoach: coachClientPolicy.canFollowCoachPlan, includeCustom: coachClientPolicy.canCreateCustomWorkouts)
        let now = Date()
        guard let userID = data.profile?.userID,
              let scored = FitnessBrainService.scoredInput(from: data, waterTargets: goals, now: now) else {
            avatarDomainScores = [:]
            brainSynergies = []
            return
        }
        let result = FitnessBrainEngine.compute(scored.input, throughDate: now.apexDateKey)
        avatarDomainScores = result.domainScores

        let published = result.publishableSnapshots
        let rows = FitnessBrainService.appSnapshots(published, userID: userID)
        brainRecomputing = true
        data.snapshots = rows
        brainSynergies = result.synergies
        brainRecomputing = false

        guard !isDeveloperSandbox, verifiedPersistenceOwnerID(userID) == userID else { return }
        storeScoreGoalHistory(scored.history, changed: scored.historyChanged, userID: userID)
        if let raw = result.snapshots.last, let row = rows.last ?? FitnessBrainService.appSnapshots([raw], userID: userID).first {
            let publication = AvatarScorePublication(row: row, verified: published.last)
            guard lastAvatarPublication != publication else { scheduleFitnessBrainShadowObservation(); return }
            #if DEBUG
            // UI automation runs an unauthenticated local fixture; a remote
            // persist would fail into the offline path and raise an alert
            // over the screen mid-test.
            if APEXRuntimeEnvironment.usesLocalUITestFixture() { return }
            #endif
            let accountToken = accountGeneration.token
            let previous = avatarPublicationTask
            lastAvatarPublication = publication
            avatarPublicationTask = Task { [weak self] in
                await previous?.value
                guard let self,
                      !Task.isCancelled, self.lastAvatarPublication == publication,
                      self.accountGeneration.accepts(accountToken),
                      self.verifiedPersistenceOwnerID(userID) == userID else { return }
                do {
                    try await self.offlineStore.enqueueAvatarPublication(publication, for: userID)
                    guard self.accountGeneration.accepts(accountToken) else { return }
                    await self.flushPendingChanges(for: userID)
                } catch {
                    if self.accountGeneration.accepts(accountToken), self.lastAvatarPublication == publication {
                        self.lastAvatarPublication = nil
                    }
                }
            }
        }
        scheduleFitnessBrainShadowObservation()
    }

    /// Keeps the goals earlier days were graded against with the settings, so a goal changed
    /// later applies from that day and never regrades history.
    private func storeScoreGoalHistory(_ history: ScoreGoalHistory, changed: Bool, userID: UUID) {
        guard changed, var settings = data.settings, settings.userID == userID else { return }
        #if DEBUG
        // The local UI-test fixture is unauthenticated and must not reach the remote store.
        if APEXRuntimeEnvironment.usesLocalUITestFixture() { return }
        #endif
        settings.addons[ScoreGoalHistory.addonKey] = history.stored
        brainRecomputing = true
        data.settings = settings
        brainRecomputing = false
        // The scores already use the history. Sending it waits for the server's settings row,
        // and the recalculation that follows that load records the same change.
        guard serverSettings.allowsSave(for: userID) else { return }
        let accountToken = accountGeneration.token
        Task { [weak self] in
            guard let self, let latest = self.data.settings, latest.userID == userID else { return }
            await self.persistUpsert(
                latest, table: "settings", onConflict: "user_id", ownerID: userID,
                expectedAccountToken: accountToken, surfacePermanentFailure: false)
        }
    }

    private func scheduleFitnessBrainShadowObservation() {
        if isDeveloperSandbox { return }
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        if processInfo.environment["APEX_UI_TESTING"] == "1"
            || processInfo.arguments.contains(where: { $0.hasPrefix("-apex-ui-test") }) {
            return
        }
        #endif
        guard let profile,
              verifiedPersistenceOwnerID(profile.userID) == profile.userID else { return }
        let observedOn = Date().apexDateKey
        let resolved = ProfileIntegrityPolicy.resolve(profile)
        let observation = FitnessBrainShadowValidator.runtimeObservation(
            ownerID: profile.userID,
            observedOn: observedOn,
            platform: .ios,
            profileKind: resolved.kind == .bespoke ? .bespoke : .standard,
            birthdate: profile.birthdate,
            sex: profile.sex,
            legacySnapshots: data.snapshots,
            evidence: data.fitnessEvidence ?? []
        )
        let parameters = FitnessBrainShadowRPCParameters(observation: observation)
        guard let encoded = try? JSONEncoder().encode(parameters) else { return }
        let signature = "\(profile.userID.uuidString.lowercased()):\(encoded.base64EncodedString())"
        guard lastShadowObservationSignature != signature else { return }
        lastShadowObservationSignature = signature
        let ownerID = profile.userID
        let accountToken = accountGeneration.token

        Task { [weak self, offlineStore] in
            guard let self,
                  self.accountGeneration.accepts(accountToken),
                  self.verifiedPersistenceOwnerID(ownerID) == ownerID else { return }
            do {
                let operation = try OfflineOperation.rpc(
                    "record_fitness_brain_shadow_observation",
                    params: parameters
                )
                try await offlineStore.enqueueLatestFitnessBrainShadowObservation(
                    operation,
                    for: ownerID
                )
                guard self.accountGeneration.accepts(accountToken),
                      self.verifiedPersistenceOwnerID(ownerID) == ownerID else { return }
                self.pendingSyncCount = (try? await offlineStore.pendingOperations(for: ownerID).count)
                    ?? self.pendingSyncCount
                await self.flushPendingChanges(for: ownerID)
            } catch {
                // Shadow telemetry is observational only. A persistence error
                // must never alter or interrupt the user's visible v1 Avatar.
            }
        }
    }

    func refresh() async {
        if isDeveloperSandbox { return }
        await refresh(includeAccess: true)
    }

    private func refresh(includeAccess: Bool) async {
        if isDeveloperSandbox { return }
        if includeAccess { await resolveEntitlements() }
        guard let ownerID = authenticatedOwnerID else { return }
        guard accountAccessAllowsPrivateWork(for: ownerID) else {
            routeToAccessRecoveryBoundary(for: ownerID)
            return
        }
        await flushPendingChanges(for: ownerID)
        do { try await refreshDashboard(refreshAccess: false) }
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

    /// Moves the shared date to the new day when it was on today at the last check.
    /// A day the user browsed to stays put, and so does the day under an open workout.
    func followTodayAcrossMidnight(now: Date = .now) {
        guard !browsingDateHeld else { return }
        let today = now.apexDateKey
        if followedToday != today, browsingDate.apexDateKey == followedToday { browsingDate = now }
        followedToday = today
    }

    /// An open workout is built from the shared date, so the date holds while it is open
    /// and catches up with any day change when it closes.
    func holdBrowsingDate(_ held: Bool, now: Date = .now) {
        browsingDateHeld = held
        followTodayAcrossMidnight(now: now)
    }

    func onAppBecameActive() async {
        followTodayAcrossMidnight()
        #if DEBUG
        // UI automation uses a deterministic, local dashboard and must not
        // replace it with an unauthenticated network refresh when XCTest
        // brings the app to the foreground.
        if ProcessInfo.processInfo.arguments.contains("-apex-ui-test") { return }
        #endif
        await resolveEntitlements()
        guard let ownerID = authenticatedOwnerID else { return }
        guard accountAccessAllowsPrivateWork(for: ownerID) else {
            routeToAccessRecoveryBoundary(for: ownerID)
            return
        }
        guard route == .portal else { return }
        guard let operation = accountOperationLease() else { return }
        // The bell is about today. Re-read it from what is on the phone before the slower sync,
        // so yesterday's card is gone on reopening, and again once the sync has landed.
        try? await refreshNudges(operation: operation)
        await retryPendingHydrationMutations(operation: operation)
        guard accountOperationIsCurrent(operation) else { return }
        /* The refresh comes first: the Health import saves the whole settings row, so it
           has to start from the server's, or a change made on the website is overwritten.
           Health still imports when the refresh fails. It comes off the phone, not the
           network, and a failed request must not leave the day's steps unread. */
        await refresh(includeAccess: false)
        guard accountOperationIsCurrent(operation) else { return }
        await importHealthQuietly(operation: operation)
        guard accountOperationIsCurrent(operation) else { return }
        try? await refreshNudges(operation: operation)
    }

    func handleAuthCallback(_ url: URL) async {
        if isDeveloperSandbox { return }
        var accountToken = beginAccountBoundary()
        var switchedAccounts = false
        route = .launching
        EntitlementStore.shared.resetAccount()
        await service.stopRealtime()
        guard accountGeneration.accepts(accountToken) else { return }
        do {
            let userID = try await service.handleAuthCallback(url)
            if let expected = UserDefaults.standard.string(forKey: Self.recoveryEmailKey),
               let expiry = UserDefaults.standard.object(forKey: Self.recoveryExpiryKey) as? Date,
               expiry > Date(), let email = try await service.client?.auth.session.user.email,
               email.lowercased() == expected, accountGeneration.accepts(accountToken) {
                _ = completeAccountBoundary()
                authenticatedOwnerID = userID
                route = .resetPassword
                return
            }
            guard accountGeneration.accepts(accountToken) else { return }
            accountToken = completeAccountBoundary()
            switchedAccounts = true
            authenticatedOwnerID = userID
            EntitlementStore.shared.prepareForAccount(userID)
            if let cachedAccess = try? await offlineStore.loadAccountAccess(for: userID) {
                _ = EntitlementStore.shared.resolve(
                    cached: cachedAccess,
                    expectedUserID: userID,
                    currentBuild: Self.clientBuildNumber
                )
            }
            data = .empty
            pendingSyncCount = 0
            failedSyncCount = 0
            navigationPath.removeAll()
            /* A completed OAuth exchange proves identity, not that the
               account is new. Keep the route non-writable until either its
               owner-scoped cache or the server dashboard proves its state. */
            route = .launching
            if accountAccessAllowsPrivateWork(for: userID) {
                let cached = try? await offlineStore.loadDashboard(for: userID)
                guard accountGeneration.accepts(accountToken) else { return }
                if let cached,
                   TrainingInduction.belongsToAccount(cached, userID: userID) {
                    var hydratedCache = cached
                    RestingEnergyPolicy.migrateLegacyProfileValue(
                        in: &hydratedCache,
                        ownerID: userID
                    )
                    hydratedCache.foods = hydratedCache.foods.map(FoodHydration.resolved)
                    data = hydratedCache
                    route = TrainingInduction.shouldEnterPortal(
                        profile: hydratedCache.profile,
                        settings: hydratedCache.settings
                    ) ? .portal : .induction
                }
            }
            try await refreshDashboard(expectedUserID: userID)
            guard accountGeneration.accepts(accountToken) else { return }
            route = TrainingInduction.shouldEnterPortal(profile: data.profile, settings: data.settings)
                ? .portal : .induction
            if route == .portal, let operation = accountOperationLease() {
                await startRealtimeSync(operation: operation)
            }
        } catch is CancellationError {
            return
        } catch {
            guard accountGeneration.accepts(accountToken) else { return }
            if !switchedAccounts {
                let existingUserID = await service.currentUserID()
                guard accountGeneration.accepts(accountToken) else { return }
                if let existingUserID {
                    accountToken = completeAccountBoundary()
                    authenticatedOwnerID = existingUserID
                    EntitlementStore.shared.prepareForAccount(existingUserID)
                    if let cachedAccess = try? await offlineStore.loadAccountAccess(for: existingUserID) {
                        _ = EntitlementStore.shared.resolve(
                            cached: cachedAccess,
                            expectedUserID: existingUserID,
                            currentBuild: Self.clientBuildNumber
                        )
                    }
                    await resolveEntitlements()
                    guard accountGeneration.accepts(accountToken) else { return }
                    guard accountAccessAllowsPrivateWork(for: existingUserID) else {
                        routeToAccessRecoveryBoundary(for: existingUserID)
                        return
                    }
                    let cached = try? await offlineStore.loadDashboard(for: existingUserID)
                    guard accountGeneration.accepts(accountToken) else { return }
                    if let cached,
                       TrainingInduction.belongsToAccount(cached, userID: existingUserID) {
                        var hydratedCache = cached
                        RestingEnergyPolicy.migrateLegacyProfileValue(
                            in: &hydratedCache,
                            ownerID: existingUserID
                        )
                        hydratedCache.foods = hydratedCache.foods.map(FoodHydration.resolved)
                        data = hydratedCache
                        route = TrainingInduction.shouldEnterPortal(
                            profile: hydratedCache.profile,
                            settings: hydratedCache.settings
                        ) ? .portal : .induction
                        if route == .portal, let operation = accountOperationLease() {
                            await startRealtimeSync(operation: operation)
                        }
                    } else {
                        try? await service.signOut()
                        guard accountGeneration.accepts(accountToken) else { return }
                        accountToken = beginAccountBoundary()
                        route = .welcome
                    }
                } else {
                    accountToken = completeAccountBoundary()
                    route = .welcome
                }
            } else if switchedAccounts,
                      let ownerID = authenticatedOwnerID,
                      TrainingInduction.belongsToAccount(data, userID: ownerID) {
                /* The OAuth exchange and owner-scoped cache are enough to
                   restore a truthful offline portal, but not enough to leave
                   its account services dormant. Revalidate the auth session,
                   then rebuild all account-derived capabilities around the
                   cached owner. */
                let currentUserID = await service.currentUserID()
                guard accountGeneration.accepts(accountToken) else { return }
                if currentUserID == ownerID {
                    await refreshCoachContext(expectedUserID: ownerID)
                    guard accountGeneration.accepts(accountToken) else { return }
                    await resolveEntitlements()
                    guard accountGeneration.accepts(accountToken) else { return }
                    guard accountAccessAllowsPrivateWork(for: ownerID) else {
                        routeToAccessRecoveryBoundary(for: ownerID)
                        return
                    }
                    if route == .portal, let operation = accountOperationLease() {
                        await startRealtimeSync(operation: operation)
                    }
                } else {
                    try? await service.signOut()
                    guard accountGeneration.accepts(accountToken) else { return }
                    accountToken = beginAccountBoundary()
                    route = .welcome
                }
            } else if switchedAccounts {
                /* With neither server proof nor an owner-scoped cache, never
                   guess that a returning account is first-run. Return to a
                   clean auth surface and let the person retry safely. */
                try? await service.signOut()
                guard accountGeneration.accepts(accountToken) else { return }
                accountToken = beginAccountBoundary()
                route = .welcome
            }
            guard accountGeneration.accepts(accountToken) else { return }
            alertMessage = error.localizedDescription
        }
    }

    func toggleMeal(
        _ meal: Meal,
        on date: Date = .now,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard meal.userID == operation.ownerID else { throw CancellationError() }
        let day = date.apexDateKey
        if let existing = data.mealLogs.first(where: {
            $0.userID == operation.ownerID && $0.date == day && $0.mealID == meal.id
        }) {
            data.mealLogs.removeAll {
                $0.id == existing.id && $0.userID == operation.ownerID
            }
            await persistDelete(
                table: "meal_logs",
                id: existing.id,
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
        } else {
            let row = MealLog(
                id: UUID(), userID: operation.ownerID, date: day,
                mealID: meal.id, checkedAt: Date().ISO8601Format()
            )
            data.mealLogs.append(row)
            await persistUpsert(
                row,
                table: "meal_logs",
                onConflict: "user_id,date,meal_id",
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
        }
        try requireCurrentAccountOperation(operation)
    }

    /// Mirrors the browser Simple Mode contract: one tap records both the
    /// planned-meal completion and an exact structured nutrition snapshot.
    /// The shared idempotency key lets web and iOS converge on one meal.
    func togglePlannedMeal(
        _ prescription: AdaptiveMeal,
        on date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let profile, operation.ownerID == profile.userID else { throw CancellationError() }
        let meal = prescription.source
        guard meal.userID == operation.ownerID else { throw CancellationError() }
        let day = date.apexDateKey
        let existingCheck = data.mealLogs.first {
            $0.userID == operation.ownerID && $0.date == day && $0.mealID == meal.id
        }
        let existingStructured = data.loggedMeals.first {
            $0.userID == operation.ownerID
                && $0.localDate == day
                && $0.sourcePlannedMealID == meal.id
        }

        if existingCheck != nil || existingStructured != nil {
            if let existingStructured {
                try await deleteLoggedMeal(existingStructured, operation: operation)
                try requireCurrentAccountOperation(operation)
            }
            if let existingCheck {
                data.mealLogs.removeAll {
                    $0.id == existingCheck.id && $0.userID == operation.ownerID
                }
                await persistDelete(
                    table: "meal_logs",
                    id: existingCheck.id,
                    ownerID: operation.ownerID,
                    expectedAccountToken: operation.generation
                )
                try requireCurrentAccountOperation(operation)
            }
            return
        }

        let now = Date().ISO8601Format()
        let mealID = UUID()
        let entryID = UUID()
        let idempotencyKey = "simple-planned:\(operation.ownerID.uuidString.lowercased()):\(day):\(meal.id.uuidString.lowercased())"
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
            userID: operation.ownerID,
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
            userID: operation.ownerID,
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
            id: UUID(), userID: operation.ownerID, date: day,
            mealID: meal.id, checkedAt: now
        )

        data.loggedMeals.insert(localMeal, at: 0)
        try await refreshNudges(operation: operation)
        try requireCurrentAccountOperation(operation)
        data.loggedFoodEntries.insert(localEntry, at: 0)
        data.mealLogs.append(check)
        try await recalculateLocalStructuredDay(day, operation: operation)
        await persistUpsert(
            check,
            table: "meal_logs",
            onConflict: "user_id,date,meal_id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)

        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            try requireCurrentAccountOperation(operation)
            lastSyncAt = .now
            return
        }

        do {
            _ = try await service.logStructuredMeal(meal: request, entries: [entry])
            try requireCurrentAccountOperation(operation)
            try await refreshDashboard(expectedUserID: operation.ownerID)
            try requireCurrentAccountOperation(operation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try requireCurrentAccountOperation(operation)
            do {
                let payload = StructuredMealRPCPayload(pMeal: request, pEntries: [entry])
                try await offlineStore.enqueue(
                    .rpc("log_structured_meal", params: payload),
                    for: operation.ownerID
                )
                try requireCurrentAccountOperation(operation)
                let pendingCount = try? await offlineStore.pendingOperations(for: operation.ownerID).count
                try requireCurrentAccountOperation(operation)
                pendingSyncCount = pendingCount ?? pendingSyncCount + 1
                /* Saved offline and queued. Deliberately silent: this is the app
                   working, not an event, and pendingSyncCount already shows it.
                   Naming the backend on a user's screen helps nobody. */
            } catch {
                try requireCurrentAccountOperation(operation)
                alertMessage = error.localizedDescription
            }
        }
    }

    func toggleSupplement(
        _ supplement: Supplement,
        on date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard supplement.userID == operation.ownerID else { throw CancellationError() }
        let day = date.apexDateKey
        try await supplementMutationQueue.enqueue(requireCurrent: {
            try self.requireCurrentAccountOperation(operation)
        }) {
            let taken = !self.data.supplementLogs.contains {
                $0.userID == operation.ownerID && $0.date == day && $0.supplementID == supplement.id
            }
            try await self.persistSupplementTaken(supplement.id, taken: taken, day: day, operation: operation)
            try self.requireCurrentAccountOperation(operation)
            self.publishHydrationState()
        }.value
        try requireCurrentAccountOperation(operation)
        try await refreshNudges(operation: operation)
        try requireCurrentAccountOperation(operation)
    }

    /// "Mark group done" for one day: ticks what is still open, or clears the group once all of it is ticked.
    /// The day is read and written from the same value, the day the screen shows.
    func toggleSupplementGroup(
        _ supplements: [Supplement],
        on date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        let day = date.apexDateKey
        func taken(_ supplement: Supplement) -> Bool {
            data.supplementLogs.contains {
                $0.userID == operation.ownerID && $0.date == day && $0.supplementID == supplement.id
            }
        }
        let completed = !supplements.isEmpty && supplements.allSatisfy(taken)
        for supplement in supplements where completed || !taken(supplement) {
            try Task.checkCancellation()
            try await toggleSupplement(supplement, on: date, operation: operation)
        }
    }

    /// Explicit values make the immediate and durable Watch delivery paths
    /// idempotent. The shared queue also orders them with phone-origin taps.
    private func handleWatchSupplementMutation(_ mutation: WatchSupplementMutation) async {
        guard let operation = accountOperationLease(), operation.ownerID == mutation.ownerID,
              verifiedPersistenceOwnerID() == operation.ownerID,
              accountAccessAllowsPrivateWork(for: operation.ownerID) else { return }
        do {
            try await supplementMutationQueue.enqueue(requireCurrent: {
                try self.requireCurrentAccountOperation(operation)
            }) {
                guard self.accountAccessAllowsPrivateWork(for: operation.ownerID) else { throw CancellationError() }
                var journal = self.watchSupplementJournal(ownerID: operation.ownerID)
                let taken = self.data.supplementLogs.contains {
                    $0.userID == operation.ownerID && $0.date == mutation.day && $0.supplementID == mutation.itemID
                }
                journal.observePhoneValue(itemID: mutation.itemID, day: mutation.day, taken: taken)
                self.saveWatchSupplementJournal(journal, ownerID: operation.ownerID)
                let validDay = ISO8601DateFormatter.apexDateOnly.date(from: mutation.day)?.apexDateKey == mutation.day
                let exists = self.data.supplements.contains {
                    $0.userID == operation.ownerID && $0.id == mutation.itemID
                }
                if validDay, exists, journal.permits(mutation) {
                    try await self.persistSupplementTaken(
                        mutation.itemID, taken: mutation.taken, day: mutation.day,
                        operation: operation, watchMutation: mutation
                    )
                    try self.requireCurrentAccountOperation(operation)
                    journal = self.watchSupplementJournal(ownerID: operation.ownerID)
                }
                // Rejected conflicts are acknowledged too, so the phone value
                // replaces an obsolete optimistic tick instead of retrying it.
                journal.acknowledge(mutation)
                self.saveWatchSupplementJournal(journal, ownerID: operation.ownerID)
                self.publishHydrationState()
            }.value
            try requireCurrentAccountOperation(operation)
            try await refreshNudges(operation: operation)
        } catch {
            // The Watch retains its owner-scoped intent until a later durable
            // commit. Account transitions deliberately do not acknowledge it.
        }
    }

    private func persistSupplementTaken(
        _ itemID: UUID, taken: Bool, day: String, operation: AccountOperationLease,
        watchMutation: WatchSupplementMutation? = nil
    ) async throws {
        try requireCurrentAccountOperation(operation)
        let existing = data.supplementLogs.first {
            $0.userID == operation.ownerID && $0.date == day && $0.supplementID == itemID
        }
        guard taken != (existing != nil) else {
            if let watchMutation {
                var journal = watchSupplementJournal(ownerID: operation.ownerID)
                journal.recordWatchValue(watchMutation)
                saveWatchSupplementJournal(journal, ownerID: operation.ownerID)
            }
            return
        }
        let row = existing ?? SupplementLog(id: UUID(), userID: operation.ownerID, date: day,
            supplementID: itemID, checkedAt: Date().ISO8601Format())
        let remoteOperation: OfflineOperation?
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            remoteOperation = nil
        } else if taken {
            remoteOperation = try OfflineOperation.upsert(row, table: "supplement_logs",
                onConflict: "user_id,date,supplement_id")
        } else {
            remoteOperation = .delete(table: "supplement_logs", id: row.id)
        }
        let committed = try await CustomWorkoutLifecycle.persistMutation(
            snapshot: { (self.dashboardMutationRevision, self.data) },
            merge: { latest in
                var next = latest
                next.supplementLogs.removeAll {
                    $0.userID == operation.ownerID && $0.date == day && $0.supplementID == itemID
                }
                if taken { next.supplementLogs.append(row) }
                return next
            },
            requireCurrent: { try self.requireCurrentAccountOperation(operation) },
            saveDashboard: { proposed in
                try await self.offlineStore.saveDashboard(proposed, for: operation.ownerID)
            },
            enqueue: {
                if let remoteOperation {
                    try await self.offlineStore.enqueue(remoteOperation, for: operation.ownerID)
                }
            }
        )
        try requireCurrentAccountOperation(operation)
        data = committed
        // Commit the source revision in the same actor turn as the value. A
        // reconnect callback must not mistake this Watch write for a phone edit.
        var journal = watchSupplementJournal(ownerID: operation.ownerID)
        if let watchMutation {
            journal.recordWatchValue(watchMutation)
        } else {
            journal.recordPhoneEdit(itemID: itemID, day: day, taken: taken)
        }
        saveWatchSupplementJournal(journal, ownerID: operation.ownerID)
        if remoteOperation != nil {
            pendingSyncCount += 1
            Task { @MainActor [weak self] in
                guard let self, self.accountOperationIsCurrent(operation) else { return }
                await self.flushPendingChanges(for: operation.ownerID)
            }
        }
    }

    private func watchSupplementJournal(ownerID: UUID) -> WatchSupplementJournal {
        defaults.data(forKey: WatchSupplementKeys.journal(ownerID: ownerID))
            .flatMap { try? JSONDecoder().decode(WatchSupplementJournal.self, from: $0) }
            ?? WatchSupplementJournal()
    }

    private func saveWatchSupplementJournal(_ journal: WatchSupplementJournal, ownerID: UUID) {
        guard let encoded = try? JSONEncoder().encode(journal) else { return }
        defaults.set(encoded, forKey: WatchSupplementKeys.journal(ownerID: ownerID))
    }

    private func makeWatchSupplementSnapshot(ownerID: UUID, day: String) -> WatchSupplementSnapshot {
        let items = activeSupplements.map { WatchSupplementItem(id: $0.id, name: $0.name, dose: $0.dose) }
        let checkedIDs = Set(data.supplementLogs.filter {
            $0.userID == ownerID && $0.date == day
        }.map(\.supplementID))
        var journal = watchSupplementJournal(ownerID: ownerID)
        for item in items {
            journal.observePhoneValue(itemID: item.id, day: day, taken: checkedIDs.contains(item.id))
        }
        let revision = journal.nextSnapshotRevision()
        saveWatchSupplementJournal(journal, ownerID: ownerID)
        return WatchSupplementSnapshot(ownerID: ownerID, day: day, revision: revision,
            items: items, checkedIDs: checkedIDs, acknowledgedIDs: Set(journal.acknowledgedIDs))
    }

    /// A remote refresh cannot erase queued checks or a check made while its
    /// request was in flight. Only supplement rows are merged into its result.
    private func preservingPendingSupplementLogs(
        in incoming: DashboardData, ownerID: UUID, startedAtRevision: UInt64,
        pendingAtStart: [OfflineOperation]
    ) async -> DashboardData {
        let token = accountGeneration.token
        let pendingNow = try? await offlineStore.pendingOperations(for: ownerID)
        guard accountGeneration.accepts(token),
              authenticatedOwnerID == ownerID || verifiedPersistenceOwnerID(ownerID) == ownerID else { return incoming }
        var next = incoming
        guard let pendingNow else {
            if verifiedPersistenceOwnerID(ownerID) == ownerID {
                next.supplementLogs = data.supplementLogs.filter { $0.userID == ownerID }
            }
            return next
        }
        let initialIDs = Set(pendingAtStart.map(\.id))
        let operations = pendingAtStart + pendingNow.filter { !initialIDs.contains($0.id) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for pending in operations where pending.table == "supplement_logs" {
            switch pending.kind {
            case .upsert:
                guard let payload = pending.payload,
                      let row = try? decoder.decode(SupplementLog.self, from: payload),
                      row.userID == ownerID else { continue }
                next.supplementLogs.removeAll {
                    $0.userID == ownerID && $0.date == row.date && $0.supplementID == row.supplementID
                }
                next.supplementLogs.append(row)
            case .delete:
                next.supplementLogs.removeAll { $0.userID == ownerID && $0.id == pending.recordID }
            case .rpc: break
            }
        }
        let changed = Set(watchSupplementJournal(ownerID: ownerID).localEdits
            .filter { $0.value > startedAtRevision }.keys)
        next.supplementLogs.removeAll {
            $0.userID == ownerID && changed.contains(WatchSupplementJournal.scope(itemID: $0.supplementID, day: $0.date))
        }
        next.supplementLogs.append(contentsOf: data.supplementLogs.filter {
            $0.userID == ownerID && changed.contains(WatchSupplementJournal.scope(itemID: $0.supplementID, day: $0.date))
        })
        return next
    }

    /// Adds a supplement to the plan from wherever the user happens to be.
    ///
    /// Previously the stack could only be checked off, never changed, so
    /// adding one meant leaving the thing you were doing and going to find the
    /// full editor. Sorting after the current last item keeps it in the group
    /// the user picked rather than jumping to the top.
    func addSupplement(
        name: String,
        dose: String,
        groupLabel: String,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let row = Supplement(
            id: UUID(),
            userID: operation.ownerID,
            name: trimmedName,
            dose: dose.trimmingCharacters(in: .whitespacesAndNewlines),
            timing: "anytime",
            clockTime: nil,
            offsetMinutes: nil,
            groupLabel: groupLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            trainingDaysOnly: false,
            sortOrder: (data.supplements
                .filter { $0.userID == operation.ownerID }
                .map(\.sortOrder).max() ?? 0) + 1
        )
        data.supplements.append(row)
        await persistUpsert(
            row,
            table: "supplements",
            onConflict: "id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        publishHydrationState()
    }

    /// Retires a supplement from the plan, keeping what it recorded.
    ///
    /// supplement_logs cascades on delete, so removing the row would take
    /// every past check-off with it. For somebody paying for the app that is
    /// their data disappearing because they tidied a list, so the row stays
    /// and simply stops appearing in the plan.
    func archiveSupplement(
        _ supplement: Supplement,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard supplement.userID == operation.ownerID,
              let index = data.supplements.firstIndex(where: {
                  $0.id == supplement.id && $0.userID == operation.ownerID
              }) else { throw CancellationError() }
        data.supplements[index].archived = true
        let archived = data.supplements[index]
        await persistUpsert(
            archived,
            table: "supplements",
            onConflict: "id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        publishHydrationState()
        try await refreshNudges(operation: operation)
    }

    /// Puts an archived supplement back into the plan.
    func restoreSupplement(
        _ supplement: Supplement,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard supplement.userID == operation.ownerID,
              let index = data.supplements.firstIndex(where: {
                  $0.id == supplement.id && $0.userID == operation.ownerID
              }) else { throw CancellationError() }
        data.supplements[index].archived = false
        let restored = data.supplements[index]
        await persistUpsert(
            restored,
            table: "supplements",
            onConflict: "id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        publishHydrationState()
    }

    /// Re-evaluate today's reminders from live data.
    ///
    /// Called on open and after anything that could change the answer, because
    /// a local notification is scheduled ahead of time and would otherwise fire
    /// on a stale reading. Being told you are short on protein an hour after
    /// hitting the target is the failure people actually notice.
    func refreshNudges(operation: AccountOperationLease) async throws {
        if isDeveloperSandbox { return }
        try requireCurrentAccountOperation(operation)
        guard profile?.userID == operation.ownerID else { throw CancellationError() }
        NudgeCenter.shared.activate(ownerID: operation.ownerID)
        await NudgeCenter.shared.refresh(
            DailyNudges.nudges(ownerID: operation.ownerID, data: data, today: Date().apexDateKey)
        )
        try requireCurrentAccountOperation(operation)
    }

    func refreshNudges() async {
        if isDeveloperSandbox { return }
        guard let operation = accountOperationLease() else { return }
        try? await refreshNudges(operation: operation)
    }

    /// What the plan should show: everything not retired.
    var activeSupplements: [Supplement] {
        guard let ownerID = verifiedPersistenceOwnerID() else { return [] }
        return data.supplements
            .filter { $0.userID == ownerID && !$0.archived }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func updateDailyLog(
        _ row: DailyLog,
        ownerID: UUID? = nil,
        expectedAccountToken: UInt64? = nil
    ) async {
        if let expectedAccountToken {
            guard accountGeneration.accepts(expectedAccountToken),
                  verifiedPersistenceOwnerID(ownerID) == ownerID,
                  row.userID == ownerID else { return }
        }
        if let index = data.dailyLogs.firstIndex(where: { $0.id == row.id }) {
            data.dailyLogs[index] = row
        } else {
            data.dailyLogs.append(row)
        }
        await persistUpsert(
            row,
            table: "daily_logs",
            onConflict: "user_id,date",
            ownerID: ownerID,
            expectedAccountToken: expectedAccountToken
        )
    }

    /// A step on the Settings weight is today's weigh-in as well as the profile's weight, so it
    /// is the newest weight on record and every target follows it.
    func stepBodyweight(by delta: Double, operation: AccountOperationLease) async throws {
        try requireCurrentAccountOperation(operation)
        guard let recorded = data.weighedProfile()?.weightKG, recorded.isFinite else { throw CancellationError() }
        /* Stepped from the weight on record now, not the one on screen when the tap began, and
           kept to what the targets accept. The weigh-in goes first: it is on the day before
           this first waits on a save, so a tap that follows at once steps from it. */
        let weightKG = min(300, max(30, recorded + delta))
        try await saveMorningWeight(weightKG, on: .now, operation: operation)
        // Saves can finish out of order, so the profile takes whichever weight is on record by now.
        let newest = data.weighedProfile()?.weightKG ?? weightKG
        try await updateProfile({ $0.weightKG = newest }, operation: operation)
    }

    func saveMorningWeight(
        _ weightKG: Double,
        on date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard weightKG.isFinite,
              (25...350).contains(weightKG) else { return }
        let day = date.apexDateKey
        let existing = data.dailyLogs.first {
            $0.userID == operation.ownerID && $0.date == day
        }
        let activityMode = data.activityLogs.contains {
            $0.userID == operation.ownerID && $0.date == day
        } ? "precise" : "quick"
        let row = MorningCheckLogic.applyingWeight(
            weightKG,
            to: existing,
            userID: operation.ownerID,
            date: day,
            activityMode: activityMode
        )
        await updateDailyLog(
            row,
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    /// Water naturally present in foods logged for the selected day. This is
    /// deliberately kept separate from `DailyLog.waterL`, which represents
    /// drinks and Apple Health dietary-water samples.
    func foodHydrationLiters(on date: Date) -> Double {
        foodHydrationML(on: date) / 1_000
    }

    /// The same water in millilitres, summed portion by portion as the score engine sums it.
    /// Whole-millilitre figures are rounded from this, never from litres.
    func foodHydrationML(on date: Date) -> Double {
        let day = date.apexDateKey
        let mealIDs = Set(data.loggedMeals.lazy.filter { $0.localDate == day }.map(\.id))
        guard !mealIDs.isEmpty else { return 0 }
        return data.loggedFoodEntries.lazy
            .filter { mealIDs.contains($0.mealID) }
            .reduce(0.0) { $0 + (FoodHydration.loggedWater($1) ?? 0) }
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

    /// The day's water the home gauge shows, from the calculation the score engine uses.
    func hydrationIntakeML(on date: Date) -> Int {
        hydrationResolution(on: date).intakeML(loggedFoodML: foodHydrationML(on: date))
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

    func hydrationTargetResolution(on date: Date, now: Date = .now) -> HydrationTargetResolution {
        let day = date.apexDateKey
        // A past day keeps the goal it had, the one the Avatar grades it against.
        let history = day < now.apexDateKey && data.settings?.userID == data.profile?.userID
            ? data.settings?.addons[ScoreGoalHistory.addonKey] : nil
        return DailyWaterTargets(data: data, coachManaged: coachContext.capabilities.sponsoredClient && !coachClientPolicy.canCreateCustomWorkouts,
                          followsCoach: coachClientPolicy.canFollowCoachPlan, includeCustom: coachClientPolicy.canCreateCustomWorkouts)
            .resolve(day: day, now: now, goals: ScoreGoalHistory(stored: history).earlierGoals(on: day))
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
        clientKey: String? = nil,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard amountML > 0, amountML <= 10_000 else { return }
        let ownerID = operation.ownerID
        let day = date.apexDateKey
        try await materializeLegacyHydrationIfNeeded(
            ownerID: ownerID,
            date: date,
            operation: operation
        )
        try requireCurrentAccountOperation(operation)
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
            ownerID: ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)

        if source == .iPhone,
           healthImportIsEnabled(operation: operation),
           occurred <= Date().addingTimeInterval(60) {
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
                try requireCurrentAccountOperation(operation)
                event.updatedAt = Date().ISO8601Format()
                upsertHydrationEventLocally(event)
                await persistUpsert(
                    event,
                    table: "hydration_events",
                    onConflict: "user_id,client_idempotency_key",
                    ownerID: ownerID,
                    expectedAccountToken: operation.generation,
                    surfacePermanentFailure: false
                )
                try requireCurrentAccountOperation(operation)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try requireCurrentAccountOperation(operation)
                HealthKitManager.shared.message = error.localizedDescription
            }
        }
        try await mirrorHydrationAggregate(ownerID: ownerID, on: date, operation: operation)
        try requireCurrentAccountOperation(operation)
        publishHydrationState()
    }

    func logHydration(
        preset: HydrationPreset,
        on date: Date = .now,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard preset.userID == operation.ownerID else { throw CancellationError() }
        try await logHydration(
            amountML: preset.amountML,
            kind: preset.kind.eventKind,
            paletteToken: preset.paletteToken,
            iconToken: preset.iconToken,
            on: date,
            operation: operation
        )
        try requireCurrentAccountOperation(operation)
    }

    func deleteHydrationEvent(
        _ event: HydrationEvent,
        on date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard event.userID == operation.ownerID,
              event.source != .healthKitExternal, event.source != .food else {
            throw CancellationError()
        }
        await removeHydrationEvent(event, operation: operation)
        try requireCurrentAccountOperation(operation)
        if event.source == .iPhone, healthImportIsEnabled(operation: operation) {
            try? await HealthKitManager.shared.deleteWater(eventID: event.id, date: date)
            try requireCurrentAccountOperation(operation)
        }
        publishHydrationState()
    }

    func saveHydrationPreset(
        _ preset: HydrationPreset,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard preset.userID == operation.ownerID else { throw CancellationError() }
        var rows = data.hydrationPresets ?? []
        rows.removeAll { $0.id == preset.id && $0.userID == operation.ownerID }
        rows.append(preset)
        data.hydrationPresets = rows
        await persistUpsert(
            preset,
            table: "hydration_presets",
            onConflict: "user_id,id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        publishHydrationState()
    }

    func deleteHydrationPreset(
        _ preset: HydrationPreset,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard preset.userID == operation.ownerID else { throw CancellationError() }
        data.hydrationPresets?.removeAll {
            $0.id == preset.id && $0.userID == operation.ownerID
        }
        await persistDelete(
            table: "hydration_presets",
            id: preset.id,
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        publishHydrationState()
    }

    func saveHydrationPreferences(
        _ preferences: HydrationAccountPreferences,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard preferences.userID == operation.ownerID else { throw CancellationError() }
        data.hydrationPreferences = preferences
        await persistUpsert(
            preferences,
            table: "hydration_preferences",
            onConflict: "user_id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        publishHydrationState()
    }

    func setActivityLevel(
        _ level: ActivityLevel,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard var profile, profile.userID == operation.ownerID else { throw CancellationError() }
        profile.activityLevel = level
        profile.updatedAt = Date().ISO8601Format()
        data.profile = profile
        await persistUpsert(
            profile,
            table: "profile",
            onConflict: "user_id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func setGoal(
        _ goal: Goal,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard var profile, profile.userID == operation.ownerID else { throw CancellationError() }
        profile.goal = goal
        profile.updatedAt = Date().ISO8601Format()
        data.profile = profile
        await persistUpsert(
            profile,
            table: "profile",
            onConflict: "user_id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func updateSettings(
        _ transform: (inout UserSettings) -> Void,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let profile, profile.userID == operation.ownerID,
              var settings = data.settings,
              settings.userID == operation.ownerID else { throw CancellationError() }
        settings = settings.rebound(to: operation.ownerID)
        transform(&settings)
        data.settings = settings
        await persistUpsert(
            settings,
            table: "settings",
            onConflict: "user_id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
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
    func adjustWater(
        deltaLiters: Double,
        on date: Date,
        operation: AccountOperationLease
    ) async throws -> Double {
        try requireCurrentAccountOperation(operation)
        let task = hydrationMutationQueue.enqueue { [weak self] in
            guard let self else { return 0 }
            return await self.performWaterAdjustment(
                deltaLiters: deltaLiters,
                on: date,
                operation: operation
            )
        }
        let value = await task.value
        try requireCurrentAccountOperation(operation)
        return value
    }

    private func performWaterAdjustment(
        deltaLiters: Double,
        on date: Date,
        operation: AccountOperationLease
    ) async -> Double {
        guard accountOperationIsCurrent(operation) else { return 0 }
        guard deltaLiters.isFinite, deltaLiters != 0 else {
            return Double(hydrationResolution(ownerID: operation.ownerID, on: date).drinkML) / 1_000
        }
        if deltaLiters > 0 {
            try? await logHydration(
                amountML: Int((deltaLiters * 1_000).rounded()),
                on: date,
                operation: operation
            )
        } else {
            try? await reduceHydration(
                byML: Int((-deltaLiters * 1_000).rounded()),
                on: date,
                operation: operation
            )
        }
        guard accountOperationIsCurrent(operation) else { return 0 }
        return Double(hydrationResolution(ownerID: operation.ownerID, on: date).drinkML) / 1_000
    }

    func setWaterTotal(
        _ liters: Double,
        on date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        let current = Double(
            hydrationResolution(ownerID: operation.ownerID, on: date).drinkML
        ) / 1_000
        _ = try await adjustWater(
            deltaLiters: liters - current,
            on: date,
            operation: operation
        )
        try requireCurrentAccountOperation(operation)
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
                    expectedAccountToken: accountToken,
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
                expectedAccountToken: accountToken,
                surfacePermanentFailure: false
            )
            guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        }
    }

    private func materializeLegacyHydrationIfNeeded(
        ownerID: UUID,
        date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard ownerID == operation.ownerID else { throw CancellationError() }
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
            expectedAccountToken: operation.generation,
            surfacePermanentFailure: false
        )
        try requireCurrentAccountOperation(operation)
        publishHydrationState()
    }

    private func materializeLegacyHydrationIfNeeded(ownerID: UUID, date: Date) async {
        guard let operation = accountOperationLease(), operation.ownerID == ownerID else { return }
        try? await materializeLegacyHydrationIfNeeded(
            ownerID: ownerID,
            date: date,
            operation: operation
        )
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

    private func mirrorHydrationAggregate(
        ownerID: UUID,
        on date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard ownerID == operation.ownerID else { throw CancellationError() }
        let day = date.apexDateKey
        // The mirror follows the ledger alone. Falling back to its own old value would keep a removed drink.
        let resolved = HydrationLedger.resolve(
            ownerID: ownerID,
            date: day,
            events: data.hydrationEvents ?? [],
            legacyDrinkLiters: 0
        )
        let liters = Double(resolved.drinkML) / 1_000
        let existing = data.dailyLogs.first { $0.userID == ownerID && $0.date == day }
        guard abs((existing?.waterL ?? 0) - liters) > 0.000_5 || existing == nil else { return }
        var row = existing ?? DailyLog(
            id: APEXStableID.scopedUUID(namespace: "daily-log", date: day, userID: ownerID),
            userID: ownerID, date: day,
            kcal: nil, proteinG: nil, fatG: nil, carbsG: nil, waterL: 0,
            estimatedTDEE: nil, computedPAL: nil,
            activityMode: data.activityLogs.contains {
                $0.userID == ownerID && $0.date == day
            } ? "precise" : "quick",
            weightKG: nil
        )
        row.waterL = liters
        await updateDailyLog(
            row,
            ownerID: ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    private func mirrorHydrationAggregate(ownerID: UUID, on date: Date) async {
        guard let operation = accountOperationLease(), operation.ownerID == ownerID else { return }
        try? await mirrorHydrationAggregate(ownerID: ownerID, on: date, operation: operation)
    }

    /// Takes an event off the ledger. The stored day total follows before the server is told,
    /// so a drink added while the delete is in flight does not find the old total and revive this one.
    private func removeHydrationEvent(_ event: HydrationEvent, operation: AccountOperationLease) async {
        data.hydrationEvents?.removeAll { $0.id == event.id && $0.userID == operation.ownerID }
        if let date = ISO8601DateFormatter.apexDateOnly.date(from: event.localDate) {
            try? await mirrorHydrationAggregate(ownerID: operation.ownerID, on: date, operation: operation)
        }
        await persistDelete(
            table: "hydration_events",
            id: event.id,
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
    }

    private func reduceHydration(
        byML amountML: Int,
        on date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard amountML > 0 else { return }
        let ownerID = operation.ownerID
        let day = date.apexDateKey
        try await materializeLegacyHydrationIfNeeded(
            ownerID: ownerID,
            date: date,
            operation: operation
        )
        try requireCurrentAccountOperation(operation)
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
            activityMode: data.activityLogs.contains {
                $0.userID == ownerID && $0.date == day
            } ? "precise" : "quick",
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
            await persistDelete(
                table: "hydration_events",
                id: event.id,
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
            if event.source == .iPhone, healthImportIsEnabled(operation: operation) {
                try? await HealthKitManager.shared.deleteWater(eventID: event.id, date: date)
                try requireCurrentAccountOperation(operation)
            }
        }

        for pair in plan.replacements {
            var replacement = pair.replacement
            if pair.original.source == .iPhone,
               healthImportIsEnabled(operation: operation) {
                try? await HealthKitManager.shared.deleteWater(eventID: pair.original.id, date: date)
                try requireCurrentAccountOperation(operation)
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
                        try requireCurrentAccountOperation(operation)
                        replacement.updatedAt = Date().ISO8601Format()
                        upsertHydrationEventLocally(replacement)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        try requireCurrentAccountOperation(operation)
                        HealthKitManager.shared.message = error.localizedDescription
                    }
                }
            }
            await persistUpsert(
                replacement,
                table: "hydration_events",
                onConflict: "user_id,client_idempotency_key",
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }

        await persistUpsert(
            aggregateRow,
            table: "daily_logs",
            onConflict: "user_id,date",
            ownerID: ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        publishHydrationState()
    }

    private func syncFoodHydrationEvent(
        on date: Date,
        ownerID: UUID,
        operation: AccountOperationLease? = nil
    ) async {
        let accountToken = operation?.generation ?? accountGeneration.token
        if let operation {
            guard operation.ownerID == ownerID,
                  accountOperationIsCurrent(operation) else { return }
        }
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        let day = date.apexDateKey
        let key = "food:\(day)"
        let amountML = Int(foodHydrationML(on: date).rounded())
        let existing = (data.hydrationEvents ?? []).first {
            $0.userID == ownerID && $0.clientIdempotencyKey == key
        }
        guard amountML > 0 else {
            if let existing {
                data.hydrationEvents?.removeAll { $0.id == existing.id }
                await persistDelete(
                    table: "hydration_events",
                    id: existing.id,
                    ownerID: ownerID,
                    expectedAccountToken: operation?.generation
                )
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
            expectedAccountToken: operation?.generation,
            surfacePermanentFailure: false
        )
        guard hydrationOperationIsCurrent(ownerID: ownerID, token: accountToken) else { return }
        publishHydrationState()
    }

    /// The day's food water goes to Health once its food event holds it. The Watch counts food water
    /// from that event alone, and a meal logged on the website arrives without one.
    func mirrorFoodWaterToHealth(on date: Date, operation: AccountOperationLease) async {
        await syncFoodHydrationEvent(on: date, ownerID: operation.ownerID, operation: operation)
        guard healthImportIsEnabled(operation: operation),
              HealthKitManager.shared.waterWriteState == .authorized else { return }
        try? await HealthKitManager.shared.syncFoodWater(
            liters: foodHydrationLiters(on: date),
            on: date,
            accountID: operation.ownerID
        )
    }

    private func reconcileHealthHydration(
        _ snapshot: HealthSnapshot,
        operation: AccountOperationLease
    ) async {
        guard snapshot.importableDietaryWaterL != nil else { return }
        let ownerID = operation.ownerID
        guard accountOperationIsCurrent(operation),
              let date = ISO8601DateFormatter.apexDateOnly.date(from: snapshot.date) else { return }
        do {
            try await materializeLegacyHydrationIfNeeded(
                ownerID: ownerID,
                date: date,
                operation: operation
            )
        } catch {
            return
        }
        guard accountOperationIsCurrent(operation) else { return }
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
            await removeHydrationEvent(event, operation: operation)
            guard accountOperationIsCurrent(operation) else { return }
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
                expectedAccountToken: operation.generation,
                surfacePermanentFailure: false
            )
            guard accountOperationIsCurrent(operation) else { return }
        }
        do {
            try await mirrorHydrationAggregate(
                ownerID: ownerID,
                on: date,
                operation: operation
            )
        } catch {
            return
        }
        guard accountOperationIsCurrent(operation) else { return }
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
        if isDeveloperSandbox { return }
        guard let ownerID = verifiedPersistenceOwnerID() else { return }
        // Access recovery retains the dashboard for this account. A late
        // activation/request must keep the Watch disconnected until access is
        // granted again, including through the validated offline entitlement.
        guard accountAccessAllowsPrivateWork(for: ownerID) else {
            hydrationConnectivity?.publishDisconnected()
            return
        }
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
            revision: HydrationComplicationRefreshPolicy.revision(),
            acknowledgedDeleteIDs: acknowledgedHydrationDeleteIDs(ownerID: ownerID)
        )
        hydrationConnectivity?.publish(snapshot, supplements: makeWatchSupplementSnapshot(ownerID: ownerID, day: day))
    }

    private func beginHydrationMutation(_ mutation: HydrationCompanionMutation) -> Bool {
        let key = hydrationMutationProcessedKey(ownerID: mutation.ownerID)
        let processed = defaults.stringArray(forKey: key) ?? []
        let mutationID = mutation.id.uuidString.lowercased()
        guard !processed.contains(mutationID), !hydrationMutationsInFlight.contains(mutation.id) else {
            return false
        }
        hydrationMutationsInFlight.insert(mutation.id)
        return true
    }

    private func finishHydrationMutation(
        _ mutation: HydrationCompanionMutation,
        markProcessed: Bool
    ) {
        hydrationMutationsInFlight.remove(mutation.id)
        guard markProcessed else { return }
        let key = hydrationMutationProcessedKey(ownerID: mutation.ownerID)
        var processed = defaults.stringArray(forKey: key) ?? []
        let mutationID = mutation.id.uuidString.lowercased()
        if !processed.contains(mutationID) {
            processed.append(mutationID)
            defaults.set(Array(processed.suffix(512)), forKey: key)
        }
        removeHydrationMutationRetry(mutation)
    }

    private func hydrationMutationProcessedKey(ownerID: UUID) -> String {
        "apex.watch.hydration.processed.\(ownerID.uuidString.lowercased())"
    }

    private func hydrationMutationWasProcessed(_ mutation: HydrationCompanionMutation) -> Bool {
        let values = defaults.stringArray(
            forKey: hydrationMutationProcessedKey(ownerID: mutation.ownerID)
        ) ?? []
        return values.contains(mutation.id.uuidString.lowercased())
    }

    private func hydrationMutationRetryKey(ownerID: UUID) -> String {
        "apex.watch.hydration.pending-retry.\(ownerID.uuidString.lowercased())"
    }

    private func pendingHydrationMutationRetries(
        ownerID: UUID
    ) -> [PendingHydrationMutationRetry] {
        guard let encoded = defaults.data(forKey: hydrationMutationRetryKey(ownerID: ownerID)),
              let values = try? JSONDecoder().decode(
                  [PendingHydrationMutationRetry].self,
                  from: encoded
              ) else { return [] }
        return values
    }

    private func saveHydrationMutationRetries(
        _ values: [PendingHydrationMutationRetry],
        ownerID: UUID
    ) {
        let key = hydrationMutationRetryKey(ownerID: ownerID)
        guard !values.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let encoded = try? JSONEncoder().encode(Array(values.suffix(64))) else { return }
        defaults.set(encoded, forKey: key)
    }

    private func enqueueHydrationMutationRetry(_ mutation: HydrationCompanionMutation) {
        guard !hydrationMutationWasProcessed(mutation) else { return }
        var values = pendingHydrationMutationRetries(ownerID: mutation.ownerID)
        guard !values.contains(where: { $0.mutation.id == mutation.id }) else { return }
        values.append(PendingHydrationMutationRetry(mutation: mutation, attempts: 0))
        saveHydrationMutationRetries(values, ownerID: mutation.ownerID)
    }

    private func removeHydrationMutationRetry(_ mutation: HydrationCompanionMutation) {
        var values = pendingHydrationMutationRetries(ownerID: mutation.ownerID)
        values.removeAll { $0.mutation.id == mutation.id }
        saveHydrationMutationRetries(values, ownerID: mutation.ownerID)
    }

    private func acknowledgedHydrationDeleteIDs(ownerID: UUID) -> [UUID] {
        (defaults.stringArray(forKey: hydrationDeleteAcknowledgementKey(ownerID: ownerID)) ?? [])
            .compactMap(UUID.init(uuidString:))
    }

    private func recordHydrationDeleteAcknowledgement(eventID: UUID, ownerID: UUID) {
        let key = hydrationDeleteAcknowledgementKey(ownerID: ownerID)
        var acknowledged = defaults.stringArray(forKey: key) ?? []
        let value = eventID.uuidString.lowercased()
        guard !acknowledged.contains(value) else { return }
        acknowledged.append(value)
        defaults.set(Array(acknowledged.suffix(512)), forKey: key)
    }

    private func hydrationDeleteAcknowledgementKey(ownerID: UUID) -> String {
        "apex.watch.hydration.acknowledged-deletes.\(ownerID.uuidString.lowercased())"
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
        guard let operation = accountOperationLease() else {
            enqueueHydrationMutationRetry(mutation)
            return
        }
        guard accountAccessAllowsPrivateWork(for: operation.ownerID) else { return }
        guard mutation.ownerID == operation.ownerID else {
            enqueueHydrationMutationRetry(mutation)
            return
        }
        guard mutation.belongs(to: operation.ownerID) else {
            if beginHydrationMutation(mutation) {
                finishHydrationMutation(mutation, markProcessed: true)
            }
            return
        }
        await handleHydrationMutation(mutation, operation: operation)
    }

    private func handleHydrationMutation(
        _ mutation: HydrationCompanionMutation,
        operation: AccountOperationLease
    ) async {
        guard !Task.isCancelled,
              accountAccessAllowsPrivateWork(for: operation.ownerID),
              mutation.belongs(to: operation.ownerID),
              accountOperationIsCurrent(operation) else {
            enqueueHydrationMutationRetry(mutation)
            return
        }
        guard beginHydrationMutation(mutation) else { return }
        var markProcessed = false
        var retryIfInterrupted = true
        defer {
            finishHydrationMutation(mutation, markProcessed: markProcessed)
            if retryIfInterrupted { enqueueHydrationMutationRetry(mutation) }
        }
        let ownerID = operation.ownerID
        switch mutation.action {
        case .upsertEvent:
            guard let event = mutation.event,
                  HydrationMutationOrdering.accepts(
                      event: event,
                      afterTombstoneRevision: hydrationTombstoneRevision(
                          eventID: event.healthKitSampleID ?? event.id,
                          ownerID: ownerID
                      )
                  ) else {
                markProcessed = true
                retryIfInterrupted = false
                return
            }
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
                    expectedAccountToken: operation.generation,
                    surfacePermanentFailure: false
                )
                guard !Task.isCancelled, accountOperationIsCurrent(operation) else { return }
            }
            if let date = ISO8601DateFormatter.apexDateOnly.date(from: event.localDate) {
                do {
                    try await mirrorHydrationAggregate(
                        ownerID: ownerID,
                        on: date,
                        operation: operation
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled, accountOperationIsCurrent(operation) else { return }
            }
        case .deleteEvent:
            guard let eventID = mutation.eventID else {
                markProcessed = true
                retryIfInterrupted = false
                return
            }
            recordHydrationTombstone(eventID: eventID, ownerID: ownerID, revision: mutation.createdAt)
            if let event = (data.hydrationEvents ?? []).first(where: {
                $0.userID == ownerID && ($0.id == eventID || $0.healthKitSampleID == eventID)
            }), !HydrationMutationOrdering.accepts(
                event: event,
                afterTombstoneRevision: mutation.createdAt
            ) {
                await removeHydrationEvent(event, operation: operation)
                guard !Task.isCancelled, accountOperationIsCurrent(operation) else { return }
            }
            guard !Task.isCancelled, accountOperationIsCurrent(operation) else { return }
            recordHydrationDeleteAcknowledgement(eventID: eventID, ownerID: ownerID)
        case .updatePreferences:
            guard let preferences = mutation.preferences,
                  HydrationMutationOrdering.acceptsPreference(
                      incomingRevision: mutation.createdAt,
                      currentRevision: data.hydrationPreferences?.updatedAt
                  ) else {
                markProcessed = true
                retryIfInterrupted = false
                return
            }
            do {
                try await saveHydrationPreferences(
                    preferences.accountRow(ownerID: ownerID, existing: data.hydrationPreferences),
                    operation: operation
                )
            } catch {
                return
            }
            guard !Task.isCancelled, accountOperationIsCurrent(operation) else { return }
        }
        guard !Task.isCancelled, accountOperationIsCurrent(operation) else { return }
        publishHydrationState()
        markProcessed = true
        retryIfInterrupted = false
    }

    func applyHealthSnapshot(
        _ snapshot: HealthSnapshot,
        operation: AccountOperationLease
    ) async {
        guard accountAccessAllowsPrivateWork(for: operation.ownerID),
              healthImportIsEnabled(operation: operation),
              profile?.userID == operation.ownerID else { return }
        let ownerID = operation.ownerID
        if let resolvedDate = ISO8601DateFormatter.apexDateOnly.date(from: snapshot.date) {
            await mirrorFoodWaterToHealth(on: resolvedDate, operation: operation)
            guard accountOperationIsCurrent(operation) else { return }
        }
        for metric in snapshot.metricRows(ownerID: ownerID, existing: data.healthMetrics) {
            data.healthMetrics.removeAll { $0.id == metric.id && $0.userID == ownerID }
            data.healthMetrics.append(metric)
            await persistUpsert(
                metric,
                table: "health_metrics",
                onConflict: "user_id,date",
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            guard accountOperationIsCurrent(operation) else { return }
        }

        await reconcileHealthHydration(snapshot, operation: operation)
        guard accountOperationIsCurrent(operation) else { return }
        if let anchorData = snapshot.hydrationDeletionAnchorData {
            HealthKitManager.shared.commitDietaryWaterAnchor(anchorData, ownerID: ownerID)
        }

        if snapshot.steps != nil || snapshot.activeEnergyKcal != nil || snapshot.exerciseMinutes != nil {
            let history = WearableActivityRecord.history(
                from: data.settings?.addons["watch_activity_history"]
            )
            if let wearable = WearableActivityRecord.mergingHealthImport(
                date: snapshot.date,
                existing: history.last { $0.date == snapshot.date },
                steps: snapshot.steps,
                activeEnergyKcal: snapshot.activeEnergyKcal,
                exerciseMinutes: snapshot.exerciseMinutes,
                updatedAt: Date().ISO8601Format()
            ) {
                await saveWearableActivity(wearable, importedFromHealth: true, operation: operation)
                guard accountOperationIsCurrent(operation) else { return }
            }
        }

        if snapshot.sleepDurationHours != nil || snapshot.heartRateVariabilityMS != nil {
            guard accountOperationIsCurrent(operation),
                  var settings = data.settings,
                  settings.userID == ownerID else { return }
            let updatedAt = Date().ISO8601Format()
            let read: ServerSettingsGate.HealthRead = { addons in
                addons = RecoveryAssessment.addons(
                    addons, storingHealthRead: snapshot.date, sleepHours: snapshot.sleepDurationHours,
                    heartRateVariabilityMS: snapshot.heartRateVariabilityMS,
                    restingHeartRate: snapshot.restingHeartRate, updatedAt: updatedAt
                )
            }
            read(&settings.addons)
            data.settings = settings
            // The screen already shows the read. Sending the whole row waits for the server's copy.
            if serverSettings.sends(read, for: ownerID) {
                await persistUpsert(
                    settings,
                    table: "settings",
                    onConflict: "user_id",
                    ownerID: ownerID,
                    expectedAccountToken: operation.generation
                )
                guard accountOperationIsCurrent(operation) else { return }
            }
        }

        await importHealthWorkoutChanges(operation: operation)
    }

    /// Stores a day's wearable record. It never changes the chosen activity level: Apple Health
    /// suggests one, and a hand-picked level stays until the person changes it.
    func saveWearableActivity(
        _ record: WearableActivityRecord,
        importedFromHealth: Bool = false,
        operation: AccountOperationLease
    ) async {
        guard accountOperationIsCurrent(operation),
              var settings = data.settings,
              settings.userID == operation.ownerID,
              profile?.userID == operation.ownerID else { return }
        let read: ServerSettingsGate.HealthRead = { addons in
            var history = WearableActivityRecord.history(from: addons["watch_activity_history"])
            history.removeAll { $0.date == record.date }
            history.append(record)
            history.sort { $0.date < $1.date }
            addons["watch_activity_history"] = .array(history.suffix(730).map(\.jsonValue))
        }
        read(&settings.addons)
        data.settings = settings
        // A record the person typed is sent like any other save. An import waits for the server's copy.
        if !importedFromHealth || serverSettings.sends(read, for: operation.ownerID) {
            await persistUpsert(
                settings,
                table: "settings",
                onConflict: "user_id",
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            guard accountOperationIsCurrent(operation) else { return }
        }
        if record.date == Date().apexDateKey { publishHydrationState() }
    }

    /// The person's own choice to take the level a day's activity suggests.
    func useSuggestedActivityLevel(on day: String, operation: AccountOperationLease) async {
        guard accountOperationIsCurrent(operation),
              let profile,
              profile.userID == operation.ownerID,
              WearableActivityEngine.shouldAutomaticallyApplyMode(
                profile: profile,
                requested: true,
                hasActivityLogs: data.activityLogs.contains {
                    $0.userID == operation.ownerID && $0.date == day
                }
              ) else { return }
        let suggested = NutritionRecordedActivity.resolve(
            profile: data.weighedProfile(),
            settings: data.settings,
            logs: data.activityLogs,
            date: day
        ).level
        try? await setActivityLevel(suggested, operation: operation)
    }

    func addActivity(
        type: ActivityType,
        date: Date,
        quantity: Double = 1,
        durationMinutes: Int? = nil,
        distanceKM: Double? = nil,
        watchKcal: Double? = nil,
        source: String = "manual",
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let profile, profile.userID == operation.ownerID else { throw CancellationError() }
        let now = Date().ISO8601Format()
        let log = ActivityLog(
            id: UUID(),
            userID: operation.ownerID,
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
                weightKG: data.weighedProfile()?.weightKG ?? profile.weightKG
            ),
            source: source,
            reconciled: false,
            createdAt: now,
            updatedAt: now
        )
        data.activityLogs.append(log)
        await persistUpsert(
            log,
            table: "activity_logs",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func prefillEventActivitiesIfNeeded(
        for date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let profile, profile.userID == operation.ownerID else { throw CancellationError() }
        let day = date.apexDateKey
        let event = data.events.first {
            $0.userID == operation.ownerID
                && $0.type == "filming_championship"
                && $0.startDate <= day
                && $0.endDate >= day
        }
        guard let event else { return }
        guard data.activityLogs.contains(where: { $0.date == day }) == false else { return }

        let marker = "apex.event-prefill.\(operation.ownerID.uuidString).\(event.id.uuidString).\(day)"
        guard defaults.bool(forKey: marker) == false else { return }
        try requireCurrentAccountOperation(operation)
        defaults.set(true, forKey: marker)

        if let filming = data.activityTypes.first(where: { $0.id == "gimbal-filming" }) {
            try await addActivity(
                type: filming,
                date: date,
                durationMinutes: 8 * 60,
                source: "event_prefill",
                operation: operation
            )
            try requireCurrentAccountOperation(operation)
        }
        if let travel = data.activityTypes.first(where: { $0.id == "travel-day" }) {
            try await addActivity(
                type: travel,
                date: date,
                durationMinutes: 2 * 60,
                source: "event_prefill",
                operation: operation
            )
            try requireCurrentAccountOperation(operation)
        }
    }

    func removeActivity(
        _ log: ActivityLog,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard log.userID == operation.ownerID else { throw CancellationError() }
        data.activityLogs.removeAll { $0.id == log.id && $0.userID == operation.ownerID }
        await persistDelete(
            table: "activity_logs",
            id: log.id,
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func clearActivities(
        on date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        let logs = data.activityLogs.filter {
            $0.userID == operation.ownerID && $0.date == date.apexDateKey
        }
        for log in logs {
            try await removeActivity(log, operation: operation)
            try requireCurrentAccountOperation(operation)
        }
    }

    func repeatYesterday(
        onto date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) else { return }
        let previous = data.activityLogs.filter {
            $0.userID == operation.ownerID && $0.date == yesterday.apexDateKey
        }
        for log in previous {
            try requireCurrentAccountOperation(operation)
            guard let type = data.activityTypes.first(where: { $0.id == log.typeID }) else { continue }
            try await addActivity(
                type: type,
                date: date,
                quantity: log.quantity,
                durationMinutes: log.durationMinutes,
                distanceKM: log.distanceKM,
                watchKcal: log.watchKcal,
                source: "manual",
                operation: operation
            )
            try requireCurrentAccountOperation(operation)
        }
    }

    func finalizeActivityDay(
        _ date: Date,
        targets: NutritionTargets,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let profile, profile.userID == operation.ownerID else { throw CancellationError() }
        let day = date.apexDateKey
        let activityIDs = data.activityLogs.compactMap { log in
            log.userID == operation.ownerID && log.date == day ? log.id : nil
        }
        for activityID in activityIDs {
            try requireCurrentAccountOperation(operation)
            guard let index = data.activityLogs.firstIndex(where: {
                $0.id == activityID && $0.userID == operation.ownerID
            }) else { continue }
            var reconciled = data.activityLogs[index]
            reconciled.reconciled = true
            reconciled.updatedAt = Date().ISO8601Format()
            data.activityLogs[index] = reconciled
            await persistUpsert(
                reconciled,
                table: "activity_logs",
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        let existing = data.dailyLogs.first {
            $0.userID == operation.ownerID && $0.date == day
        }
        let row = DailyLog(
            id: existing?.id ?? UUID(),
            userID: operation.ownerID,
            date: day,
            kcal: existing?.kcal,
            proteinG: existing?.proteinG,
            fatG: existing?.fatG,
            carbsG: existing?.carbsG,
            waterL: existing?.waterL ?? 0,
            estimatedTDEE: targets.tdee,
            computedPAL: targets.pal,
            activityMode: activityIDs.isEmpty ? "quick" : "precise",
            weightKG: existing?.weightKG,
            nutritionSource: existing?.nutritionSource ?? "manual",
            manualKcal: existing?.manualKcal,
            manualProteinG: existing?.manualProteinG,
            manualFatG: existing?.manualFatG,
            manualCarbsG: existing?.manualCarbsG
        )
        await updateDailyLog(
            row,
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /* A provider almost never publishes water, so it is estimated on the way in.
       Without this a scanned food silently contributes nothing to hydration. */
    func lookupFood(
        barcode: String,
        operation: AccountOperationLease
    ) async throws -> FoodLookupEnvelope {
        if isDeveloperSandbox {
            try requireCurrentAccountOperation(operation)
            return FoodLookupEnvelope(state: "not_found", source: "sample", food: nil, results: [], message: nil)
        }
        try requireCurrentAccountOperation(operation)
        let envelope = try await service.lookupFood(barcode: barcode)
        try requireCurrentAccountOperation(operation)
        let resolved = FoodLookupEnvelope(
            state: envelope.state,
            source: envelope.source,
            food: envelope.food.map(FoodHydration.resolved),
            results: envelope.results?.map(FoodHydration.resolved),
            message: envelope.message
        )
        if let found = resolved.food {
            data.foods.removeAll { $0.id.lowercased() == found.id.lowercased() }
            data.foods.insert(found, at: 0)
            try await saveLocalSnapshot(operation: operation)
        }
        try requireCurrentAccountOperation(operation)
        return resolved
    }

    func searchFoods(
        query: String,
        operation: AccountOperationLease,
        reportOnlineAvailability: ((Bool) -> Void)? = nil
    ) async throws -> [Food] {
        try requireCurrentAccountOperation(operation)
        let ownerID = operation.ownerID
        let foods = data.foods
        let preferences = data.foodPreferences
        let local = MealMemory.searchFoods(
            query: query,
            foods: foods,
            preferences: preferences,
            userID: ownerID
        )
        let remote: FoodLookupEnvelope
        do {
            remote = try await foodSearchProvider(query)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try requireCurrentAccountOperation(operation)
            reportOnlineAvailability?(false)
            return FoodNutrientEvidence.overlayBundledNaturalFoodEvidence(local)
        }
        try requireCurrentAccountOperation(operation)
        let providerUnavailable = remote.source == "provider_unavailable"
            || (remote.results?.isEmpty == true && remote.message != nil)
        reportOnlineAvailability?(remote.results != nil && !providerUnavailable)
        let resolved = (remote.results ?? []).map(FoodHydration.resolved)
        let combined = FoodNutrientEvidence.mergeLocalSearchFoods(local, with: resolved)
        return MealMemory.searchFoods(
            query: query,
            foods: combined,
            preferences: preferences,
            userID: ownerID
        )
    }

    func mealEditSnapshot(_ meal: LoggedMeal, operation: AccountOperationLease) async throws -> MealEditSnapshot {
        try requireCurrentAccountOperation(operation)
        guard meal.userID == operation.ownerID else { throw CancellationError() }
        let local = MealEditSnapshot(version: meal.clientIdempotencyKey, entries: data.loggedFoodEntries
            .filter { $0.userID == operation.ownerID && $0.mealID == meal.id }
            .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) })
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() { return local }
        do {
            let snapshot = try await service.loadMealEditSnapshot(meal.id)
            try requireCurrentAccountOperation(operation)
            guard let snapshot, snapshot.version == meal.clientIdempotencyKey,
                  !snapshot.entries.isEmpty,
                  snapshot.entries.allSatisfy({ $0.userID == operation.ownerID && $0.mealID == meal.id })
            else { throw APEXServiceError.staleMeal }
            return snapshot
        } catch {
            try requireCurrentAccountOperation(operation)
            guard !(error is APEXServiceError), !(error is CancellationError),
                  SyncFailurePolicy.classify(error) == .transient,
                  data.hasCompleteMealHistory == true, !local.entries.isEmpty
            else { throw error }
            return local
        }
    }

    /// Saves a complete meal in one atomic Supabase operation. The same RPC is
    /// used by the web client, so edits, ordering and nutrition totals converge
    /// across both clients instead of creating one row per food.
    func saveStructuredMeal(
        _ draft: MealComposerDraft,
        recordFoodUsage: Bool = true,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let profile, profile.userID == operation.ownerID else { throw CancellationError() }
        let ownerID = operation.ownerID
        let originalIDs = Set(draft.expectedEntryIDs ?? [])
        let validItems = draft.items.map { original in
            guard originalIDs.contains(original.id) else { return original }
            var item = original
            item.id = APEXStableID.scopedUUID(namespace: "meal-edit-entry", date: "\(draft.saveOperationID)/\(original.id)", userID: ownerID)
            return item
        }
        let totals = draft.totals
        guard !validItems.isEmpty, validItems.allSatisfy({ $0.isLoggablePortion }),
              [totals.kcal, totals.proteinG, totals.carbsG, totals.fatG].allSatisfy(FoodQuantity.isRepresentableTotal)
        else { throw APEXServiceError.incompleteFood }
        if draft.replaceMealID != nil && (draft.expectedMealVersion == nil || draft.expectedEntryIDs == nil) {
            throw APEXServiceError.staleMeal
        }

        let key = draft.clientIdempotencyKey
        let loggedAs = MealLogKind.normalized(draft.loggedAs)
        let request = StructuredMealRequest(
            id: draft.id,
            localDate: draft.localDate,
            mealSlot: MealBlocks.storageSlot(draft.mealSlot),
            displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? draft.mealSlot.capitalized
                : draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            sourcePresetID: draft.sourcePresetID,
            sourcePlannedMealID: draft.sourcePlannedMealID,
            loggedAt: draft.finishedAt.ISO8601Format(),
            clientIdempotencyKey: key,
            loggedAs: loggedAs,
            replaceMealID: draft.replaceMealID,
            expectedMealVersion: draft.expectedMealVersion, expectedEntryIDs: draft.expectedEntryIDs
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
                snapshotNutrientEvidence: item.nutrientEvidence,
                quantity: item.quantity,
                unit: item.unit,
                equivalentAmount: item.equivalentAmount
            )
        }
        let localMeal = LoggedMeal(
            id: draft.id,
            userID: ownerID,
            localDate: draft.localDate,
            mealSlot: request.mealSlot,
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
                userID: ownerID,
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
                waterML: item.waterML100.map { $0 * item.equivalentAmount / 100 },
                snapshotNutrientEvidence: item.nutrientEvidence
            )
        }
        let preferenceUpdates = recordFoodUsage
            ? MealMemory.usagePreferenceUpdates(
                current: data.foodPreferences,
                items: validItems,
                userID: ownerID,
                usedAt: request.loggedAt
            )
            : []

        let previousData = data
        func rollbackEditedMeal() async throws {
            try requireCurrentAccountOperation(operation)
            // A failed write may return after an unrelated workout, drink or a
            // newer edit was recorded. Undo only this optimistic meal version.
            guard data.loggedMeals.contains(where: { $0.id == draft.id && $0.clientIdempotencyKey == key }) else { return }
            let mealIDs = Set([draft.id, draft.replaceMealID].compactMap { $0 })
            data.loggedMeals.removeAll { mealIDs.contains($0.id) && $0.userID == ownerID }
            data.loggedMeals.append(contentsOf: previousData.loggedMeals.filter { mealIDs.contains($0.id) && $0.userID == ownerID })
            data.loggedFoodEntries.removeAll { mealIDs.contains($0.mealID) && $0.userID == ownerID }
            data.loggedFoodEntries.append(contentsOf: previousData.loggedFoodEntries.filter { mealIDs.contains($0.mealID) && $0.userID == ownerID })
            for preference in preferenceUpdates where data.foodPreferences.contains(preference) {
                data.foodPreferences.removeAll { $0.id == preference.id && $0.userID == ownerID }
                if let original = previousData.foodPreferences.first(where: { $0.foodID == preference.foodID && $0.userID == ownerID }) {
                    data.foodPreferences.append(original)
                }
            }
            try await recalculateLocalStructuredDay(draft.localDate, operation: operation)
            try await saveLocalSnapshot(operation: operation)
        }
        let payload = StructuredMealRPCPayload(pMeal: request, pEntries: entryRequests)
        let offlineOperation = try OfflineOperation.rpc("log_structured_meal", params: payload)

        try requireCurrentAccountOperation(operation)
        if let replaced = draft.replaceMealID {
            data.loggedMeals.removeAll { $0.id == replaced }
            data.loggedFoodEntries.removeAll { $0.mealID == replaced }
        }
        data.loggedMeals.removeAll { $0.id == draft.id }
        data.loggedMeals.insert(localMeal, at: 0)
        try await refreshNudges(operation: operation)
        try requireCurrentAccountOperation(operation)
        data.loggedFoodEntries.removeAll { $0.mealID == draft.id }
        data.loggedFoodEntries.insert(contentsOf: localEntries, at: 0)
        let updatedFoodIDs = Set(preferenceUpdates.map(\.foodID))
        data.foodPreferences.removeAll {
            $0.userID == operation.ownerID && updatedFoodIDs.contains($0.foodID)
        }
        data.foodPreferences.append(contentsOf: preferenceUpdates)
        try await recalculateLocalStructuredDay(draft.localDate, operation: operation)
        try await saveLocalSnapshot(operation: operation)

        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            try requireCurrentAccountOperation(operation)
            lastSyncAt = .now
            return
        }

        do {
            _ = try await service.logStructuredMeal(meal: request, entries: entryRequests)
            try requireCurrentAccountOperation(operation)
            lastSyncAt = .now
        } catch {
            try requireCurrentAccountOperation(operation)
            switch SyncFailurePolicy.classify(error) {
            case .transient, .authenticationRequired:
                do {
                    try await offlineStore.enqueue(offlineOperation, for: ownerID)
                    try requireCurrentAccountOperation(operation)
                    let pendingCount = try? await offlineStore.pendingOperations(for: ownerID).count
                    try requireCurrentAccountOperation(operation)
                    pendingSyncCount = pendingCount ?? pendingSyncCount + 1
                    /* Saved offline and queued. Deliberately silent: this is
                       normal offline operation, not a failed save. */
                } catch {
                    try requireCurrentAccountOperation(operation)
                    try await rollbackEditedMeal()
                    throw error
                }
            case .permanent:
                try requireCurrentAccountOperation(operation)
                try await rollbackEditedMeal()
                try? await offlineStore.recordFailure(
                    offlineOperation,
                    reason: error.localizedDescription,
                    for: ownerID
                )
                try requireCurrentAccountOperation(operation)
                throw error
            }
        }
        for preference in preferenceUpdates {
            try requireCurrentAccountOperation(operation)
            await persistUpsert(
                preference,
                table: "food_preferences",
                onConflict: "user_id,food_id",
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }

        // The write is already committed and idempotent. A dashboard refresh
        // failure must not turn a successful meal into an offline retry or a
        // false error; the optimistic local meal remains the accurate view.
        do {
            try await refreshDashboard(expectedUserID: ownerID)
            try requireCurrentAccountOperation(operation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try requireCurrentAccountOperation(operation)
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
        mealIDs: Set<UUID>? = nil,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let profile, operation.ownerID == profile.userID else { throw CancellationError() }
        let sourceKey = sourceDate.apexDateKey
        let destinationKey = destinationDate.apexDateKey
        guard sourceKey != destinationKey else { return }

        let sourceMeals = data.loggedMeals
            .filter {
                $0.userID == operation.ownerID
                    && $0.localDate == sourceKey
                    && (mealIDs == nil || mealIDs?.contains($0.id) == true)
            }
            .sorted { $0.loggedAt < $1.loggedAt }
        var destinationMeals = data.loggedMeals.filter {
            $0.userID == operation.ownerID && $0.localDate == destinationKey
        }

        for sourceMeal in sourceMeals {
            try requireCurrentAccountOperation(operation)
            let sourceEntries = try await mealEditSnapshot(sourceMeal, operation: operation).entries
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
            var draft = MealComposerDraft(
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
            if let replacement {
                let snapshot = try await mealEditSnapshot(replacement, operation: operation)
                draft.expectedMealVersion = snapshot.version
                draft.expectedEntryIDs = snapshot.entries.map(\.id)
            }
            try await saveStructuredMeal(draft, operation: operation)
            try requireCurrentAccountOperation(operation)
            destinationMeals = data.loggedMeals.filter {
                $0.userID == operation.ownerID && $0.localDate == destinationKey
            }
        }

        let structuredSourcePlannedIDs = Set(sourceMeals.compactMap(\.sourcePlannedMealID))
        let sourceChecks = data.mealLogs.filter { check in
            guard check.userID == operation.ownerID, check.date == sourceKey else { return false }
            if let mealIDs {
                // A structured planned check follows the selected structured
                // meal. Legacy checks without a structured meal are offered
                // only by a full-day paste.
                return structuredSourcePlannedIDs.contains(check.mealID)
                    && sourceMeals.contains { $0.sourcePlannedMealID == check.mealID && mealIDs.contains($0.id) }
            }
            return true
        }
        var destinationChecks = Set(data.mealLogs.filter {
            $0.userID == operation.ownerID && $0.date == destinationKey
        }.map(\.mealID))
        for sourceCheck in sourceChecks where destinationChecks.contains(sourceCheck.mealID) == false {
            try requireCurrentAccountOperation(operation)
            let row = MealLog(
                id: UUID(),
                userID: operation.ownerID,
                date: destinationKey,
                mealID: sourceCheck.mealID,
                checkedAt: Date().ISO8601Format()
            )
            data.mealLogs.append(row)
            await persistUpsert(
                row,
                table: "meal_logs",
                onConflict: "user_id,date,meal_id",
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
            destinationChecks.insert(sourceCheck.mealID)
        }

        try await saveLocalSnapshot(operation: operation)
        try requireCurrentAccountOperation(operation)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Calendar Clear intentionally removes only meals and snacks. Hydration,
    /// workouts, supplements and activity evidence remain untouched.
    func clearNutritionDay(
        _ date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        let key = date.apexDateKey
        let structured = data.loggedMeals.filter {
            $0.userID == operation.ownerID && $0.localDate == key
        }
        let legacyChecks = data.mealLogs.filter {
            $0.userID == operation.ownerID && $0.date == key
        }
        for meal in structured {
            try await deleteLoggedMeal(meal, operation: operation)
            try requireCurrentAccountOperation(operation)
        }
        for check in legacyChecks {
            try requireCurrentAccountOperation(operation)
            data.mealLogs.removeAll {
                $0.id == check.id && $0.userID == operation.ownerID
            }
            await persistDelete(
                table: "meal_logs",
                id: check.id,
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        try await recalculateLocalStructuredDay(key, operation: operation)
        try await saveLocalSnapshot(operation: operation)
        try requireCurrentAccountOperation(operation)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Moves an actual meal on the metabolic Dayline. The nutrition values do
    /// not change, only the recorded finish time used by timing intelligence.
    func updateLoggedMealFinishedAt(
        _ mealID: UUID,
        to date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let index = data.loggedMeals.firstIndex(where: {
                  $0.id == mealID && $0.userID == operation.ownerID
              }) else { return }
        let meal = data.loggedMeals[index]
        let snapshot = try await mealEditSnapshot(meal, operation: operation)
        let draft = MealComposerDraft(
            id: meal.id,
            localDate: meal.localDate,
            mealSlot: meal.mealSlot,
            displayName: meal.displayName,
            finishedAt: date,
            sourcePresetID: meal.sourcePresetID,
            sourcePlannedMealID: meal.sourcePlannedMealID,
            replaceMealID: meal.id,
            loggedAs: MealLogKind.normalized(meal.loggedAs),
            items: snapshot.entries.map(MealComposerItem.init(entry:)),
            expectedMealVersion: snapshot.version, expectedEntryIDs: snapshot.entries.map(\.id)
        )

        try await saveStructuredMeal(
            MealFinishedAtReplacement.retime(draft, to: date),
            recordFoodUsage: false,
            operation: operation
        )
        try requireCurrentAccountOperation(operation)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Moves a planned meal moment. This is intentionally account-scoped and
    /// persists the same `meals.time` value consumed by the web client.
    func updatePlannedMealTime(
        _ mealID: UUID,
        to time: String,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let index = data.meals.firstIndex(where: {
            $0.id == mealID && $0.userID == operation.ownerID
        }) else { return }
        var meal = data.meals[index]
        meal.time = time
        data.meals[index] = meal
        await persistUpsert(
            meal,
            table: "meals",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Reschedules one configured meal block, including on a fresh account
    /// where no legacy `meals` row exists yet. The settings object is shared by
    /// web and native, so the moved moment stays identical on both clients.
    func updateMealBlockTime(
        _ blockID: String,
        to time: String,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        try await updateSettings({ settings in
            var root = settings.addons["meal_blocks"]?.objectValue ?? [:]
            let blocks = MealBlocks.normalized(settings.addons["meal_blocks"]).map { block in
                JSONValue.object([
                    "id": .string(block.id),
                    "kind": .string(block.kind),
                    "time": .string(block.id == blockID ? time : block.time),
                    "enabled": .bool(block.enabled),
                ])
            }
            root["blocks"] = .array(blocks)
            if root["custom_blocks"] == nil { root["custom_blocks"] = .array([]) }
            if root["preset_assignments"] == nil { root["preset_assignments"] = .object([:]) }
            settings.addons["meal_blocks"] = .object(root)
        }, operation: operation)
        try requireCurrentAccountOperation(operation)
    }

    /// Moves the factual finish marker for a completed workout. Meal timing
    /// and recovery guidance consume this same account-scoped timestamp on web
    /// and native, so correcting it never creates a second local-only truth.
    func updateWorkoutCompletedAt(
        _ sessionID: UUID,
        to date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let index = data.workoutSessions.firstIndex(where: {
            $0.id == sessionID && $0.userID == operation.ownerID
        }) else { return }
        var workout = data.workoutSessions[index]
        guard workout.completed else { return }
        workout.completedAt = date.ISO8601Format()
        data.workoutSessions[index] = workout
        await persistUpsert(
            workout,
            table: "workout_sessions",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
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
        existing: MealPreset? = nil,
        operation: AccountOperationLease
    ) async throws -> UUID {
        try requireCurrentAccountOperation(operation)
        guard let profile, profile.userID == operation.ownerID else { throw CancellationError() }
        if let existing, existing.userID != operation.ownerID { throw CancellationError() }
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
            id: presetID, userID: operation.ownerID,
            name: preset.name, mealSlot: mealSlot,
            sourcePlannedMealID: existing?.sourcePlannedMealID,
            archived: false, version: expectedVersion + 1
        )
        let localItems = itemRequests.map { value in
            MealPresetItem(
                id: value.id, presetID: presetID, userID: operation.ownerID,
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
        try requireCurrentAccountOperation(operation)
        data.mealPresets.removeAll { $0.id == presetID && $0.userID == operation.ownerID }
        data.mealPresets.append(localPreset)
        data.mealPresetItems.removeAll {
            $0.presetID == presetID && $0.userID == operation.ownerID
        }
        data.mealPresetItems.append(contentsOf: localItems)
        if subtitle.isEmpty == false {
            guard var settings = data.settings?.rebound(to: operation.ownerID) else {
                throw APEXServiceError.configurationMissing
            }
            var subtitles = settings.addons["meal_preset_subtitles"]?.objectValue ?? [:]
            subtitles[presetID.uuidString.lowercased()] = .string(subtitle)
            settings.addons["meal_preset_subtitles"] = .object(subtitles)
            data.settings = settings
            await persistUpsert(
                settings,
                table: "settings",
                onConflict: "user_id",
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        try await saveLocalSnapshot(operation: operation)

        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            try requireCurrentAccountOperation(operation)
            lastSyncAt = .now
            return presetID
        }

        do {
            let savedID = try await service.saveMealPreset(
                preset: preset,
                items: itemRequests,
                expectedVersion: expectedVersion
            )
            try requireCurrentAccountOperation(operation)
            try await refreshDashboard(expectedUserID: operation.ownerID)
            try requireCurrentAccountOperation(operation)
            return savedID
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try requireCurrentAccountOperation(operation)
            let payload = MealPresetRPCPayload(
                pPreset: preset,
                pItems: itemRequests,
                pExpectedVersion: expectedVersion
            )
            try await offlineStore.enqueue(
                .rpc("save_meal_preset", params: payload),
                for: operation.ownerID
            )
            try requireCurrentAccountOperation(operation)
            let pendingCount = try? await offlineStore.pendingOperations(for: operation.ownerID).count
            try requireCurrentAccountOperation(operation)
            pendingSyncCount = pendingCount ?? pendingSyncCount + 1
            /* Saved offline and queued. Deliberately silent: this is the app
               working, not an event, and pendingSyncCount already shows it.
               Naming the backend on a user's screen helps nobody. */
            return presetID
        }
    }

    func deleteMealPreset(
        _ preset: MealPreset,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard preset.userID == operation.ownerID else { throw CancellationError() }
        data.mealPresets.removeAll { $0.id == preset.id && $0.userID == operation.ownerID }
        data.mealPresetItems.removeAll {
            $0.presetID == preset.id && $0.userID == operation.ownerID
        }
        try await saveLocalSnapshot(operation: operation)
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            try requireCurrentAccountOperation(operation)
            lastSyncAt = .now
            return
        }
        do {
            try await service.deleteMealPreset(preset.id)
            try requireCurrentAccountOperation(operation)
            try await refreshDashboard(expectedUserID: operation.ownerID)
            try requireCurrentAccountOperation(operation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try requireCurrentAccountOperation(operation)
            do {
                try await offlineStore.enqueue(
                    .rpc("delete_meal_preset", params: ["p_preset_id": preset.id.uuidString]),
                    for: operation.ownerID
                )
                try requireCurrentAccountOperation(operation)
                let pendingCount = try? await offlineStore.pendingOperations(for: operation.ownerID).count
                try requireCurrentAccountOperation(operation)
                pendingSyncCount = pendingCount ?? pendingSyncCount + 1
            } catch {
                try requireCurrentAccountOperation(operation)
                alertMessage = error.localizedDescription
            }
        }
    }

    func setFoodFavourite(
        _ food: Food,
        favourite: Bool,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard food.ownerUserID == nil || food.ownerUserID == operation.ownerID else { throw CancellationError() }
        guard let foodID = UUID(uuidString: food.id) else { throw APEXServiceError.incompleteFood }
        // Only explicitly referenced foods enter the account's existing cache.
        // Keep canonical catalogue values when a saved-meal snapshot is older.
        if !data.foods.contains(where: { UUID(uuidString: $0.id) == foodID }) {
            data.foods.append(food)
        }
        let existing = data.foodPreferences.first {
            $0.userID == operation.ownerID && $0.foodID == foodID
        }
        let value = FoodPreference(
            id: existing?.id ?? UUID(), userID: operation.ownerID, foodID: foodID,
            personalName: existing?.personalName, aliases: existing?.aliases ?? [],
            favourite: favourite, usualAmount: existing?.usualAmount,
            usualUnit: existing?.usualUnit, usageCount: existing?.usageCount ?? 0,
            lastUsedAt: existing?.lastUsedAt, hidden: existing?.hidden ?? false
        )
        data.foodPreferences.removeAll {
            $0.userID == operation.ownerID && $0.foodID == foodID
        }
        data.foodPreferences.append(value)
        await persistUpsert(
            value,
            table: "food_preferences",
            onConflict: "user_id,food_id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func saveAvatarStartingPoints(_ points: [String: Int], operation: AccountOperationLease) async throws {
        try requireCurrentAccountOperation(operation)
        guard let profile, profile.userID == operation.ownerID, profile.avatarStartingPoints == nil,
              ProfileIntegrityPolicy.authorizedProtocol(for: profile) == nil, AvatarStartingPoints.stats(points) != nil
        else { throw CancellationError() }
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            data.profile?.avatarStartingPoints = points
        } else {
            let saved = try await service.setAvatarStartingPoints(points, ownerID: operation.ownerID)
            try requireCurrentAccountOperation(operation)
            guard saved.userID == operation.ownerID, let accepted = saved.avatarStartingPoints else { throw CancellationError() }
            data.profile?.avatarStartingPoints = accepted
            try await saveLocalSnapshot(operation: operation)
        }
    }

    func updateProfile(
        _ transform: (inout Profile) -> Void,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard var profile, profile.userID == operation.ownerID else { throw CancellationError() }
        transform(&profile)
        profile.updatedAt = Date().ISO8601Format()
        data.profile = profile
        await persistUpsert(
            profile,
            table: "profile",
            onConflict: "user_id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func logFood(
        _ food: Food,
        amount: Double,
        unit: String,
        mealSlot: String,
        date: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let profile, operation.ownerID == profile.userID else { throw CancellationError() }
        guard let portionUnit = FoodUnitKind(rawValue: unit),
              let portion = FoodPortionMath.portion(food, quantity: amount, unit: portionUnit)
        else { throw APEXServiceError.incompleteFood }
        let equivalentAmount = portion.equivalentAmount

        let now = Date().ISO8601Format()
        let mealID = UUID()
        let entryID = UUID()
        let nutrients = food.nutrients(forEquivalentAmount: equivalentAmount)
        let nutrientEvidence = FoodNutrientEvidence.observations(for: food)
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
            snapshotNutrientEvidence: nutrientEvidence,
            quantity: amount,
            unit: unit,
            equivalentAmount: equivalentAmount
        )
        let localMeal = LoggedMeal(
            id: mealID,
            userID: operation.ownerID,
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
            userID: operation.ownerID,
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
            waterML: food.waterML100.map { $0 * equivalentAmount / 100 },
            snapshotNutrientEvidence: nutrientEvidence
        )
        let preferenceUpdates = MealMemory.usagePreferenceUpdates(
            current: data.foodPreferences,
            items: [MealComposerItem(food: food, quantity: amount, unit: unit)],
            userID: operation.ownerID,
            usedAt: now
        )

        try requireCurrentAccountOperation(operation)
        data.loggedMeals.insert(localMeal, at: 0)
        try await refreshNudges(operation: operation)
        try requireCurrentAccountOperation(operation)
        data.loggedFoodEntries.insert(localEntry, at: 0)
        let updatedFoodIDs = Set(preferenceUpdates.map(\.foodID))
        data.foodPreferences.removeAll {
            $0.userID == operation.ownerID && updatedFoodIDs.contains($0.foodID)
        }
        data.foodPreferences.append(contentsOf: preferenceUpdates)
        try await recalculateLocalStructuredDay(date.apexDateKey, operation: operation)
        try await saveLocalSnapshot(operation: operation)

        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            try requireCurrentAccountOperation(operation)
            lastSyncAt = .now
            return
        }

        do {
            _ = try await service.logStructuredMeal(meal: mealRequest, entries: [entryRequest])
            try requireCurrentAccountOperation(operation)
            try await refreshDashboard(expectedUserID: operation.ownerID)
            try requireCurrentAccountOperation(operation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try requireCurrentAccountOperation(operation)
            let payload = StructuredMealRPCPayload(pMeal: mealRequest, pEntries: [entryRequest])
            let offlineOperation = try OfflineOperation.rpc("log_structured_meal", params: payload)
            try await offlineStore.enqueue(offlineOperation, for: operation.ownerID)
            try requireCurrentAccountOperation(operation)
            let pendingCount = try? await offlineStore.pendingOperations(for: operation.ownerID).count
            try requireCurrentAccountOperation(operation)
            pendingSyncCount = pendingCount ?? pendingSyncCount + 1
            /* Saved offline and queued. Deliberately silent: this is the app
               working, not an event, and pendingSyncCount already shows it.
               Naming the backend on a user's screen helps nobody. */
        }
        /* A successful meal RPC refreshes the dashboard before the separate
           preference upsert. Reapply the captured account-owned update so the
           freshly scanned food never vanishes from Recents during that gap. */
        try requireCurrentAccountOperation(operation)
        let refreshedFoodIDs = Set(preferenceUpdates.map(\.foodID))
        data.foodPreferences.removeAll {
            $0.userID == operation.ownerID && refreshedFoodIDs.contains($0.foodID)
        }
        data.foodPreferences.append(contentsOf: preferenceUpdates)
        for preference in preferenceUpdates {
            try requireCurrentAccountOperation(operation)
            await persistUpsert(
                preference,
                table: "food_preferences",
                onConflict: "user_id,food_id",
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
    }

    func deleteLoggedMeal(
        _ meal: LoggedMeal,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let scope = StructuredMealDeletionScope(
            meal: meal,
            ownerID: operation.ownerID
        ) else { throw CancellationError() }
        let change = try StructuredMealDeletionChange(scope: scope, data: data)
        let usesLocalFixture = isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture()
        let offlineOperation: OfflineOperation?
        if usesLocalFixture {
            offlineOperation = nil
        } else {
            offlineOperation = try OfflineOperation.rpc(
                "delete_structured_meal_checked",
                params: ["p_meal_id": scope.mealID.uuidString, "p_expected_meal_version": meal.clientIdempotencyKey]
            )
        }

        let committedDeletion: DashboardData
        do {
            committedDeletion = try await ConfirmedMealDeletionPersistence
                .persistMergedBeforePublishing(
                    snapshot: { (self.dashboardMutationRevision, self.data) },
                    merge: { try change.deleting(from: $0) },
                    persist: { proposed in
                        try self.requireCurrentAccountOperation(operation)
                        try await self.offlineStore.saveDashboard(
                            proposed,
                            for: operation.ownerID
                        )
                        try self.requireCurrentAccountOperation(operation)
                    }
                )
        } catch {
            let deletionError = error
            guard accountOperationIsCurrent(operation) else {
                throw CancellationError()
            }
            /* A previous merge attempt may already have reached disk before a
               newer dashboard revision was detected. Restore the latest
               observable state without publishing any stale snapshot. */
            do {
                try await persistStableMealDeletionSnapshot(operation: operation)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                /* The observable dashboard is still unchanged and authoritative. */
            }
            try requireCurrentAccountOperation(operation)
            throw deletionError
        }

        /* There is deliberately no suspension between the stable revision
           check above and publishing the merged owner-scoped deletion. */
        data = committedDeletion

        let outcome: ConfirmedMealDeletionPersistence.Outcome
        do {
            if usesLocalFixture {
                outcome = .remote
            } else {
                outcome = try await ConfirmedMealDeletionPersistence.synchronize(
                    remote: {
                        try self.requireCurrentAccountOperation(operation)
                        try await self.service.deleteStructuredMeal(scope.mealID, expectedVersion: meal.clientIdempotencyKey)
                        try self.requireCurrentAccountOperation(operation)
                    },
                    enqueue: {
                        guard let offlineOperation else {
                            throw StructuredMealDeletionError.durabilityUnavailable
                        }
                        try self.requireCurrentAccountOperation(operation)
                        try await self.offlineStore.enqueue(
                            offlineOperation,
                            for: operation.ownerID
                        )
                        try self.requireCurrentAccountOperation(operation)
                    }
                )
            }
        } catch {
            let deletionError = error
            guard accountOperationIsCurrent(operation) else {
                throw CancellationError()
            }
            let restored = change.restoring(in: data)
            data = restored
            do {
                try await persistStableMealDeletionSnapshot(operation: operation)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                /* The visible state is restored and the server never accepted
                   the deletion. A later refresh therefore converges safely. */
            }
            try requireCurrentAccountOperation(operation)
            throw deletionError
        }

        try requireCurrentAccountOperation(operation)
        switch outcome {
        case .queued:
            let pendingCount = try? await offlineStore.pendingOperations(for: operation.ownerID).count
            try requireCurrentAccountOperation(operation)
            pendingSyncCount = pendingCount ?? pendingSyncCount + 1
            /* Queued, and silent for the same reason a queued save is. */
        case .remote:
            lastSyncAt = .now
        }

        try await reconcileStructuredDayHydration(
            scope.localDate,
            operation: operation
        )
        try requireCurrentAccountOperation(operation)
        do {
            try await persistStableMealDeletionSnapshot(operation: operation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            /* The deletion and hydration convergence are already durable via
               their server or outbox operations; this cache is recoverable. */
        }
    }

    func saveProgressPhoto(
        original: Data,
        thumbnail: Data,
        width: Int,
        height: Int,
        pose: String,
        framing: ProgressPhotoEngine.FramingMode,
        note: String,
        weightKG: Double? = nil,
        date: Date,
        operation: AccountOperationLease
    ) async throws {
        if isDeveloperSandbox { throw CancellationError() }
        try requireCurrentAccountOperation(operation)
        guard let profile,
              profile.userID == operation.ownerID else { throw CancellationError() }
        let row = ProgressPhotoEngine.checkpoint(
            id: UUID(),
            userID: operation.ownerID,
            takenAt: date,
            pose: pose,
            framing: framing,
            width: width,
            height: height,
            referencePhotoID: data.progressPhotos.first(where: { $0.pose == pose })?.id,
            weightKG: weightKG,
            note: note
        )
        if APEXRuntimeEnvironment.usesLocalUITestFixture() == false {
            do {
                try await service.uploadProgressPhoto(row: row, original: original, thumbnail: thumbnail)
            } catch {
                try requireCurrentAccountOperation(operation)
                throw error
            }
        }
        try requireCurrentAccountOperation(operation)
        data.progressPhotos.insert(row, at: 0)
        try await saveLocalSnapshot(operation: operation)
        try requireCurrentAccountOperation(operation)
    }

    /// Progress photos older than the first page and the earlier pages
    /// already loaded, a page at a time.
    func earlierProgressPhotos(
        after earlier: [ProgressPhoto],
        operation: AccountOperationLease
    ) async throws -> (photos: [ProgressPhoto], reachedEnd: Bool) {
        if isDeveloperSandbox { return ([], true) }
        try requireCurrentAccountOperation(operation)
        let page = try await service.loadEarlierProgressPhotos(
            ownerID: operation.ownerID,
            firstPage: data.progressPhotos.filter { $0.userID == operation.ownerID },
            earlier: earlier.filter { $0.userID == operation.ownerID }
        )
        try requireCurrentAccountOperation(operation)
        return (page.photos.filter { $0.userID == operation.ownerID }, page.reachedEnd)
    }

    func signedProgressURL(
        for photo: ProgressPhoto,
        thumbnail: Bool,
        operation: AccountOperationLease
    ) async throws -> URL {
        if isDeveloperSandbox { throw CancellationError() }
        try requireCurrentAccountOperation(operation)
        guard photo.userID == operation.ownerID else { throw CancellationError() }
        let url = try await service.signedProgressURL(
            path: thumbnail ? photo.thumbnailPath : photo.storagePath
        )
        try requireCurrentAccountOperation(operation)
        return url
    }

    #if DEBUG
    private var uiTestWorkoutSaveFailureInjected = false
    #endif

    /// Returns the finished session's id so the caller can show its receipt.
    @discardableResult
    func completeWorkout(
        day: ProgramDay,
        setInputs: [WorkoutSetInput],
        lite: Bool,
        startedAt: Date,
        finishedAt: Date? = Date(),
        qualityScore: Double? = nil,
        warmupOnly: PlayerTimeline.WarmupOnly? = nil,
        wearableLinkRequest: WearableLinkRequest = .automatic,
        completionDate: String? = nil,
        operation: AccountOperationLease
    ) async throws -> UUID? {
        try requireCurrentAccountOperation(operation)
        let ownerID = operation.ownerID
        guard TrainingInduction.workoutOwnerID(in: data, day: day) == ownerID else {
            return nil
        }
        if let finishedAt {
            let elapsed = finishedAt.timeIntervalSince(startedAt)
            guard elapsed.isFinite, elapsed >= 0, elapsed < Double(Int.max) else { return nil }
        }
        if warmupOnly != nil && !setInputs.isEmpty { return nil }
        if warmupOnly == nil && setInputs.isEmpty && wearableLinkRequest == .automatic { return nil }
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
        let completedDate = completionDate ?? Date().apexDateKey
        guard WorkoutReceipt.canComplete(on: completedDate) else { return nil }
        let startedAtISO = startedAt.ISO8601Format()
        // A failed local write or outbox enqueue leaves the draft available.
        // Its retry must persist the same receipt graph, not create another.
        let existingWorkout = data.workoutSessions.first {
            $0.userID == ownerID && $0.programDayID == day.id
                && $0.date == completedDate && $0.isLite == lite
                && $0.startedAt == startedAtISO && $0.completed
        }
        let isDeload = TrainingAdjustmentEngine.isDeload(
            on: completedDate,
            marks: (data.deloadMarks ?? []).filter { $0.userID == ownerID }
        ) || TrainingPlanEngine.isScheduledDeload(data, programID: day.programID, date: completedDate)
        var workout = existingWorkout ?? WorkoutSession(
            id: APEXStableID.scopedUUID(
                namespace: "guided-workout-receipt",
                date: "\(day.id):\(completedDate):\(lite):\(startedAtISO)",
                userID: ownerID
            ), userID: ownerID, date: completedDate,
            programDayID: day.id, isLite: lite, isDeload: isDeload,
            isEventRecovery: warmupOnly != nil, completed: true, qualityScore: 1,
            startedAt: startedAtISO, completedAt: finishedAt?.ISO8601Format(),
            notes: warmupOnly?.notes ?? (wearableLinkRequest == .automatic
                ? "Completed in FITR MAX iOS"
                : "Completed externally from the FITR MAX guided player")
        )
        if let qualityScore, qualityScore.isFinite {
            workout.qualityScore = min(1, max(0, qualityScore))
        }
        let existingLogs = data.workoutLogs.filter { $0.userID == ownerID && $0.sessionID == workout.id }
        let logs = normalizedInputs.map { input in
            let oldLog = existingLogs.first {
                $0.exerciseID == input.exerciseID && $0.exerciseName == input.exerciseName
                    && $0.setNumber == input.setNumber
            }
            let movementKey = input.exerciseID?.uuidString ?? input.movementID ?? input.exerciseName
            return WorkoutLog(
                id: oldLog?.id ?? APEXStableID.scopedUUID(
                    namespace: "guided-workout-log",
                    date: "\(workout.id):\(movementKey):\(input.setNumber)",
                    userID: ownerID
                ), userID: ownerID, sessionID: workout.id,
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
                overrideFlag: oldLog?.overrideFlag ?? false, createdAt: oldLog?.createdAt ?? now
            )
        }
        var linkedWearable = data.importedActivities.first {
            $0.userID == ownerID && $0.apexWorkoutSessionID == workout.id
        }
        if case let .activity(activityID) = wearableLinkRequest {
            guard let selected = data.importedActivities.first(where: {
                      $0.id == activityID && $0.userID == ownerID
                  }),
                  let linked = WearableWorkoutLinking.explicitLink(selected, to: workout) else {
                return nil
            }
            linkedWearable = linked
        }

        var candidate = data
        candidate.workoutSessions.removeAll { $0.userID == ownerID && $0.id == workout.id }
        candidate.workoutSessions.append(workout)
        candidate.workoutLogs.removeAll { $0.userID == ownerID && $0.sessionID == workout.id }
        candidate.workoutLogs.append(contentsOf: logs)
        if wearableLinkRequest == .automatic {
            linkedWearable = WearableWorkoutLinking.automaticLinks(
                sessions: candidate.workoutSessions,
                activities: candidate.importedActivities,
                ownerID: ownerID
            ).first { $0.apexWorkoutSessionID == workout.id } ?? linkedWearable
        }
        if let linkedWearable {
            candidate.importedActivities.removeAll { $0.id == linkedWearable.id }
            candidate.importedActivities.append(linkedWearable)
        }

        var linkedActivity = data.activityLogs.first {
            $0.userID == ownerID && $0.id == WorkoutReceipt.generatedActivityID(for: workout)
        }
        if linkedActivity == nil, warmupOnly == nil, wearableLinkRequest == .automatic, let finishedAt,
           let profile, profile.userID == ownerID,
           let activityType = data.activityTypes.first(where: { $0.id == "apex-strength" }) {
            let elapsed = max(0, Int(finishedAt.timeIntervalSince(startedAt) / 60))
            let activity = ActivityLog(
                id: WorkoutReceipt.generatedActivityID(for: workout),
                userID: ownerID,
                date: completedDate,
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
                    weightKG: data.weighedProfile()?.weightKG ?? profile.weightKG
                ),
                source: "workout_module",
                reconciled: false,
                createdAt: now,
                updatedAt: now
            )
            candidate.activityLogs.append(activity)
            linkedActivity = activity
        }

        func publishReceipt() {
            // Nutrition or other account edits may happen during storage awaits.
            // Publish only this receipt graph into the current dashboard.
            var current = data
            current.workoutSessions.removeAll { $0.userID == ownerID && $0.id == workout.id }
            current.workoutSessions.append(workout)
            current.workoutLogs.removeAll { $0.userID == ownerID && $0.sessionID == workout.id }
            current.workoutLogs.append(contentsOf: logs)
            if let linkedWearable {
                current.importedActivities.removeAll { $0.id == linkedWearable.id }
                current.importedActivities.append(linkedWearable)
            }
            if let linkedActivity {
                current.activityLogs.removeAll { $0.id == linkedActivity.id }
                current.activityLogs.append(linkedActivity)
            }
            data = current
        }

        /* The receipt is part of completing the workout, so it must not wait
           for a chain of remote writes. Preserve one complete local snapshot
           first, durably enqueue its dependency bundle, then let the normal
           offline-aware sync path drain in the background. */
        #if DEBUG
        if APEXRuntimeEnvironment.usesLocalUITestFixture(),
           ProcessInfo.processInfo.arguments.contains("-fitr-ui-test-save-failure"),
           !uiTestWorkoutSaveFailureInjected {
            uiTestWorkoutSaveFailureInjected = true
            throw CocoaError(.fileWriteOutOfSpace)
        }
        #endif
        // Completion may clear the player's only recovery draft, so unlike
        // best-effort background snapshots this write must report failure.
        if !isDeveloperSandbox && !APEXRuntimeEnvironment.usesLocalUITestFixture() {
            try await offlineStore.saveDashboard(candidate, for: ownerID)
        }
        try requireCurrentAccountOperation(operation)
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            try requireCurrentAccountOperation(operation)
            publishReceipt()
            lastSyncAt = .now
            return workout.id
        }
        do {
            try requireCurrentAccountOperation(operation)
            guard TrainingInduction.belongsToAccount(data, userID: ownerID) else {
                throw CancellationError()
            }
            func completionOperation<T: Encodable & Sendable>(
                _ value: T, table: String, recordID: UUID, onConflict: String? = nil
            ) throws -> OfflineOperation {
                // A changed retry gets its own operation, even if the earlier
                // payload is already syncing. Identical retries still coalesce.
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                let payload = try encoder.encode(value).base64EncodedString()
                return try OfflineOperation.upsert(
                    value, table: table, onConflict: onConflict,
                    id: APEXStableID.scopedUUID(
                        namespace: "workout-completion-outbox",
                        date: "\(table):\(recordID):\(payload)", userID: ownerID
                    )
                )
            }
            let parent = try completionOperation(
                workout,
                table: "workout_sessions",
                recordID: workout.id
            )
            var dependents = try logs.map {
                try completionOperation(
                    $0,
                    table: "workout_logs",
                    recordID: $0.id
                )
            }
            if let linkedActivity {
                dependents.append(
                    try completionOperation(
                        linkedActivity,
                        table: "activity_logs",
                        recordID: linkedActivity.id
                    )
                )
            }
            if let linkedWearable {
                dependents.append(
                    try completionOperation(
                        linkedWearable,
                        table: "imported_activities",
                        recordID: linkedWearable.id,
                        onConflict: "user_id,healthkit_workout_id"
                    )
                )
            }
            try await offlineStore.enqueue(
                parent: parent,
                dependents: dependents,
                for: ownerID
            )
            try requireCurrentAccountOperation(operation)
            let storedPendingCount =
                try? await offlineStore.pendingOperations(for: ownerID).count
            try requireCurrentAccountOperation(operation)
            pendingSyncCount =
                storedPendingCount ?? pendingSyncCount + dependents.count + 1
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try requireCurrentAccountOperation(operation)
            throw error
        }

        try requireCurrentAccountOperation(operation)
        publishReceipt()
        workoutSyncTask?.cancel()
        workoutSyncTask = Task { @MainActor [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.accountOperationIsCurrent(operation) else { return }
            await self.flushPendingChanges(for: ownerID)
        }
        return workout.id
    }

    /// Correct measured facts from a finished-session receipt. A correction
    /// keeps the original row identity, so history and progression never split
    /// one performed set into two events.
    @discardableResult
    func updateWorkoutLog(
        id: UUID,
        draft: WorkoutSetInput,
        operation: AccountOperationLease
    ) async throws -> Bool {
        try requireCurrentAccountOperation(operation)
        let ownerID = operation.ownerID
        guard let index = data.workoutLogs.firstIndex(where: {
                  $0.id == id && $0.userID == ownerID
              }), let parent = data.workoutSessions.first(where: {
                  $0.id == data.workoutLogs[index].sessionID && $0.userID == ownerID
              }) else {
            return false
        }
        let original = data.workoutLogs[index]
        guard draft != WorkoutReceipt.editInput(original) else { return true }
        let updated = WorkoutReceipt.correctedLog(original, with: draft)
        guard updated != original else { return true }
        var candidate = data
        candidate.workoutLogs[index] = updated
        if APEXRuntimeEnvironment.usesLocalUITestFixture() {
            data = candidate
            return true
        }
        // The receipt may still be waiting for its original completion upload.
        // Persist the parent and edit together before reporting local success.
        try await offlineStore.saveDashboard(candidate, for: ownerID)
        try requireCurrentAccountOperation(operation)
        try await offlineStore.enqueue(
            parent: OfflineOperation.upsert(parent, table: "workout_sessions", onConflict: nil),
            dependents: [OfflineOperation.upsert(updated, table: "workout_logs", onConflict: nil)],
            for: ownerID
        )
        try requireCurrentAccountOperation(operation)
        if let currentIndex = data.workoutLogs.firstIndex(where: { $0.id == id && $0.userID == ownerID }) {
            data.workoutLogs[currentIndex] = updated
        }
        let count = try? await offlineStore.pendingOperations(for: ownerID).count
        try requireCurrentAccountOperation(operation)
        pendingSyncCount = count ?? pendingSyncCount + 2
        workoutSyncTask = Task { @MainActor [weak self] in
            guard let self, self.accountOperationIsCurrent(operation) else { return }
            await self.flushPendingChanges(for: ownerID)
        }
        return true
    }

    /// Move an owned receipt without creating another workout or rewriting
    /// the immutable HealthKit workout linked to it.
    @discardableResult
    func updateCompletedWorkoutTiming(
        id: UUID, date: String, startedAt: Date?, completedAt: Date,
        operation: AccountOperationLease
    ) async throws -> Bool {
        try requireCurrentAccountOperation(operation)
        let ownerID = operation.ownerID
        guard let correction = WorkoutReceipt.timingCorrection(
            data: data, sessionID: id, ownerID: ownerID,
            date: date, startedAt: startedAt, completedAt: completedAt
        ) else { return false }
        func applyingCorrection(to source: DashboardData) -> DashboardData {
            var result = source
            result.workoutSessions = result.workoutSessions.map {
                $0.id == id && $0.userID == ownerID ? correction.session : $0
            }
            let logs = Dictionary(uniqueKeysWithValues: correction.logs.map { ($0.id, $0) })
            result.workoutLogs = result.workoutLogs.map { row in
                row.userID == ownerID ? logs[row.id] ?? row : row
            }
            let activities = Dictionary(uniqueKeysWithValues: correction.activities.map { ($0.id, $0) })
            result.activityLogs = result.activityLogs.map { row in
                row.userID == ownerID ? activities[row.id] ?? row : row
            }
            return result
        }
        let candidate = applyingCorrection(to: data)
        if !isDeveloperSandbox && !APEXRuntimeEnvironment.usesLocalUITestFixture() {
            try await offlineStore.saveDashboard(candidate, for: ownerID)
            try requireCurrentAccountOperation(operation)
            let parent = try OfflineOperation.upsert(correction.session, table: "workout_sessions", onConflict: nil)
            let dependents = try correction.logs.map {
                try OfflineOperation.upsert($0, table: "workout_logs", onConflict: nil)
            } + correction.activities.map {
                try OfflineOperation.upsert($0, table: "activity_logs", onConflict: nil)
            }
            try await offlineStore.enqueue(parent: parent, dependents: dependents, for: ownerID)
            try requireCurrentAccountOperation(operation)
            let count = try? await offlineStore.pendingOperations(for: ownerID).count
            try requireCurrentAccountOperation(operation)
            pendingSyncCount = count ?? pendingSyncCount + dependents.count + 1
        }
        try requireCurrentAccountOperation(operation)
        data = applyingCorrection(to: data)
        if !isDeveloperSandbox && !APEXRuntimeEnvironment.usesLocalUITestFixture() {
            workoutSyncTask?.cancel()
            workoutSyncTask = Task { @MainActor [weak self] in
                guard let self, self.accountOperationIsCurrent(operation) else { return }
                await self.flushPendingChanges(for: ownerID)
            }
        }
        return true
    }

    /// Remove a completed receipt and all of its measured set rows. A linked
    /// external workout is unlinked first and remains intact in Apple Health;
    /// unrelated activity records are never guessed by date or source.
    @discardableResult
    func deleteCompletedWorkoutSession(
        id: UUID,
        operation: AccountOperationLease
    ) async throws -> Bool {
        try requireCurrentAccountOperation(operation)
        let ownerID = operation.ownerID
        guard let plan = WorkoutReceipt.deletionPlan(
                sessions: data.workoutSessions,
                logs: data.workoutLogs,
                activities: data.activityLogs,
                sessionID: id,
                ownerID: ownerID
              ) else {
            return false
        }

        let logIDs = Set(plan.logIDs)
        let unlinkedWearables = data.importedActivities.compactMap { activity -> ImportedActivity? in
            guard activity.userID == ownerID,
                  activity.apexWorkoutSessionID == plan.sessionID,
                  ExternalWorkoutImport.isAPEXBundleIdentifier(
                    activity.sourceBundleIdentifier ?? ""
                  ) == false else { return nil }
            return activity.linkingToAPEXSession(nil)
        }
        for activity in unlinkedWearables {
            data.importedActivities.removeAll { $0.id == activity.id }
            data.importedActivities.append(activity)
        }
        data.workoutLogs.removeAll { logIDs.contains($0.id) }
        let activityLogIDs = Set(plan.activityLogIDs)
        data.activityLogs.removeAll { $0.userID == ownerID && activityLogIDs.contains($0.id) }
        data.workoutSessions.removeAll { $0.id == plan.sessionID }
        recomputeBrain()
        try await saveLocalSnapshot(operation: operation)

        for activityID in plan.activityLogIDs {
            try requireCurrentAccountOperation(operation)
            await persistDelete(
                table: "activity_logs",
                id: activityID,
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        for logID in plan.logIDs {
            try requireCurrentAccountOperation(operation)
            await persistDelete(
                table: "workout_logs",
                id: logID,
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        for activity in unlinkedWearables {
            try requireCurrentAccountOperation(operation)
            await persistUpsert(
                activity,
                table: "imported_activities",
                onConflict: "user_id,healthkit_workout_id",
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        await persistDelete(
            table: "workout_sessions",
            id: plan.sessionID,
            ownerID: ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        return true
    }

    /// Hide only APEX's account-owned receipt. The source HKWorkout remains
    /// untouched in Apple Health and can continue contributing to its totals.
    @discardableResult
    func hideExternalWorkoutFromAPEX(
        id: UUID,
        operation: AccountOperationLease
    ) async throws -> Bool {
        try requireCurrentAccountOperation(operation)
        let ownerID = operation.ownerID
        guard let index = data.importedActivities.firstIndex(where: {
                  $0.id == id && $0.userID == ownerID && $0.healthKitWorkoutID != nil
              }) else { return false }

        let hidden = data.importedActivities[index].hidingFromAPEX(at: Date().ISO8601Format())
        data.importedActivities[index] = hidden
        try await saveLocalSnapshot(operation: operation)
        await persistUpsert(
            hidden,
            table: "imported_activities",
            onConflict: "user_id,healthkit_workout_id",
            ownerID: ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        return true
    }

    func toggleDeload(
        on date: Date = .now,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        let ownerID = operation.ownerID
        let day = date.apexDateKey
        if let existing = (data.deloadMarks ?? []).first(where: {
            $0.userID == ownerID && $0.date == day
        }) {
            data.deloadMarks?.removeAll {
                $0.id == existing.id && $0.userID == ownerID
            }
            await persistDelete(
                table: "deload_marks",
                id: existing.id,
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
        } else {
            let mark = DeloadMark(id: UUID(), userID: ownerID, date: day)
            if data.deloadMarks == nil { data.deloadMarks = [] }
            data.deloadMarks?.append(mark)
            await persistUpsert(
                mark,
                table: "deload_marks",
                onConflict: "user_id,date",
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
        }
        try requireCurrentAccountOperation(operation)
    }

    func exportOrbitData() throws -> URL {
        if isDeveloperSandbox { throw CancellationError() }
        guard let profile else { throw APEXServiceError.configurationMissing }
        return try OrbitPrivateArchive
            .ownerScoped(from: data, userID: profile.userID)
            .writeTemporaryFile()
    }

    func deleteAllOrbitData(operation: AccountOperationLease) async throws {
        try requireCurrentAccountOperation(operation)
        guard profile?.userID == operation.ownerID else { throw CancellationError() }
        let ownerID = operation.ownerID

        let posters = data.orbitPosters.filter { $0.userID == ownerID }
        let segments = data.orbitSegments.filter { $0.userID == ownerID }
        let runs = data.orbitRuns.filter { $0.userID == ownerID }
        let campaignSessions = data.orbitCampaignSessions.filter { $0.userID == ownerID }
        let campaigns = data.orbitCampaigns.filter { $0.userID == ownerID }
        let inductions = data.orbitInductions.filter { $0.userID == ownerID }
        let routes = data.orbitRoutes.filter { $0.userID == ownerID }
        let shoes = data.orbitShoes.filter { $0.userID == ownerID }

        // Clear the local owner-scoped view first. Each remote delete then uses
        // the normal protected offline outbox if connectivity disappears.
        data.orbitPosters.removeAll { $0.userID == ownerID }
        data.orbitSegments.removeAll { $0.userID == ownerID }
        data.orbitRuns.removeAll { $0.userID == ownerID }
        data.orbitCampaignSessions.removeAll { $0.userID == ownerID }
        data.orbitCampaigns.removeAll { $0.userID == ownerID }
        data.orbitInductions.removeAll { $0.userID == ownerID }
        data.orbitRoutes.removeAll { $0.userID == ownerID }
        data.orbitShoes.removeAll { $0.userID == ownerID }
        if !isDeveloperSandbox { OrbitLocationManager.shared.cancel() }
        try await saveLocalSnapshot(operation: operation)

        let deletions: [(String, UUID)] =
            posters.map { ("orbit_posters", $0.id) }
            + segments.map { ("orbit_segments", $0.id) }
            + runs.map { ("orbit_runs", $0.id) }
            + campaignSessions.map { ("orbit_campaign_sessions", $0.id) }
            + campaigns.map { ("orbit_campaigns", $0.id) }
            + inductions.map { ("orbit_inductions", $0.id) }
            + routes.map { ("orbit_routes", $0.id) }
            + shoes.map { ("orbit_shoes", $0.id) }
        for (table, id) in deletions {
            try requireCurrentAccountOperation(operation)
            await persistDelete(
                table: table,
                id: id,
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        try requireCurrentAccountOperation(operation)
        alertMessage = "Orbit data deleted for this profile."
    }

    func saveOrbitRun(
        ownerID: UUID,
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
        shoeID: UUID? = nil,
        operation: AccountOperationLease
    ) async throws -> OrbitRunRecord? {
        try requireCurrentAccountOperation(operation)
        guard let profile,
              ownerID == operation.ownerID,
              profile.userID == operation.ownerID else { throw CancellationError() }
        let metrics = OrbitRunMetricsEngine.calculate(
            samples: samples,
            elapsedSeconds: endedAt.timeIntervalSince(startedAt),
            movingSeconds: movingSeconds,
            weightKG: data.weighedProfile()?.weightKG ?? profile.weightKG
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
        try requireCurrentAccountOperation(operation)
        data.orbitRuns.insert(run, at: 0)
        await persistUpsert(
            run,
            table: "orbit_runs",
            onConflict: "user_id,client_idempotency_key",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        if let campaignSessionID,
           let index = data.orbitCampaignSessions.firstIndex(where: {
               $0.id == campaignSessionID && $0.userID == operation.ownerID
           }) {
            data.orbitCampaignSessions[index].status = "completed"
            data.orbitCampaignSessions[index].completionRunID = runID
            data.orbitCampaignSessions[index].updatedAt = now
            await persistUpsert(
                data.orbitCampaignSessions[index],
                table: "orbit_campaign_sessions",
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        try await integrateOrbitRun(run, operation: operation)
        try requireCurrentAccountOperation(operation)
        return run
    }

    func updateOrbitRunCheckIn(
        _ run: OrbitRunRecord,
        perceivedEffort: Int?,
        legs: String?,
        discomfort: String?,
        note: String,
        operation: AccountOperationLease
    ) async throws -> OrbitRunRecord {
        try requireCurrentAccountOperation(operation)
        guard run.userID == operation.ownerID else { throw CancellationError() }
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
        try requireCurrentAccountOperation(operation)
        if let index = data.orbitRuns.firstIndex(where: {
            $0.id == run.id && $0.userID == operation.ownerID
        }) {
            data.orbitRuns[index] = updated
        }
        await persistUpsert(
            updated,
            table: "orbit_runs",
            onConflict: "user_id,client_idempotency_key",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        try await adaptCampaignAfterRun(updated, operation: operation)
        try requireCurrentAccountOperation(operation)
        return updated
    }

    func applyOrbitNutritionAdjustment(
        to run: OrbitRunRecord,
        foodSuggestion: OrbitFoodMemorySuggestion?,
        operation: AccountOperationLease
    ) async throws -> OrbitRunRecord {
        try requireCurrentAccountOperation(operation)
        guard let profile, run.userID == operation.ownerID,
              profile.userID == operation.ownerID,
              run.nutritionAdjustmentAppliedAt == nil
        else { return run }
        let adjustment = OrbitIntegrations.nutritionAdjustment(
            run: run, weightKG: data.weighedProfile()?.weightKG ?? profile.weightKG
        )
        guard adjustment.kcal > 0 else { return run }

        guard let draft = OrbitIntegrations.nutritionMealDraft(run: run, suggestion: foodSuggestion) else {
            try requireCurrentAccountOperation(operation)
            alertMessage = "Choose one of your saved foods before applying this Orbit adjustment."
            return run
        }
        do {
            try await saveStructuredMeal(draft, operation: operation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try requireCurrentAccountOperation(operation)
            alertMessage = "The Orbit food adjustment was not applied. \(error.localizedDescription)"
            return run
        }

        try requireCurrentAccountOperation(operation)
        let updated = OrbitRunRecord(
            id: run.id, userID: run.userID, clientIdempotencyKey: run.clientIdempotencyKey,
            localDate: run.localDate, startedAt: run.startedAt, endedAt: run.endedAt,
            mission: run.mission, routeID: run.routeID, campaignSessionID: run.campaignSessionID,
            shoeID: run.shoeID, samples: run.samples, pauses: run.pauses,
            manualLapsM: run.manualLapsM, metrics: run.metrics, checkIn: run.checkIn,
            nutritionAdjustmentAppliedAt: Date().ISO8601Format(), status: run.status,
            createdAt: run.createdAt, updatedAt: Date().ISO8601Format()
        )
        data.orbitRuns.removeAll {
            $0.id == run.id && $0.userID == operation.ownerID
        }
        data.orbitRuns.insert(updated, at: 0)
        await persistUpsert(
            updated,
            table: "orbit_runs",
            onConflict: "user_id,client_idempotency_key",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        return updated
    }

    func saveOrbitInduction(
        _ induction: OrbitInduction,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard induction.userID == operation.ownerID else { throw CancellationError() }
        if let index = data.orbitInductions.firstIndex(where: {
            $0.id == induction.id && $0.userID == operation.ownerID
        }) {
            data.orbitInductions[index] = induction
        } else {
            data.orbitInductions.insert(induction, at: 0)
        }
        await persistUpsert(
            induction,
            table: "orbit_inductions",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func completeOrbitInduction(
        _ induction: OrbitInduction,
        operation: AccountOperationLease
    ) async throws -> OrbitCampaign {
        try requireCurrentAccountOperation(operation)
        guard induction.userID == operation.ownerID else { throw CancellationError() }
        try await saveOrbitInduction(induction, operation: operation)
        try requireCurrentAccountOperation(operation)
        let generated = OrbitCampaignEngine.createCampaign(
            induction: induction,
            programDays: TrainingInduction.activeProgramDays(in: data, userID: operation.ownerID),
            events: data.events.filter { $0.userID == operation.ownerID }
        )
        guard generated.campaign.userID == operation.ownerID,
              generated.sessions.allSatisfy({ $0.userID == operation.ownerID })
        else { throw CancellationError() }
        data.orbitCampaigns.removeAll {
            $0.id == generated.campaign.id && $0.userID == operation.ownerID
        }
        data.orbitCampaigns.insert(generated.campaign, at: 0)
        let generatedIDs = Set(generated.sessions.map(\.id))
        data.orbitCampaignSessions.removeAll {
            generatedIDs.contains($0.id) && $0.userID == operation.ownerID
        }
        data.orbitCampaignSessions.append(contentsOf: generated.sessions)
        await persistUpsert(
            generated.campaign,
            table: "orbit_campaigns",
            onConflict: "user_id,client_idempotency_key",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        for item in generated.sessions {
            await persistUpsert(
                item,
                table: "orbit_campaign_sessions",
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        return generated.campaign
    }

    func markOrbitCampaignSessionMissed(
        _ session: OrbitCampaignSession,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard session.userID == operation.ownerID,
              let campaign = data.orbitCampaigns.first(where: {
                  $0.id == session.campaignID && $0.userID == operation.ownerID
              }) else { throw CancellationError() }
        let bundle = OrbitCampaignEngine.adaptAfterMissed(
            campaign: campaign,
            sessions: data.orbitCampaignSessions.filter {
                $0.campaignID == campaign.id && $0.userID == operation.ownerID
            },
            missedID: session.id
        )
        try await saveCampaignBundle(
            bundle.campaign,
            sessions: bundle.sessions,
            operation: operation
        )
        try requireCurrentAccountOperation(operation)
    }

    func chooseOrbitCampaignVersion(
        _ session: OrbitCampaignSession,
        useOriginal: Bool,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard session.userID == operation.ownerID,
              let campaignIndex = data.orbitCampaigns.firstIndex(where: {
                  $0.id == session.campaignID && $0.userID == operation.ownerID
              }) else { throw CancellationError() }
        var updatedSession = session
        if useOriginal { updatedSession.adapted = updatedSession.original }
        updatedSession.userOverride = true
        if useOriginal { updatedSession.adaptationReason = "User kept the original prescription." }
        updatedSession.updatedAt = Date().ISO8601Format()
        if let index = data.orbitCampaignSessions.firstIndex(where: {
            $0.id == session.id && $0.userID == operation.ownerID
        }) {
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
        await persistUpsert(
            updatedSession,
            table: "orbit_campaign_sessions",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        await persistUpsert(
            campaign,
            table: "orbit_campaigns",
            onConflict: "user_id,client_idempotency_key",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func saveOrbitRoute(
        _ candidate: OrbitRouteCandidate,
        name: String,
        mission: String,
        surface: String,
        shape: String,
        operation: AccountOperationLease
    ) async throws -> OrbitRouteRecord? {
        try requireCurrentAccountOperation(operation)
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
            userID: operation.ownerID,
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
        await persistUpsert(
            route,
            table: "orbit_routes",
            onConflict: "user_id,client_idempotency_key",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        return route
    }

    func updateOrbitRoute(
        _ route: OrbitRouteRecord,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard route.userID == operation.ownerID else { throw CancellationError() }
        var updated = route
        updated.updatedAt = Date().ISO8601Format()
        data.orbitRoutes.removeAll {
            $0.id == updated.id && $0.userID == operation.ownerID
        }
        data.orbitRoutes.insert(updated, at: 0)
        await persistUpsert(
            updated,
            table: "orbit_routes",
            onConflict: "user_id,client_idempotency_key",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func duplicateOrbitRoute(
        _ route: OrbitRouteRecord,
        operation: AccountOperationLease
    ) async throws -> OrbitRouteRecord? {
        try requireCurrentAccountOperation(operation)
        guard route.userID == operation.ownerID else { throw CancellationError() }
        var copy = route
        let id = UUID()
        let now = Date().ISO8601Format()
        copy = OrbitRouteRecord(
            id: id,
            userID: operation.ownerID,
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
        await persistUpsert(
            copy,
            table: "orbit_routes",
            onConflict: "user_id,client_idempotency_key",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        return copy
    }

    func saveOrbitShoe(
        id: UUID? = nil,
        name: String,
        brand: String,
        firstUseDate: Date,
        surfaces: [String],
        notes: String,
        archived: Bool = false,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        let identifier = id ?? UUID()
        let existing = data.orbitShoes.first {
            $0.id == identifier && $0.userID == operation.ownerID
        }
        if id != nil, existing == nil { throw CancellationError() }
        let now = Date().ISO8601Format()
        let shoe = OrbitShoe(
            id: identifier,
            userID: operation.ownerID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            firstUseDate: firstUseDate.apexDateKey,
            preferredSurfaces: surfaces,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            archived: archived,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        data.orbitShoes.removeAll {
            $0.id == identifier && $0.userID == operation.ownerID
        }
        data.orbitShoes.append(shoe)
        await persistUpsert(
            shoe,
            table: "orbit_shoes",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func archiveOrbitShoe(
        _ shoe: OrbitShoe,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard shoe.userID == operation.ownerID else { throw CancellationError() }
        try await saveOrbitShoe(
            id: shoe.id,
            name: shoe.name,
            brand: shoe.brand,
            firstUseDate: ISO8601DateFormatter.apexDateOnly.date(from: shoe.firstUseDate) ?? .now,
            surfaces: shoe.preferredSurfaces,
            notes: shoe.notes,
            archived: true,
            operation: operation
        )
        try requireCurrentAccountOperation(operation)
    }

    func saveOrbitSegment(
        route: OrbitRouteRecord,
        name: String,
        startDistanceM: Int,
        endDistanceM: Int,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard route.userID == operation.ownerID,
              endDistanceM > startDistanceM else { throw CancellationError() }
        let now = Date().ISO8601Format()
        let segment = OrbitSegment(
            id: UUID(), userID: operation.ownerID, routeID: route.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            startDistanceM: max(0, startDistanceM),
            endDistanceM: min(route.distanceM, endDistanceM),
            createdAt: now, updatedAt: now
        )
        data.orbitSegments.append(segment)
        await persistUpsert(
            segment,
            table: "orbit_segments",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func saveOrbitPosterMetadata(
        run: OrbitRunRecord,
        style: String,
        privacyTrimM: Int,
        includeHeartRate: Bool,
        note: String,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard run.userID == operation.ownerID else { throw CancellationError() }
        let poster = OrbitPoster(
            id: UUID(), userID: operation.ownerID, runID: run.id,
            style: style, privacyTrimM: max(0, privacyTrimM),
            includeHeartRate: includeHeartRate,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date().ISO8601Format()
        )
        data.orbitPosters.insert(poster, at: 0)
        await persistUpsert(
            poster,
            table: "orbit_posters",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    private func adaptCampaignAfterRun(
        _ run: OrbitRunRecord,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard run.userID == operation.ownerID else { throw CancellationError() }
        guard let campaignSessionID = run.campaignSessionID,
              let completedSession = data.orbitCampaignSessions.first(where: {
                  $0.id == campaignSessionID && $0.userID == operation.ownerID
              }),
              let campaign = data.orbitCampaigns.first(where: {
                  $0.id == completedSession.campaignID && $0.userID == operation.ownerID
              })
        else { return }
        let currentSessions = data.orbitCampaignSessions.filter {
            $0.campaignID == campaign.id && $0.userID == operation.ownerID
        }
        let bundle = OrbitCampaignEngine.adaptAfterRun(
            campaign: campaign,
            sessions: currentSessions,
            run: run
        )
        guard bundle.campaign != campaign || bundle.sessions != currentSessions else { return }
        try await saveCampaignBundle(
            bundle.campaign,
            sessions: bundle.sessions,
            operation: operation
        )
        try requireCurrentAccountOperation(operation)
    }

    private func integrateOrbitRun(
        _ run: OrbitRunRecord,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let profile,
              profile.userID == operation.ownerID,
              run.userID == operation.ownerID else { throw CancellationError() }
        let distanceKM = max(0, (run.metrics["distance_m"]?.numberValue ?? 0) / 1_000)
        let durationMinutes = max(1, Int(((run.metrics["moving_s"]?.numberValue ?? 0) / 60).rounded()))
        let id = APEXStableID.scopedUUID(
            namespace: "activity-log:orbit:\(run.id.uuidString.lowercased())",
            date: run.localDate,
            userID: operation.ownerID
        )
        let activity = ActivityLog(
            id: id, userID: operation.ownerID, date: run.localDate,
            typeID: "jog-run", quantity: 1,
            durationMinutes: durationMinutes, distanceKM: distanceKM,
            watchKcal: nil,
            computedKcal: ((data.weighedProfile()?.weightKG ?? profile.weightKG) * distanceKM).rounded(),
            source: "orbit", reconciled: true,
            createdAt: run.createdAt, updatedAt: run.updatedAt
        )
        data.activityLogs = OrbitIntegrations.reconciledActivityLogs(
            existing: data.activityLogs,
            generated: activity
        )
        await persistUpsert(
            activity,
            table: "activity_logs",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)

        let healthAlreadyRepresentsRun = OrbitIntegrations.healthWorkoutRepresentsRun(
            data.importedActivities,
            ownerID: operation.ownerID,
            localDate: run.localDate,
            durationMinutes: durationMinutes,
            startedAt: run.startedAt
        )
        if healthAlreadyRepresentsRun == false {
            let importedID = APEXStableID.orbitUUID(
                userID: operation.ownerID,
                key: "imported:\(run.id.uuidString.lowercased())"
            )
            let imported = ImportedActivity(
                id: importedID, userID: operation.ownerID, date: run.localDate,
                kind: "endurance",
                activity: "APEX Orbit: \(run.mission.replacingOccurrences(of: "_", with: " "))",
                durationMinutes: durationMinutes,
                source: "APEX Orbit"
            )
            data.importedActivities.removeAll { $0.id == importedID }
            data.importedActivities.append(imported)
            await persistUpsert(
                imported,
                table: "imported_activities",
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }

        try requireCurrentAccountOperation(operation)
        let dayLogs = data.activityLogs.filter {
            $0.userID == operation.ownerID && $0.date == run.localDate
        }
        let targets = EnergyEngine.targets(
            profile: data.weighedProfile() ?? profile,
            logs: dayLogs,
            catalog: data.activityTypes,
            planContext: NutritionGoalPolicy.context(from: data.settings),
            settings: data.settings,
            wearableActiveCalories: WearableActivityRecord.activeCalories(
                on: run.localDate,
                settings: data.settings,
                ownerID: operation.ownerID
            )
        )
        let existing = data.dailyLogs.first {
            $0.userID == operation.ownerID && $0.date == run.localDate
        }
        let daily = DailyLog(
            id: existing?.id ?? APEXStableID.scopedUUID(
                namespace: "daily-log",
                date: run.localDate,
                userID: operation.ownerID
            ),
            userID: operation.ownerID, date: run.localDate,
            kcal: existing?.kcal, proteinG: existing?.proteinG,
            fatG: existing?.fatG, carbsG: existing?.carbsG,
            waterL: existing?.waterL ?? 0,
            estimatedTDEE: targets.tdee, computedPAL: targets.pal,
            activityMode: "precise", weightKG: existing?.weightKG,
            nutritionSource: existing?.nutritionSource ?? "manual",
            manualKcal: existing?.manualKcal, manualProteinG: existing?.manualProteinG,
            manualFatG: existing?.manualFatG, manualCarbsG: existing?.manualCarbsG
        )
        await updateDailyLog(
            daily,
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    private func saveCampaignBundle(
        _ campaign: OrbitCampaign,
        sessions: [OrbitCampaignSession],
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard campaign.userID == operation.ownerID,
              sessions.allSatisfy({ $0.userID == operation.ownerID }) else {
            throw CancellationError()
        }
        data.orbitCampaigns.removeAll { $0.id == campaign.id }
        data.orbitCampaigns.insert(campaign, at: 0)
        let ids = Set(sessions.map(\.id))
        data.orbitCampaignSessions.removeAll { ids.contains($0.id) }
        data.orbitCampaignSessions.append(contentsOf: sessions)
        await persistUpsert(
            campaign,
            table: "orbit_campaigns",
            onConflict: "user_id,client_idempotency_key",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
        for item in sessions {
            await persistUpsert(
                item,
                table: "orbit_campaign_sessions",
                ownerID: operation.ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
    }

    // Save a custom session. Saving the same weekday twice replaces that day
    // rather than stacking a second one, matching the web builder.
    @discardableResult
    func installRecoveryPlan(
        target: RecoveryPlanner.Target,
        source: RecoveryPlanner.Source,
        startDate: String,
        operation: AccountOperationLease
    ) async throws -> Int {
        try requireCurrentAccountOperation(operation)
        guard coachClientPolicy.canCreateCustomWorkouts else {
            if accountOperationIsCurrent(operation) {
                alertMessage = LanguageState.shared.text("Ask your coach to add recovery sessions to your plan.")
            }
            return 0
        }
        guard let profile, profile.userID == operation.ownerID else {
            throw CancellationError()
        }
        let ownerID = operation.ownerID
        let result = RecoveryPlanner.build(
            data: data,
            ownerID: ownerID,
            startDate: startDate,
            target: target,
            source: source
        )
        guard !result.days.isEmpty else {
            if accountOperationIsCurrent(operation) {
                alertMessage = LanguageState.shared.text("Build or restore a current Fitness Plan before adding recovery sessions.")
            }
            return 0
        }
        guard result.days.allSatisfy({ $0.userID == ownerID }),
              result.exercises.allSatisfy({ $0.userID == ownerID }) else {
            throw CancellationError()
        }

        let usedDayIDs = Set(data.workoutSessions
            .filter { $0.userID == ownerID }
            .map(\.programDayID))
        let deactivated = RecoveryPlanner.futureRowsToDeactivate(
            data.programDays.filter { $0.userID == ownerID },
            ownerID: ownerID,
            target: target,
            today: startDate,
            protectedDayIDs: usedDayIDs
        )
        for row in deactivated {
            if let index = data.programDays.firstIndex(where: {
                $0.id == row.id && $0.userID == ownerID
            }) {
                data.programDays[index] = row
            }
        }
        data.programDays.append(contentsOf: result.days)
        data.exercises.append(contentsOf: result.exercises)

        for row in deactivated {
            await persistUpsert(
                row,
                table: "program_days",
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        for row in result.days {
            await persistUpsert(
                row,
                table: "program_days",
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        for row in result.exercises {
            await persistUpsert(
                row,
                table: "exercises",
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            try requireCurrentAccountOperation(operation)
        }
        try requireCurrentAccountOperation(operation)
        alertMessage = LanguageState.shared.text("Recovery sessions added to your calendar.")
        return result.days.count
    }

    func saveCustomWorkout(
        name: String,
        weekday: Int,
        estimatedMinutes: Int,
        sessionMode: WorkoutSessionMode,
        picks: [CustomWorkoutBuilder.Pick],
        editingDayID: UUID? = nil,
        confirmedReplacementDayIDs: Set<UUID> = [],
        operation: AccountOperationLease
    ) async throws -> CustomWorkoutLifecycle.SaveOutcome {
        try requireCurrentAccountOperation(operation)
        guard coachClientPolicy.canCreateCustomWorkouts else {
            if accountOperationIsCurrent(operation) {
                alertMessage = LanguageState.shared.text("Coach-sponsored accounts follow the coach plan. An individual subscription keeps custom workouts available.")
            }
            return .denied
        }
        guard let mutationToken = beginCustomWorkoutMutation() else { return .denied }
        defer { finishCustomWorkoutMutation(mutationToken) }
        guard let profile, profile.userID == operation.ownerID else {
            throw CancellationError()
        }
        let userID = operation.ownerID

        let change: CustomWorkoutLifecycle.SaveChange
        do {
            change = try CustomWorkoutLifecycle.prepareSave(
                in: data,
                ownerID: userID,
                request: CustomWorkoutLifecycle.SaveRequest(
                    name: name,
                    weekday: weekday,
                    estimatedMinutes: estimatedMinutes,
                    sessionMode: sessionMode,
                    picks: picks,
                    editingDayID: editingDayID,
                    confirmedReplacementDayIDs: confirmedReplacementDayIDs
                )
            )
        } catch CustomWorkoutLifecycle.Error.replacementConfirmationRequired(let dayIDs) {
            return .replacementConfirmationRequired(dayIDs)
        }

        let remoteBundle: (parent: OfflineOperation, dependents: [OfflineOperation])?
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            remoteBundle = nil
        } else {
            let parent = try OfflineOperation.upsert(
                change.program,
                table: "programs",
                onConflict: nil
            )
            var dependents = try change.deactivatedDays.map {
                try OfflineOperation.upsert($0, table: "program_days", onConflict: nil)
            }
            dependents.append(
                try OfflineOperation.upsert(change.day, table: "program_days", onConflict: nil)
            )
            dependents.append(contentsOf: try change.exercises.map {
                try OfflineOperation.upsert($0, table: "exercises", onConflict: nil)
            })
            dependents.append(contentsOf: change.staleExerciseIDs.map {
                OfflineOperation.delete(table: "exercises", id: $0)
            })
            remoteBundle = (parent, dependents)
        }

        /* Persist a delta merged over the latest observable dashboard. If an
           unrelated same-account mutation lands while disk or outbox I/O is
           suspended, repeat against that newer snapshot instead of publishing
           stale nutrition, hydration, Health or Avatar state. */
        let committed = try await CustomWorkoutLifecycle.persistMutation(
            snapshot: { (self.dashboardMutationRevision, self.data) },
            merge: { change.merging(into: $0) },
            requireCurrent: { try self.requireCurrentAccountOperation(operation) },
            saveDashboard: { proposed in
                try await self.offlineStore.saveDashboard(proposed, for: userID)
            },
            enqueue: {
                if let remoteBundle {
                    try await self.offlineStore.enqueue(
                        parent: remoteBundle.parent,
                        dependents: remoteBundle.dependents,
                        for: userID
                    )
                }
            }
        )
        /* There is deliberately no suspension between the stable revision
           check above and publication here. */
        try requireCurrentAccountOperation(operation)
        data = committed
        let count = try? await offlineStore.pendingOperations(for: userID).count
        if accountOperationIsCurrent(operation), let count {
            pendingSyncCount = count
        }
        Task { @MainActor [weak self] in
            guard let self, self.accountOperationIsCurrent(operation) else { return }
            await self.flushPendingChanges(for: userID)
        }
        return .saved
    }

    @discardableResult
    func archiveCustomWorkout(
        dayID: UUID,
        operation: AccountOperationLease
    ) async throws -> Bool {
        try requireCurrentAccountOperation(operation)
        guard coachClientPolicy.canCreateCustomWorkouts else {
            if accountOperationIsCurrent(operation) {
                alertMessage = LanguageState.shared.text("Coach-sponsored accounts follow the coach plan. An individual subscription keeps custom workouts available.")
            }
            return false
        }
        guard let mutationToken = beginCustomWorkoutMutation() else { return false }
        defer { finishCustomWorkoutMutation(mutationToken) }
        let change = try CustomWorkoutLifecycle.prepareArchive(
            dayID: dayID,
            in: data,
            ownerID: operation.ownerID
        )
        let remoteOperation: OfflineOperation?
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            remoteOperation = nil
        } else {
            remoteOperation = try OfflineOperation.upsert(
                change.day,
                table: "program_days",
                onConflict: nil
            )
        }
        let committed = try await CustomWorkoutLifecycle.persistMutation(
            snapshot: { (self.dashboardMutationRevision, self.data) },
            merge: { change.merging(into: $0) },
            requireCurrent: { try self.requireCurrentAccountOperation(operation) },
            saveDashboard: { proposed in
                try await self.offlineStore.saveDashboard(proposed, for: operation.ownerID)
            },
            enqueue: {
                if let remoteOperation {
                    try await self.offlineStore.enqueue(remoteOperation, for: operation.ownerID)
                }
            }
        )
        try requireCurrentAccountOperation(operation)
        data = committed
        let count = try? await offlineStore.pendingOperations(for: operation.ownerID).count
        if accountOperationIsCurrent(operation), let count {
            pendingSyncCount = count
        }
        Task { @MainActor [weak self] in
            guard let self, self.accountOperationIsCurrent(operation) else { return }
            await self.flushPendingChanges(for: operation.ownerID)
        }
        return true
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
        draftID: UUID,
        editing sessionID: UUID? = nil,
        operation: AccountOperationLease
    ) async throws -> Bool {
        try requireCurrentAccountOperation(operation)
        guard coachClientPolicy.canCreateCustomWorkouts else {
            if accountOperationIsCurrent(operation) {
                alertMessage = LanguageState.shared.text("Coach-sponsored accounts follow the coach plan. An individual subscription keeps custom workouts available.")
            }
            return false
        }
        guard let profile, profile.userID == operation.ownerID else {
            throw CancellationError()
        }
        let userID = operation.ownerID

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
        guard valid, WorkoutReceipt.canComplete(on: date) else { return false }
        let usable = exercises

        let (program, day) = ManualWorkout.receiptParents(in: data, ownerID: userID)
        let receiptID = sessionID ?? draftID
        let existingSession = data.workoutSessions.first { $0.id == receiptID && $0.userID == userID }
        if sessionID != nil && existingSession == nil { return false }
        if let existingSession, ManualWorkout.title(fromNotes: existingSession.notes) == nil { return false }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let receiptDay = ISO8601DateFormatter.apexDateOnly.date(from: date) else { return false }
        let localFinish = copiedClock(from: formatter.string(from: .now), onto: receiptDay)
        let finish = existingSession?.completedAt ?? formatter.string(from: localFinish)

        let workout = WorkoutSession(
            id: receiptID,
            userID: userID,
            date: date,
            programDayID: existingSession?.programDayID ?? day.id,
            isLite: existingSession?.isLite ?? false,
            isDeload: existingSession?.isDeload ?? false,
            isEventRecovery: existingSession?.isEventRecovery ?? false,
            completed: true,
            qualityScore: 1,
            startedAt: existingSession?.startedAt,
            completedAt: finish,
            notes: ManualWorkout.notes(title: title) + (existingSession?.notes
                .components(separatedBy: "\n").filter { $0.hasPrefix(WorkoutReceipt.timingMetadataPrefix) }
                .map { "\n" + $0 }.joined() ?? "")
        )

        let existingLogs = existingSession
            .map { session in
                data.workoutLogs.filter {
                    $0.userID == userID && $0.sessionID == session.id
                }
            } ?? []
        /* Chronology is the durable identity here: give every exercise its own
           minute so a movement repeated later in the session never collapses
           into its earlier occurrence. */
        let existingTimes = existingLogs.compactMap { formatter.date(from: $0.createdAt)?.timeIntervalSince1970 }
        let base = existingTimes.min() ?? localFinish.timeIntervalSince1970 - Double(max(0, usable.count - 1)) * 60

        let proposed = ManualWorkout.logs(
            userID: userID,
            sessionID: workout.id,
            exercises: usable,
            base: Date(timeIntervalSince1970: base)
        )

        let reconciled = ManualWorkout.reconcile(existing: existingLogs, next: proposed)

        func applyingReceipt(to current: DashboardData) -> DashboardData {
            var result = current
            if workout.programDayID == day.id {
                if !result.programs.contains(where: { $0.id == program.id }) { result.programs.append(program) }
                if !result.programDays.contains(where: { $0.id == day.id }) { result.programDays.append(day) }
            }
            result.workoutSessions.removeAll { $0.userID == userID && $0.id == workout.id }
            result.workoutSessions.append(workout)
            result.workoutLogs.removeAll { $0.userID == userID && $0.sessionID == workout.id }
            result.workoutLogs.append(contentsOf: reconciled.logs)
            return result
        }

        if !isDeveloperSandbox && !APEXRuntimeEnvironment.usesLocalUITestFixture() {
            var writes: [OfflineOperation] = []
            if workout.programDayID == day.id {
                writes.append(try .upsert(program, table: "programs", onConflict: nil))
                writes.append(try .upsert(day, table: "program_days", onConflict: nil))
            }
            writes.append(try .upsert(workout, table: "workout_sessions", onConflict: nil))
            writes += try reconciled.logs.map { try .upsert($0, table: "workout_logs", onConflict: nil) }
            writes += reconciled.staleIDs.map { .delete(table: "workout_logs", id: $0) }
            try await offlineStore.enqueue(parent: writes[0], dependents: Array(writes.dropFirst()), for: userID)
            try requireCurrentAccountOperation(operation)
            try await offlineStore.saveDashboard(applyingReceipt(to: data), for: userID)
            try requireCurrentAccountOperation(operation)
        }
        data = applyingReceipt(to: data)
        if !isDeveloperSandbox && !APEXRuntimeEnvironment.usesLocalUITestFixture() {
            workoutSyncTask = Task { @MainActor [weak self] in
                guard let self, self.accountOperationIsCurrent(operation) else { return }
                await self.flushPendingChanges(for: userID)
            }
        }
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
    func installInductionPlan(
        _ input: TrainingInduction.Input,
        operation: AccountOperationLease
    ) async {
        if isDeveloperSandbox {
            guard accountOperationIsCurrent(operation), var settings = data.settings else { return }
            settings = TrainingInduction.protectingOriginalProgramme(settings, in: data)
            if TrainingInduction.hasRestorableOverlay(in: data) {
                settings = TrainingInduction.invalidatingPlanMetadata(settings,
                    additionalDayIDs: TrainingInduction.legacyGeneratedDayIDs(in: data, userID: operation.ownerID))
            }
            let plan = TrainingInduction.generate(userID: operation.ownerID, input: input,
                existingPrograms: data.programs, generationRevision: TrainingInduction.generationRevision(settings))
            settings = TrainingInduction.markingPendingPlan(settings, plan: plan)
            settings = TrainingInduction.Submission.answered(input).applyingAccountMetadata(to: settings, plan: plan)
            applyInductionPlan(plan, settings: settings)
            return
        }
        guard accountOperationIsCurrent(operation) else { return }
        guard !isBusy else { return }
        isBusy = true
        defer {
            if accountOperationIsCurrent(operation) { isBusy = false }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-first-run"),
           var settings = data.settings,
           settings.userID == operation.ownerID {
            settings = TrainingInduction.protectingOriginalProgramme(settings, in: data)
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
            guard accountOperationIsCurrent(operation) else { return }
            alertMessage = "Sign in again to build your plan."
            return
        }
        guard accountOperationIsCurrent(operation), userID == operation.ownerID else { return }
        do {
            var settings = try await service.createSettingsIfNeeded(userID: userID)
                .rebound(to: userID)
            try requireCurrentAccountOperation(operation)
            settings = TrainingInduction.protectingOriginalProgramme(settings, in: data)

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
                try requireCurrentAccountOperation(operation)
                data.settings = settings
                try await saveLocalSnapshot(operation: operation)
            }
            let plan = TrainingInduction.generate(
                userID: userID,
                input: input,
                existingPrograms: data.programs,
                generationRevision: TrainingInduction.generationRevision(settings)
            )
            settings = TrainingInduction.markingPendingPlan(settings, plan: plan)
            try await service.upsert(settings, table: "settings", onConflict: "user_id")
            try requireCurrentAccountOperation(operation)
            data.settings = settings
            try await saveLocalSnapshot(operation: operation)
            try await service.saveInductionPlan(plan)
            try requireCurrentAccountOperation(operation)
            settings = TrainingInduction.Submission.answered(input)
                .applyingAccountMetadata(to: settings, plan: plan)
            try await service.upsert(settings, table: "settings", onConflict: "user_id")
            try requireCurrentAccountOperation(operation)
            applyInductionPlan(plan, settings: settings)
            try await saveLocalSnapshot(operation: operation)
        } catch is CancellationError {
            return
        } catch {
            guard accountOperationIsCurrent(operation) else { return }
            alertMessage = error.localizedDescription
        }
    }

    /// Finish the account boundary before the briefing opens Simple Mode.
    /// A settings-only Skip remains profileless; only the durable committed
    /// plan it later installs is sufficient evidence to repair the account.
    /// Deferring this until the final button also keeps the briefing stable
    /// while the portal changes from a settings identity to a full profile.
    func prepareCommittedPlanForPortal(operation: AccountOperationLease) async -> Bool {
        guard accountOperationIsCurrent(operation) else { return false }
        guard !isBusy else { return false }
        guard data.profile == nil else { return data.profile?.userID == operation.ownerID }
        guard let settings = data.settings,
              settings.userID == operation.ownerID,
              let bootstrap = TrainingInduction.missingProfileBootstrap(
                  in: data,
                  authenticatedUserID: settings.userID
              )
        else {
            alertMessage = "Your plan is not fully synced yet. Please try again."
            return false
        }

        isBusy = true
        defer {
            if accountOperationIsCurrent(operation) { isBusy = false }
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-apex-ui-test-first-run") {
            var profile = APEXDebugFixture.dashboard(userID: bootstrap.userID).profile!
            profile.goal = Goal(rawValue: bootstrap.goal) ?? .maintain
            data.profile = profile
            return true
        }
        #endif

        if isDeveloperSandbox {
            var sample = DeveloperSandboxSamples.dashboard(ownerID: bootstrap.userID, name: "Sample").profile!
            sample.goal = Goal(rawValue: bootstrap.goal) ?? .maintain
            data.profile = sample
            return true
        }
        guard let authenticatedUserID = await service.currentUserID(),
              authenticatedUserID == bootstrap.userID,
              authenticatedUserID == operation.ownerID,
              accountOperationIsCurrent(operation)
        else {
            if accountOperationIsCurrent(operation) {
                alertMessage = "Sign in again to open your plan."
            }
            return false
        }
        do {
            try await refreshDashboard(expectedUserID: authenticatedUserID)
            try requireCurrentAccountOperation(operation)
            guard data.profile?.userID == authenticatedUserID else {
                alertMessage = "Your account setup is not complete yet. Please try again."
                return false
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard accountOperationIsCurrent(operation) else { return false }
            alertMessage = error.localizedDescription
            return false
        }
    }

    private func applyInductionPlan(
        _ plan: TrainingInduction.GeneratedPlan,
        settings: UserSettings
    ) {
        data = TrainingInduction.applyingGeneratedPlan(plan, settings: settings, to: data)
    }

    /// Puts the original programme back and removes only generated overlay rows.
    func restoreOriginalProgramme(operation: AccountOperationLease) async {
        guard accountOperationIsCurrent(operation) else { return }
        guard !isBusy else { return }
        isBusy = true
        defer {
            if accountOperationIsCurrent(operation) { isBusy = false }
        }
        guard let userID = profile?.userID ?? data.settings?.userID,
              userID == operation.ownerID,
              let restoration = TrainingInduction.restoration(in: data, userID: userID),
              let restoredSettings = restoration.dashboard.settings else { return }
        do {
            if !isDeveloperSandbox { try await service.upsert(restoredSettings, table: "settings", onConflict: "user_id") }
            try requireCurrentAccountOperation(operation)
            data = restoration.dashboard
            data.settings = restoredSettings
            try await saveLocalSnapshot(operation: operation)
        } catch is CancellationError {
            return
        } catch {
            guard accountOperationIsCurrent(operation) else { return }
            alertMessage = error.localizedDescription
        }
    }

    /// Store a rewritten predefined list, keyed so an edit to one meal on one
    /// goal never quietly rewrites the others. An emptied list falls back to
    /// the protocol default.
    func saveMealProtocolOverride(
        key: String,
        lines: [String],
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard var settings = data.settings?.rebound(to: operation.ownerID) else {
            throw APEXServiceError.configurationMissing
        }
        var overrides = settings.addons["meal_protocol_overrides"]?.objectValue ?? [:]
        if lines.isEmpty {
            overrides.removeValue(forKey: key)
        } else {
            overrides[key] = .array(lines.map { .string($0) })
        }
        settings.addons["meal_protocol_overrides"] = .object(overrides)
        data.settings = settings
        await persistUpsert(
            settings,
            table: "settings",
            onConflict: "user_id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    private func verifiedPersistenceOwnerID(_ expectedOwnerID: UUID? = nil) -> UUID? {
        guard let ownerID = expectedOwnerID ?? data.profile?.userID ?? data.settings?.userID,
              TrainingInduction.belongsToAccount(data, userID: ownerID) else {
            return nil
        }
        return ownerID
    }

    func recordFitnessEvidence(
        _ evidence: NormalizedFitnessEvidence,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        guard let ownerID = UUID(uuidString: evidence.userID),
              ownerID == operation.ownerID else {
            throw FitnessEvidenceRecordingError.accountMismatch
        }
        guard evidence.confidence == .low,
              evidence.source == .structuredSelfReport
                || evidence.source == .userEnteredExternalResult else {
            throw FitnessEvidenceRecordingError.trustedSourceRequiresIngestion
        }

        if isDeveloperSandbox {
            mergeFitnessEvidenceRecord(localFitnessEvidenceRecord(evidence, ownerID: ownerID))
            return
        }
        let params = RecordUserFitnessEvidenceParameters(evidence)
        let offlineOperation = try OfflineOperation.rpc("record_user_fitness_evidence", params: params)

        #if DEBUG
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            try requireCurrentAccountOperation(operation)
            mergeFitnessEvidenceRecord(localFitnessEvidenceRecord(evidence, ownerID: ownerID))
            try await saveLocalSnapshot(operation: operation)
            return
        }
        #endif

        do {
            let record = try await service.recordUserFitnessEvidence(evidence)
            try requireCurrentAccountOperation(operation)
            guard record.userID == ownerID else {
                throw FitnessEvidenceRecordingError.accountMismatch
            }
            mergeFitnessEvidenceRecord(record)
            try await saveLocalSnapshot(operation: operation)
            try requireCurrentAccountOperation(operation)
            lastSyncAt = .now
        } catch let evidenceError as FitnessEvidenceRecordingError {
            try requireCurrentAccountOperation(operation)
            try? await offlineStore.recordFailure(
                offlineOperation,
                reason: String(describing: evidenceError),
                for: ownerID
            )
            try requireCurrentAccountOperation(operation)
            let failedCount = try? await offlineStore.failedOperations(for: ownerID).count
            try requireCurrentAccountOperation(operation)
            failedSyncCount = failedCount ?? failedSyncCount + 1
            throw evidenceError
        } catch {
            try requireCurrentAccountOperation(operation)
            switch SyncFailurePolicy.classify(error) {
            case .transient, .authenticationRequired:
                try await offlineStore.enqueue(offlineOperation, for: ownerID)
                try requireCurrentAccountOperation(operation)
                mergeFitnessEvidenceRecord(localFitnessEvidenceRecord(evidence, ownerID: ownerID))
                try await saveLocalSnapshot(operation: operation)
                let pendingCount = try? await offlineStore.pendingOperations(for: ownerID).count
                try requireCurrentAccountOperation(operation)
                pendingSyncCount = pendingCount ?? pendingSyncCount + 1
            case .permanent:
                try? await offlineStore.recordFailure(
                    offlineOperation,
                    reason: error.localizedDescription,
                    for: ownerID
                )
                try requireCurrentAccountOperation(operation)
                let failedCount = try? await offlineStore.failedOperations(for: ownerID).count
                try requireCurrentAccountOperation(operation)
                failedSyncCount = failedCount ?? failedSyncCount + 1
                throw error
            }
        }
    }

    func saveBaselineCalibration(
        _ answers: BaselineCalibrationAnswers,
        measuredAt: Date = .now,
        operation: AccountOperationLease
    ) async throws -> OnboardingBaselineBands {
        try requireCurrentAccountOperation(operation)
        let ownerID = operation.ownerID
        let importedAt = Date().ISO8601Format()
        let measuredAtString = measuredAt.ISO8601Format()
        guard case .accepted(let evaluation) = BaselineCalibrationAssessment.evaluate(
            userID: ownerID.uuidString,
            measuredAt: measuredAtString,
            importedAt: importedAt,
            answers: answers
        ) else {
            throw BaselineCalibrationSaveError.invalidAssessment
        }
        for draft in evaluation.evidence {
            try requireCurrentAccountOperation(operation)
            guard case .accepted(let evidence) = FitnessEvidenceNormalizer.normalize(
                draft,
                admission: .user,
                referenceNow: importedAt
            ) else {
                throw BaselineCalibrationSaveError.invalidEvidence
            }
            try await recordFitnessEvidence(evidence, operation: operation)
        }
        try requireCurrentAccountOperation(operation)
        return evaluation.bands
    }

    func saveManualCalibrationResult(
        metric: FitnessEvidenceMetric,
        value: Double,
        unit: String,
        declaredSource: String,
        measuredAt: Date,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        let ownerID = operation.ownerID
        let importedAt = Date().ISO8601Format()
        guard case .accepted(let evidence) = BaselineCalibrationAssessment.manualEvidence(
            userID: ownerID.uuidString,
            metric: metric,
            value: value,
            unit: unit,
            declaredSource: declaredSource,
            measuredAt: measuredAt.ISO8601Format(),
            importedAt: importedAt
        ) else {
            throw BaselineCalibrationSaveError.invalidEvidence
        }
        try await recordFitnessEvidence(evidence, operation: operation)
    }

    func saveManualDEXACalibrationResult(
        bodyFatPercentage: Double?,
        restingMetabolicRate: Double?,
        declaredSource: String,
        measuredAt: Date,
        operation: AccountOperationLease
    ) async throws -> [NormalizedFitnessEvidence] {
        try requireCurrentAccountOperation(operation)
        let ownerID = operation.ownerID
        let importedAt = Date().ISO8601Format()
        guard case .accepted(let evidence) = BaselineCalibrationAssessment.manualDEXAEvidence(
            userID: ownerID.uuidString,
            bodyFatPercentage: bodyFatPercentage,
            restingMetabolicRate: restingMetabolicRate,
            declaredSource: declaredSource,
            measuredAt: measuredAt.ISO8601Format(),
            importedAt: importedAt
        ) else {
            throw BaselineCalibrationSaveError.invalidEvidence
        }
        for item in evidence {
            try requireCurrentAccountOperation(operation)
            try await recordFitnessEvidence(item, operation: operation)
        }

        if ProfileIntegrityPolicy.isBodyFatEnergyEligible(
            value: bodyFatPercentage,
            source: .dexa
        ) {
            try await updateProfile({ profile in
                profile.bodyFatPercent = bodyFatPercentage
                profile.bodyFatSource = .dexa
                profile.bodyFatMeasuredAt = measuredAt.ISO8601Format()
            }, operation: operation)
        }

        if let validatedRMR = RestingEnergyPolicy.validated(restingMetabolicRate) {
            try await updateSettings({ settings in
                RestingEnergyPolicy.storeDEXAReportEstimate(
                    validatedRMR,
                    in: &settings.addons
                )
            }, operation: operation)
        }
        try requireCurrentAccountOperation(operation)
        return evidence
    }

    func connectHealthForBaselineCalibration(operation: AccountOperationLease) async -> Bool {
        if isDeveloperSandbox { return false }
        return await connectHealth(operation: operation)
    }

    private func mergeFitnessEvidenceRecord(_ record: FitnessEvidenceRecord) {
        var records = data.fitnessEvidence ?? []
        records.removeAll {
            $0.id == record.id || $0.clientIdempotencyKey == record.clientIdempotencyKey
        }
        records.insert(record, at: 0)
        data.fitnessEvidence = records
    }

    private func localFitnessEvidenceRecord(
        _ evidence: NormalizedFitnessEvidence,
        ownerID: UUID
    ) -> FitnessEvidenceRecord {
        FitnessEvidenceRecord(
            id: UUID(),
            userID: ownerID,
            metric: evidence.metric,
            value: evidence.value,
            unit: evidence.unit,
            source: evidence.source,
            protocol: evidence.protocol,
            device: evidence.device,
            measuredAt: evidence.measuredAt,
            importedAt: evidence.importedAt,
            confidence: evidence.confidence,
            metadata: evidence.metadata,
            supersedesID: evidence.supersedesID.flatMap(UUID.init(uuidString:)),
            clientIdempotencyKey: evidence.clientIdempotencyKey
        )
    }

    private func persistUpsert<T: Encodable & Sendable>(
        _ value: T,
        table: String,
        onConflict: String? = nil,
        ownerID: UUID? = nil,
        expectedAccountToken: UInt64? = nil,
        surfacePermanentFailure: Bool = true
    ) async {
        if isDeveloperSandbox { return }
        let persistenceOwnerID = verifiedPersistenceOwnerID(ownerID)
        if let expectedAccountToken {
            guard accountGeneration.accepts(expectedAccountToken),
                  verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID,
                  persistenceOwnerID != nil else { return }
        }
        #if DEBUG
        /* The authenticated first-run UI fixture is deliberately local. Once
           its missing profile is repaired, view tasks may save preferences or
           Health-derived defaults; allowing those calls to reach Supabase
           both violates the fixture boundary and covers the recovered screen
           with an irrelevant network alert. */
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            lastSyncAt = .now
            return
        }
        #endif
        if let persistenceOwnerID {
            let snapshot = data
            try? await offlineStore.saveDashboard(snapshot, for: persistenceOwnerID)
        }
        if let expectedAccountToken {
            guard accountGeneration.accepts(expectedAccountToken),
                  verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
        }
        do {
            try await service.upsert(value, table: table, onConflict: onConflict)
            if let expectedAccountToken {
                guard accountGeneration.accepts(expectedAccountToken),
                      verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
            }
            lastSyncAt = .now
        } catch {
            if let expectedAccountToken {
                guard accountGeneration.accepts(expectedAccountToken),
                      verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
            }
            guard let userID = persistenceOwnerID else { return }
            do {
                let operation = try OfflineOperation.upsert(value, table: table, onConflict: onConflict)
                switch SyncFailurePolicy.classify(error) {
                case .transient, .authenticationRequired:
                    try await offlineStore.enqueue(operation, for: userID)
                    if let expectedAccountToken {
                        guard accountGeneration.accepts(expectedAccountToken),
                              verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
                    }
                    let pendingCount = try? await offlineStore.pendingOperations(for: userID).count
                    if let expectedAccountToken {
                        guard accountGeneration.accepts(expectedAccountToken),
                              verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
                    }
                    pendingSyncCount = pendingCount ?? pendingSyncCount + 1
                    /* Silent, like the other offline saves. Working without a
                       connection is the feature, not an incident report. */
                case .permanent:
                    try await offlineStore.recordFailure(
                        operation,
                        reason: error.localizedDescription,
                        for: userID
                    )
                    if let expectedAccountToken {
                        guard accountGeneration.accepts(expectedAccountToken),
                              verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
                    }
                    let failedCount = try? await offlineStore.failedOperations(for: userID).count
                    if let expectedAccountToken {
                        guard accountGeneration.accepts(expectedAccountToken),
                              verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
                    }
                    failedSyncCount = failedCount ?? failedSyncCount + 1
                    if surfacePermanentFailure {
                        alertMessage = "APEX could not sync that change. Please try again after refreshing your account."
                    }
                }
            } catch {
                if let expectedAccountToken {
                    guard accountGeneration.accepts(expectedAccountToken),
                          verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
                }
                if surfacePermanentFailure {
                    alertMessage = "APEX could not preserve that change offline. \(error.localizedDescription)"
                }
            }
        }
    }

    private func persistDelete(
        table: String,
        id: UUID,
        ownerID: UUID? = nil,
        expectedAccountToken: UInt64? = nil
    ) async {
        if isDeveloperSandbox {
            await sandboxDeleteInFlight?()
            return
        }
        let persistenceOwnerID = verifiedPersistenceOwnerID(ownerID)
        if let expectedAccountToken {
            guard accountGeneration.accepts(expectedAccountToken),
                  verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID,
                  persistenceOwnerID != nil else { return }
        }
        #if DEBUG
        if isDeveloperSandbox || APEXRuntimeEnvironment.usesLocalUITestFixture() {
            lastSyncAt = .now
            return
        }
        #endif
        if let persistenceOwnerID {
            let snapshot = data
            try? await offlineStore.saveDashboard(snapshot, for: persistenceOwnerID)
        }
        if let expectedAccountToken {
            guard accountGeneration.accepts(expectedAccountToken),
                  verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
        }
        do {
            try await service.delete(table: table, id: id)
            if let expectedAccountToken {
                guard accountGeneration.accepts(expectedAccountToken),
                      verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
            }
            lastSyncAt = .now
        } catch {
            if let expectedAccountToken {
                guard accountGeneration.accepts(expectedAccountToken),
                      verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
            }
            guard let userID = persistenceOwnerID else { return }
            do {
                let operation = OfflineOperation.delete(table: table, id: id)
                switch SyncFailurePolicy.classify(error) {
                case .transient, .authenticationRequired:
                    try await offlineStore.enqueue(operation, for: userID)
                    if let expectedAccountToken {
                        guard accountGeneration.accepts(expectedAccountToken),
                              verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
                    }
                    let pendingCount = try? await offlineStore.pendingOperations(for: userID).count
                    if let expectedAccountToken {
                        guard accountGeneration.accepts(expectedAccountToken),
                              verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
                    }
                    pendingSyncCount = pendingCount ?? pendingSyncCount + 1
                    /* Silent, like the other offline saves. Working without a
                       connection is the feature, not an incident report. */
                case .permanent:
                    try await offlineStore.recordFailure(
                        operation,
                        reason: error.localizedDescription,
                        for: userID
                    )
                    if let expectedAccountToken {
                        guard accountGeneration.accepts(expectedAccountToken),
                              verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
                    }
                    let failedCount = try? await offlineStore.failedOperations(for: userID).count
                    if let expectedAccountToken {
                        guard accountGeneration.accepts(expectedAccountToken),
                              verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
                    }
                    failedSyncCount = failedCount ?? failedSyncCount + 1
                    alertMessage = "APEX could not sync that change. Please try again after refreshing your account."
                }
            } catch {
                if let expectedAccountToken {
                    guard accountGeneration.accepts(expectedAccountToken),
                          verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID else { return }
                }
                alertMessage = "APEX could not preserve that change offline. \(error.localizedDescription)"
            }
        }
    }

    private func persistStableMealDeletionSnapshot(
        operation: AccountOperationLease
    ) async throws {
        if isDeveloperSandbox { return }
        try requireCurrentAccountOperation(operation)
        _ = try await ConfirmedMealDeletionPersistence.persistMergedBeforePublishing(
            snapshot: { (self.dashboardMutationRevision, self.data) },
            merge: { $0 },
            persist: { latest in
                try self.requireCurrentAccountOperation(operation)
                try await self.offlineStore.saveDashboard(
                    latest,
                    for: operation.ownerID
                )
                try self.requireCurrentAccountOperation(operation)
            }
        )
    }

    private func saveLocalSnapshot(operation: AccountOperationLease) async throws {
        if isDeveloperSandbox { return }
        try requireCurrentAccountOperation(operation)
        let snapshot = data
        try? await offlineStore.saveDashboard(snapshot, for: operation.ownerID)
        try requireCurrentAccountOperation(operation)
    }

    private func recalculateLocalStructuredDay(
        _ date: String,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        StructuredNutritionDayProjection.apply(
            date: date,
            ownerID: operation.ownerID,
            to: &data
        )
        try await reconcileStructuredDayHydration(date, operation: operation)
    }

    private func reconcileStructuredDayHydration(
        _ date: String,
        operation: AccountOperationLease
    ) async throws {
        try requireCurrentAccountOperation(operation)
        if let resolvedDate = ISO8601DateFormatter.apexDateOnly.date(from: date) {
            await syncFoodHydrationEvent(
                on: resolvedDate,
                ownerID: operation.ownerID,
                operation: operation
            )
            try requireCurrentAccountOperation(operation)
        }
        if healthImportIsEnabled(operation: operation),
           HealthKitManager.shared.waterWriteState == .authorized,
           let resolvedDate = ISO8601DateFormatter.apexDateOnly.date(from: date) {
            let liters = foodHydrationLiters(on: resolvedDate)
            try requireCurrentAccountOperation(operation)
            try? await HealthKitManager.shared.syncFoodWater(
                liters: liters,
                on: resolvedDate,
                accountID: operation.ownerID
            )
            try requireCurrentAccountOperation(operation)
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

    private func considerWeeklyCalibration(operation: AccountOperationLease) async throws {
        try requireCurrentAccountOperation(operation)
        guard var profile, profile.userID == operation.ownerID else { return }
        guard let calibration = EnergyEngine.weeklyCalibration(profile: profile, data: data) else { return }
        let previous = profile.calibrationK
        profile.calibrationK = calibration.nextK
        profile.calibrationHistory.append(.init(
            appliedAt: Date().ISO8601Format(),
            previousK: previous,
            nextK: calibration.nextK,
            observedTDEE: calibration.observedTDEE,
            predictedTDEE: calibration.predictedTDEE,
            sampleDays: calibration.sampleDays
        ))
        profile.calibrationHistory = Array(profile.calibrationHistory.suffix(52))
        profile.updatedAt = Date().ISO8601Format()
        try requireCurrentAccountOperation(operation)
        data.profile = profile
        await persistUpsert(
            profile,
            table: "profile",
            onConflict: "user_id",
            ownerID: operation.ownerID,
            expectedAccountToken: operation.generation
        )
        try requireCurrentAccountOperation(operation)
    }

    func refreshFailedSyncOperations() async {
        if isDeveloperSandbox { return }
        guard let profile else {
            failedSyncOperations = []
            failedSyncCount = 0
            return
        }
        let ownerID = profile.userID
        let accountToken = accountGeneration.token
        let failures = (try? await offlineStore.failedOperations(for: ownerID)) ?? []
        guard accountGeneration.accepts(accountToken),
              verifiedPersistenceOwnerID(ownerID) == ownerID else { return }
        failedSyncOperations = failures
        failedSyncCount = failures.count
    }

    private func flushPendingChanges(for userID: UUID) async {
        guard syncDrainGate.begin(for: userID) else { return }
        repeat {
            await drainPendingChanges(for: userID)
        } while syncDrainGate.nextPass(for: userID)
    }

    private func drainPendingChanges(for userID: UUID) async {
        if isDeveloperSandbox { return }
        let accountToken = accountGeneration.token
        guard accountAccessAllowsPrivateWork(for: userID),
              accountGeneration.accepts(accountToken),
              verifiedPersistenceOwnerID(userID) == userID else { return }
        let requeuedAuthenticationFailures =
            (try? await offlineStore.requeueAuthenticationFailures(for: userID)) ?? 0
        guard accountGeneration.accepts(accountToken),
              verifiedPersistenceOwnerID(userID) == userID else { return }
        if requeuedAuthenticationFailures > 0 {
            let pendingCount = try? await offlineStore.pendingOperations(for: userID).count
            let failureCount = try? await offlineStore.failedOperations(for: userID).count
            guard accountGeneration.accepts(accountToken),
                  verifiedPersistenceOwnerID(userID) == userID else { return }
            pendingSyncCount = pendingCount ?? pendingSyncCount
            failedSyncCount = failureCount ?? failedSyncCount
        }

        guard let operations = try? await offlineStore.pendingOperations(for: userID) else { return }
        guard accountGeneration.accepts(accountToken),
              verifiedPersistenceOwnerID(userID) == userID else { return }
        pendingSyncCount = operations.count
        let report = await OfflineQueueDrainer.drain(
            operations,
            replay: { [weak self, service] operation in
                guard let self else { throw SyncAccountBoundaryError() }
                try await self.requireCurrentSyncAccount(ownerID: userID, token: accountToken)
                try await service.replay(operation)
                try await self.requireCurrentSyncAccount(ownerID: userID, token: accountToken)
            },
            remove: { [weak self, offlineStore] operation in
                guard let self else { throw SyncAccountBoundaryError() }
                try await self.requireCurrentSyncAccount(ownerID: userID, token: accountToken)
                try await offlineStore.removeOperation(operation.id, for: userID)
            },
            quarantine: { [weak self, offlineStore] operation, reason in
                guard let self else { throw SyncAccountBoundaryError() }
                try await self.requireCurrentSyncAccount(ownerID: userID, token: accountToken)
                try await offlineStore.quarantine(operation, reason: reason, for: userID)
            },
            refreshAuthentication: { [weak self, service] in
                guard let self else { throw SyncAccountBoundaryError() }
                try await self.requireCurrentSyncAccount(ownerID: userID, token: accountToken)
                try await service.refreshAuthenticationSession()
            },
            classify: { error in
                error is SyncAccountBoundaryError
                    ? .transient
                    : SyncFailurePolicy.classify(error)
            }
        )
        guard accountGeneration.accepts(accountToken),
              verifiedPersistenceOwnerID(userID) == userID else { return }
        let pendingCount = try? await offlineStore.pendingOperations(for: userID).count
        let failureCount = try? await offlineStore.failedOperations(for: userID).count
        guard accountGeneration.accepts(accountToken),
              verifiedPersistenceOwnerID(userID) == userID else { return }
        pendingSyncCount = pendingCount ?? max(
            0,
            operations.count - report.succeeded - report.quarantined
        )
        failedSyncCount = failureCount ?? failedSyncCount
        if report.succeeded > 0 { lastSyncAt = .now }
    }

    private func bindHealthBackgroundMonitoring(operation: AccountOperationLease) {
        if isDeveloperSandbox { return }
        guard accountAccessAllowsPrivateWork(for: operation.ownerID),
              healthImportIsEnabled(operation: operation) else { return }
        HealthKitManager.shared.startBackgroundMonitoring(
            ownerID: operation.ownerID
        ) { [weak self, operation] snapshot in
            await self?.applyHealthSnapshot(snapshot, operation: operation)
        }
    }

    private func retryPendingHydrationMutations(operation: AccountOperationLease) async {
        guard !Task.isCancelled,
              accountAccessAllowsPrivateWork(for: operation.ownerID),
              accountOperationIsCurrent(operation) else { return }
        var pending = pendingHydrationMutationRetries(ownerID: operation.ownerID)
            .filter { !hydrationMutationWasProcessed($0.mutation) }
        saveHydrationMutationRetries(pending, ownerID: operation.ownerID)
        let retryable = pending.filter { $0.attempts < 1 }
        for candidate in retryable {
            guard !Task.isCancelled,
                  accountAccessAllowsPrivateWork(for: operation.ownerID),
                  accountOperationIsCurrent(operation),
                  candidate.mutation.ownerID == operation.ownerID else { return }
            if let index = pending.firstIndex(where: {
                $0.mutation.id == candidate.mutation.id
            }) {
                pending[index].attempts += 1
                saveHydrationMutationRetries(pending, ownerID: operation.ownerID)
            }
            await handleHydrationMutation(candidate.mutation, operation: operation)
            pending = pendingHydrationMutationRetries(ownerID: operation.ownerID)
        }
    }

    private func startRealtimeSync(operation: AccountOperationLease) async {
        if isDeveloperSandbox { return }
        if let accessServiceSuspensionTask {
            await accessServiceSuspensionTask.value
            self.accessServiceSuspensionTask = nil
        }
        guard accountAccessAllowsPrivateWork(for: operation.ownerID),
              accountOperationIsCurrent(operation) else { return }
        await retryPendingHydrationMutations(operation: operation)
        guard accountOperationIsCurrent(operation) else { return }
        bindHealthBackgroundMonitoring(operation: operation)
        do {
            try await service.startRealtime { [weak self, operation] in
                Task { @MainActor [weak self] in
                    self?.scheduleRealtimeRefresh(operation: operation)
                }
            }
            guard accountOperationIsCurrent(operation) else { return }
        } catch {
            // Foreground refresh and the offline outbox remain available if
            // Realtime is temporarily unavailable.
        }
    }

    private func scheduleRealtimeRefresh(operation: AccountOperationLease) {
        guard accountOperationIsCurrent(operation) else { return }
        realtimeDebounceTask?.cancel()
        realtimeDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self,
                  Task.isCancelled == false,
                  self.accountOperationIsCurrent(operation) else { return }
            await self.flushPendingChanges(for: operation.ownerID)
            guard Task.isCancelled == false,
                  self.accountOperationIsCurrent(operation) else { return }
            do {
                try await self.refreshDashboard(expectedUserID: operation.ownerID)
            } catch is CancellationError {
                // Account transitions intentionally revoke realtime work.
            } catch let error as URLError where error.code == .cancelled {
                // URLSession cancellation is the same benign control flow.
            } catch {
                // Foreground refresh and the offline outbox remain available.
            }
        }
    }

    func refreshExternalWorkouts(operation: AccountOperationLease) async {
        if isDeveloperSandbox { return }
        guard healthImportIsEnabled(operation: operation) else { return }
        await importHealthWorkoutChanges(operation: operation)
    }

    private func importHealthWorkoutChanges(
        operation: AccountOperationLease
    ) async {
        if isDeveloperSandbox { return }
        guard healthImportIsEnabled(operation: operation) else { return }
        let ownerID = operation.ownerID
        guard let changes = try? await HealthKitManager.shared.workoutChanges(ownerID: ownerID) else {
            return
        }
        guard accountOperationIsCurrent(operation) else { return }

        let persistedWorkoutSessions =
            (try? await service.loadWorkoutSessionIdentities(ownerID: ownerID)) ?? []
        guard accountOperationIsCurrent(operation) else { return }
        let currentWorkoutSessions = data.workoutSessions.compactMap { session -> ExternalWorkoutImport.APEXSessionIdentity? in
            guard session.userID == ownerID,
                  let value = session.startedAt ?? session.completedAt,
                  let startedAt = ExternalWorkoutImport.parseTimestamp(value) else { return nil }
            return .init(id: session.id, startedAt: startedAt)
        }
        var workoutSessionsByID = Dictionary(
            uniqueKeysWithValues: persistedWorkoutSessions.map { ($0.id, $0) }
        )
        // A just-completed offline session may not be visible remotely yet.
        // Prefer the in-memory identity until its queued write reaches the server.
        for session in currentWorkoutSessions {
            workoutSessionsByID[session.id] = session
        }
        let workoutSessions = workoutSessionsByID.values.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt > $1.startedAt }
            return $0.id.uuidString > $1.id.uuidString
        }
        let orbitSessions = data.orbitRuns.compactMap { run -> ExternalWorkoutImport.APEXSessionIdentity? in
            guard run.userID == ownerID,
                  let startedAt = ExternalWorkoutImport.parseTimestamp(run.startedAt) else { return nil }
            return .init(id: run.id, startedAt: startedAt)
        }
        let legacyLogIDs = Set(data.activityLogs.compactMap { log in
            log.userID == ownerID && log.source == "workout_module" && log.reconciled
                ? log.id
                : nil
        })
        let reconciled = ExternalWorkoutImport.reconcile(
            changeSet: changes,
            existing: data.importedActivities,
            apexSessions: workoutSessions + orbitSessions,
            ownerID: ownerID,
            legacyActivityLogIDs: legacyLogIDs
        )

        for rowID in reconciled.importedActivityIDsToDelete {
            data.importedActivities.removeAll { $0.id == rowID && $0.userID == ownerID }
            await persistDelete(
                table: "imported_activities",
                id: rowID,
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            guard accountOperationIsCurrent(operation) else { return }
        }
        for logID in reconciled.activityLogIDsToDelete {
            data.activityLogs.removeAll { $0.id == logID && $0.userID == ownerID }
            await persistDelete(
                table: "activity_logs",
                id: logID,
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            guard accountOperationIsCurrent(operation) else { return }
        }
        var persistenceRows = reconciled.upserts
        for row in persistenceRows {
            data.importedActivities.removeAll { $0.id == row.id && $0.userID == ownerID }
            data.importedActivities.append(row)
        }
        let automaticLinks = WearableWorkoutLinking.automaticLinks(
            sessions: data.workoutSessions,
            activities: data.importedActivities,
            ownerID: ownerID
        )
        for linked in automaticLinks {
            data.importedActivities.removeAll { $0.id == linked.id && $0.userID == ownerID }
            data.importedActivities.append(linked)
            persistenceRows.removeAll { $0.id == linked.id }
            persistenceRows.append(linked)
        }
        for batch in ExternalWorkoutImport.persistenceBatches(persistenceRows) {
            await persistUpsert(
                batch,
                table: "imported_activities",
                onConflict: "user_id,healthkit_workout_id",
                ownerID: ownerID,
                expectedAccountToken: operation.generation
            )
            guard accountOperationIsCurrent(operation) else { return }
        }

        if let anchorData = changes.anchorData {
            guard accountOperationIsCurrent(operation) else { return }
            HealthKitManager.shared.commitWorkoutAnchor(anchorData, ownerID: ownerID)
        }
    }
}
