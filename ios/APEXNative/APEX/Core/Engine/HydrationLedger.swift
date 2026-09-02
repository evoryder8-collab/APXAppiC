import Foundation

extension ISO8601DateFormatter {
    static let apexDateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension Date {
    var apexDateKey: String { ISO8601DateFormatter.apexDateOnly.string(from: self) }
}

enum HydrationTargetMode: String, Codable, CaseIterable, Equatable, Sendable {
    case automatic
    case custom
}

enum HydrationTargetDateRelation: Sendable {
    case past
    case today
    case future
}

struct HydrationTargetResolution: Equatable, Sendable {
    let mode: HydrationTargetMode
    let targetML: Int
    let baselineML: Int
    let exerciseAdjustmentML: Int
    let wearableAdjustmentML: Int
}

enum HydrationTargetPolicy {
    private static let legacyTargetML = 2_750

    static func inferredMode(stored: String?, targetML: Int) -> HydrationTargetMode {
        if let stored, let explicit = HydrationTargetMode(rawValue: stored) { return explicit }
        return targetML == legacyTargetML ? .automatic : .custom
    }

    static func resolve(
        sex: String,
        weightKG: Double,
        mode: HydrationTargetMode? = nil,
        customTargetML: Int? = nil,
        plannedExerciseMinutes: Int? = nil,
        recordedExerciseMinutes: Int? = nil,
        activeCalories: Int? = nil,
        steps: Int? = nil,
        dateRelation: HydrationTargetDateRelation = .today,
        localHour: Int = 0
    ) -> HydrationTargetResolution {
        let resolvedMode = mode ?? inferredMode(stored: nil, targetML: customTargetML ?? legacyTargetML)
        if resolvedMode == .custom {
            let exact = min(6_000, max(1_000, customTargetML ?? legacyTargetML))
            return HydrationTargetResolution(
                mode: resolvedMode,
                targetML: exact,
                baselineML: exact,
                exerciseAdjustmentML: 0,
                wearableAdjustmentML: 0
            )
        }

        let isFemale = sex.lowercased() == "female"
        let populationLowerML = isFemale ? 2_000.0 : 2_500.0
        let populationUpperML = isFemale ? 2_700.0 : 3_700.0
        let fallbackWeightKG = isFemale ? 66.0 : 87.0
        let safeWeightKG = weightKG.isFinite && weightKG > 0 ? weightKG : fallbackWeightKG
        let bodyIndexedML = min(populationUpperML, max(populationLowerML, safeWeightKG * 35.5))
        let baselineML = roundedTo50(bodyIndexedML)

        let planned = max(0, plannedExerciseMinutes ?? 0)
        let recorded = max(0, recordedExerciseMinutes ?? 0)
        let exerciseMinutes = min(120, max(planned, recorded))
        let exerciseAdjustmentML = min(750, roundedTo50(Double(exerciseMinutes) * 7))

        let lateEnough = dateRelation == .past || (dateRelation == .today && localHour >= 15)
        let caloriesPerKG = Double(max(0, activeCalories ?? 0)) / max(1, safeWeightKG)
        let safeSteps = max(0, steps ?? 0)
        let calorieAdjustment = caloriesPerKG >= 10 ? 200 : caloriesPerKG >= 6 ? 100 : 0
        let stepAdjustment = safeSteps >= 15_000 ? 200 : safeSteps >= 10_000 ? 100 : 0
        let requestedWearableAdjustment = lateEnough ? max(calorieAdjustment, stepAdjustment) : 0
        let wearableAdjustmentML = min(requestedWearableAdjustment, max(0, 750 - exerciseAdjustmentML))

        return HydrationTargetResolution(
            mode: resolvedMode,
            targetML: baselineML + exerciseAdjustmentML + wearableAdjustmentML,
            baselineML: baselineML,
            exerciseAdjustmentML: exerciseAdjustmentML,
            wearableAdjustmentML: wearableAdjustmentML
        )
    }

    private static func roundedTo50(_ milliliters: Double) -> Int {
        Int((milliliters / 50).rounded()) * 50
    }
}

enum HydrationCompanionKeys {
    static let snapshot = "apex_hydration_snapshot_v1"
    static let mutation = "apex_hydration_mutation_v1"
    static let disconnected = "apex_hydration_disconnected_v1"
    static let disconnectedRevision = "apex_hydration_disconnected_revision_v1"
    static let workoutCommand = "apex_watch_workout_command_v1"
}

enum WatchWorkoutKind: String, Codable, Equatable, Sendable {
    case traditionalStrength = "traditional_strength"
    case yoga
    case hiit
    case running
    case cycling
    case walking
}

enum WatchWorkoutHandoff {
    static func resolve(
        dayType: String,
        name: String,
        exerciseNames: [String]
    ) -> WatchWorkoutKind {
        let descriptor = "\(dayType) \(name)".lowercased()
        if descriptor.containsAny(["mobility", "prehab", "yoga", "pilates", "flexibility", "recovery flow"]) {
            return .yoga
        }
        if descriptor.containsAny(["running", " run", "run ", "5k", "10k", "marathon"]) { return .running }
        if descriptor.containsAny(["cycling", "bike", "bicycle"]) { return .cycling }
        if descriptor.containsAny(["walking", "walk", "hike", "hiking"]) { return .walking }
        if descriptor.containsAny(["hiit", "interval", "conditioning", "metcon", "crossfit", "hyrox", "tabata", "circuit"]) {
            return .hiit
        }
        if descriptor.containsAny(["strength", "hypertrophy", "bodybuilding", "upper", "lower", "push", "pull", "legs"]) {
            return .traditionalStrength
        }

        let exercises = exerciseNames.map { $0.lowercased() }
        let mobilityCount = exercises.filter {
            $0.containsAny(["stretch", "mobility", "yoga", "breathing", "wall slide", "chin tuck"])
        }.count
        if !exercises.isEmpty, mobilityCount * 2 >= exercises.count { return .yoga }
        if exercises.contains(where: { $0.containsAny(["running", "run ", "treadmill"]) }) { return .running }
        if exercises.contains(where: { $0.containsAny(["bike", "cycling"]) }) { return .cycling }
        if exercises.contains(where: { $0.containsAny(["burpee", "interval", "air bike", "ski erg", "row erg"]) }) {
            return .hiit
        }
        return .traditionalStrength
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool { needles.contains(where: contains) }
}

struct WatchWorkoutCommand: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case start
        case stop
        case abort
    }

    let id: UUID
    let ownerID: UUID
    let action: Action
    let createdAt: String

    /// `id` identifies one launch, not one delivery. The start, stop and abort
    /// copies deliberately reuse it so duplicated or delayed WCSession messages
    /// cannot affect a different workout owned by the same account.
    static func starting(
        ownerID: UUID,
        launchID: UUID,
        createdAt: String = revision()
    ) -> WatchWorkoutCommand {
        WatchWorkoutCommand(id: launchID, ownerID: ownerID, action: .start, createdAt: createdAt)
    }

    static func stopping(
        ownerID: UUID,
        launchID: UUID,
        createdAt: String = revision()
    ) -> WatchWorkoutCommand {
        WatchWorkoutCommand(id: launchID, ownerID: ownerID, action: .stop, createdAt: createdAt)
    }

    static func aborting(
        ownerID: UUID,
        launchID: UUID,
        createdAt: String = revision()
    ) -> WatchWorkoutCommand {
        WatchWorkoutCommand(id: launchID, ownerID: ownerID, action: .abort, createdAt: createdAt)
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> WatchWorkoutCommand {
        try JSONDecoder().decode(WatchWorkoutCommand.self, from: data)
    }

    private static func revision() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

struct WatchWorkoutLaunchIntent: Codable, Equatable, Sendable {
    let id: UUID
    let ownerID: UUID
    let createdAt: String
}

private struct WatchWorkoutLaunchCancellation: Codable, Equatable, Sendable {
    let id: UUID
    let ownerID: UUID
}

enum WatchWorkoutLaunchCommandEffect: Equatable, Sendable {
    case none
    case stopActive(UUID)
}

enum WatchWorkoutLaunchResolution: Equatable, Sendable {
    case start(WatchWorkoutLaunchIntent)
    case discard(UUID)
}

enum WatchWorkoutOwnerBoundary {
    static func ownerAfterDisconnect(
        activeOwnerID: UUID?,
        disconnectedOwnerID: UUID
    ) -> UUID? {
        activeOwnerID == disconnectedOwnerID ? nil : activeOwnerID
    }
}

/// Durable causal state for the two independent delivery paths involved in a
/// Watch handoff: WatchConnectivity carries identity while HealthKit carries
/// the workout configuration. Either can arrive first. Pairing them in FIFO
/// order and retaining launch-specific cancellation prevents both an orphaned
/// late start and a stale stop terminating a newer same-owner workout.
struct WatchWorkoutLaunchLedger: Codable, Equatable, Sendable {
    private(set) var pending: [WatchWorkoutLaunchIntent] = []
    private var cancellations: [WatchWorkoutLaunchCancellation] = []
    private(set) var completedLaunchIDs: [UUID] = []
    private(set) var disconnectRevisionByOwner: [String: String] = [:]
    private(set) var active: WatchWorkoutLaunchIntent?

    private static let retainedHistoryLimit = 128

    var representedOwnerIDs: Set<UUID> {
        var owners = Set(pending.map(\.ownerID))
        if let active { owners.insert(active.ownerID) }
        return owners
    }

    mutating func receive(
        _ command: WatchWorkoutCommand
    ) -> WatchWorkoutLaunchCommandEffect {
        switch command.action {
        case .start:
            guard !completedLaunchIDs.contains(command.id),
                  active?.id != command.id,
                  !pending.contains(where: { $0.id == command.id }) else {
                return .none
            }
            let intent = WatchWorkoutLaunchIntent(
                id: command.id,
                ownerID: command.ownerID,
                createdAt: command.createdAt
            )
            pending.append(intent)
            if let disconnectRevision = disconnectRevisionByOwner[ownerKey(command.ownerID)],
               Self.isNotNewer(command.createdAt, than: disconnectRevision) {
                retainCancellation(id: command.id, ownerID: command.ownerID)
            }
            return .none

        case .stop:
            guard !completedLaunchIDs.contains(command.id) else { return .none }
            if let active,
               active.id == command.id,
               active.ownerID == command.ownerID {
                self.active = nil
                complete(command.id)
                return .stopActive(command.id)
            }
            retainCancellation(id: command.id, ownerID: command.ownerID)
            return .none

        case .abort:
            guard !completedLaunchIDs.contains(command.id) else { return .none }
            let removedPending = pending.contains {
                $0.id == command.id && $0.ownerID == command.ownerID
            }
            pending.removeAll { $0.id == command.id && $0.ownerID == command.ownerID }
            cancellations.removeAll {
                $0.id == command.id && $0.ownerID == command.ownerID
            }
            if let active,
               active.id == command.id,
               active.ownerID == command.ownerID {
                self.active = nil
                complete(command.id)
                return .stopActive(command.id)
            }
            guard removedPending else { return .none }
            complete(command.id)
            return .none
        }
    }

    /// Consume exactly one queued HealthKit configuration when its identity is
    /// known. A nil owner means account state is still loading, so neither the
    /// intent nor configuration should be guessed or discarded yet.
    mutating func resolveNextConfiguration(
        activeOwnerID: UUID?
    ) -> WatchWorkoutLaunchResolution? {
        guard let intent = pending.first else { return nil }
        if isCancelled(id: intent.id, ownerID: intent.ownerID) {
            pending.removeFirst()
            complete(intent.id)
            return .discard(intent.id)
        }
        guard let activeOwnerID else { return nil }
        pending.removeFirst()
        guard intent.ownerID == activeOwnerID, active == nil else {
            complete(intent.id)
            return .discard(intent.id)
        }
        active = intent
        return .start(intent)
    }

    mutating func disconnect(
        ownerID: UUID,
        revision: String
    ) -> WatchWorkoutLaunchCommandEffect {
        let key = ownerKey(ownerID)
        if let existing = disconnectRevisionByOwner[key],
           Self.isNotNewer(revision, than: existing) {
            return .none
        }
        disconnectRevisionByOwner[key] = revision
        for intent in pending where intent.ownerID == ownerID
            && Self.isNotNewer(intent.createdAt, than: revision) {
            retainCancellation(id: intent.id, ownerID: intent.ownerID)
        }
        guard let active,
              active.ownerID == ownerID,
              Self.isNotNewer(active.createdAt, than: revision) else {
            return .none
        }
        self.active = nil
        complete(active.id)
        return .stopActive(active.id)
    }

    /// A newly accepted canonical owner is a stronger boundary than a possibly
    /// delayed disconnect packet. Every launch belonging to the previous owner
    /// is invalid, regardless of timestamp, while other owners remain intact.
    mutating func revoke(
        ownerID: UUID,
        revision: String
    ) -> WatchWorkoutLaunchCommandEffect {
        let key = ownerKey(ownerID)
        if let existing = disconnectRevisionByOwner[key] {
            if !Self.isNotNewer(revision, than: existing) {
                disconnectRevisionByOwner[key] = revision
            }
        } else {
            disconnectRevisionByOwner[key] = revision
        }
        for intent in pending where intent.ownerID == ownerID {
            retainCancellation(id: intent.id, ownerID: intent.ownerID)
        }
        guard let active, active.ownerID == ownerID else { return .none }
        self.active = nil
        complete(active.id)
        return .stopActive(active.id)
    }

    func permitsStart(
        launchID: UUID,
        ownerID: UUID,
        activeOwnerID: UUID?
    ) -> Bool {
        active?.id == launchID
            && active?.ownerID == ownerID
            && activeOwnerID == ownerID
            && !isCancelled(id: launchID, ownerID: ownerID)
    }

    mutating func finishActive(launchID: UUID) {
        guard active?.id == launchID else { return }
        active = nil
        complete(launchID)
    }

    private mutating func complete(_ launchID: UUID) {
        cancellations.removeAll { $0.id == launchID }
        completedLaunchIDs = Self.retaining(launchID, in: completedLaunchIDs)
    }

    private func isCancelled(id: UUID, ownerID: UUID) -> Bool {
        cancellations.contains { $0.id == id && $0.ownerID == ownerID }
    }

    private mutating func retainCancellation(id: UUID, ownerID: UUID) {
        let cancellation = WatchWorkoutLaunchCancellation(id: id, ownerID: ownerID)
        cancellations.removeAll { $0 == cancellation }
        cancellations.append(cancellation)
        if cancellations.count > Self.retainedHistoryLimit {
            cancellations.removeFirst(cancellations.count - Self.retainedHistoryLimit)
        }
    }

    private func ownerKey(_ ownerID: UUID) -> String {
        ownerID.uuidString.lowercased()
    }

    private static func retaining(_ id: UUID, in values: [UUID]) -> [UUID] {
        var values = values
        values.removeAll { $0 == id }
        values.append(id)
        if values.count > Self.retainedHistoryLimit {
            values.removeFirst(values.count - Self.retainedHistoryLimit)
        }
        return values
    }

    private static func isNotNewer(_ candidate: String, than revision: String) -> Bool {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let candidateDate = fractional.date(from: candidate) ?? plain.date(from: candidate)
        let revisionDate = fractional.date(from: revision) ?? plain.date(from: revision)
        if let candidateDate, let revisionDate { return candidateDate <= revisionDate }
        return candidate <= revision
    }
}

enum HydrationWidgetStorage {
    static let suiteName = "group.ch.apexperformance.APEX"
    static let stateKey = "apex_hydration_widget_state_v1"
    static let healthStateKey = "apex_hydration_widget_health_state_v1"
    static let requestedVisibleSignatureKey = "apex_hydration_widget_requested_signature_v1"
    static let renderedVisibleSignatureKey = "apex_hydration_widget_rendered_signature_v1"

    static func healthSampleOwnerClaimKey(for sampleID: UUID) -> String {
        "apex_hydration_health_sample_owner_v1.\(sampleID.uuidString.lowercased())"
    }
}

enum HydrationMetadata {
    static let eventID = "ch.apexperformance.APEX.hydration.event_id"
    static let ownerID = "ch.apexperformance.APEX.hydration.owner_id"
    static let kind = "ch.apexperformance.APEX.hydration.kind"
    static let palette = "ch.apexperformance.APEX.hydration.palette"
    static let icon = "ch.apexperformance.APEX.hydration.icon"
}

enum HydrationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case water, coffee, tea, juice, shake, other, food, external, legacy
}

enum HydrationPresetKind: String, Codable, CaseIterable, Hashable, Sendable {
    case water, coffee, tea, juice, shake, other

    var eventKind: HydrationKind { HydrationKind(rawValue: rawValue) ?? .other }
}

enum HydrationSource: String, Codable, CaseIterable, Hashable, Sendable {
    case iPhone = "iphone"
    case watch
    case web
    case food
    case healthKitExternal = "healthkit_external"
    case legacy
}

struct HydrationEvent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    let clientIdempotencyKey: String
    let localDate: String
    let occurredAt: String
    var amountML: Int
    let kind: HydrationKind
    let paletteToken: String
    let iconToken: String
    let source: HydrationSource
    var healthKitSampleID: UUID?
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, source
        case userID = "user_id"
        case clientIdempotencyKey = "client_idempotency_key"
        case localDate = "local_date"
        case occurredAt = "occurred_at"
        case amountML = "amount_ml"
        case paletteToken = "palette_token"
        case iconToken = "icon_token"
        case healthKitSampleID = "healthkit_sample_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct HydrationPresetTemplate: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let amountML: Int
    let kind: HydrationPresetKind
    let paletteToken: String
    let iconToken: String
    let sortOrder: Int
    let enabled: Bool
}

struct HydrationPreset: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var name: String
    var amountML: Int
    var kind: HydrationPresetKind
    var paletteToken: String
    var iconToken: String
    var sortOrder: Int
    var enabled: Bool
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, kind, enabled
        case userID = "user_id"
        case amountML = "amount_ml"
        case paletteToken = "palette_token"
        case iconToken = "icon_token"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct HydrationAccountPreferences: Codable, Hashable, Sendable {
    let userID: UUID
    var targetML: Int
    var targetMode: String? = nil
    var displayUnit: String
    var remindersEnabled: Bool
    var reminderIntervalMinutes: Int
    var quietHoursStartMinutes: Int
    var quietHoursEndMinutes: Int
    var showsPresetNames: Bool
    var confirmationHaptics: Bool
    var motionIntensity: String
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case targetML = "target_ml"
        case targetMode = "target_mode"
        case displayUnit = "display_unit"
        case remindersEnabled = "reminders_enabled"
        case reminderIntervalMinutes = "reminder_interval_minutes"
        case quietHoursStartMinutes = "quiet_hours_start_minutes"
        case quietHoursEndMinutes = "quiet_hours_end_minutes"
        case showsPresetNames = "shows_preset_names"
        case confirmationHaptics = "confirmation_haptics"
        case motionIntensity = "motion_intensity"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var effectiveTargetMode: HydrationTargetMode {
        HydrationTargetPolicy.inferredMode(stored: targetMode, targetML: targetML)
    }
}

extension WatchHydrationPreferences {
    init(account preferences: HydrationAccountPreferences) {
        self.init(
            targetLiters: Double(preferences.targetML) / 1_000,
            targetMode: preferences.effectiveTargetMode,
            unit: Unit(rawValue: preferences.displayUnit) ?? .liters,
            showsPresetNames: preferences.showsPresetNames,
            confirmationHaptics: preferences.confirmationHaptics,
            motionIntensity: MotionIntensity(rawValue: preferences.motionIntensity) ?? .subtle,
            remindersEnabled: preferences.remindersEnabled,
            reminderIntervalMinutes: preferences.reminderIntervalMinutes,
            quietHoursStartMinutes: preferences.quietHoursStartMinutes,
            quietHoursEndMinutes: preferences.quietHoursEndMinutes
        )
    }

    func accountRow(ownerID: UUID, existing: HydrationAccountPreferences?) -> HydrationAccountPreferences {
        let now = Date().ISO8601Format()
        return HydrationAccountPreferences(
            userID: ownerID,
            targetML: effectiveTargetMode == .custom
                ? Int((targetLiters * 1_000).rounded())
                : existing?.targetML ?? Int((targetLiters * 1_000).rounded()),
            targetMode: effectiveTargetMode.rawValue,
            displayUnit: unit.rawValue,
            remindersEnabled: remindersEnabled,
            reminderIntervalMinutes: reminderIntervalMinutes,
            quietHoursStartMinutes: quietHoursStartMinutes,
            quietHoursEndMinutes: quietHoursEndMinutes,
            showsPresetNames: showsPresetNames,
            confirmationHaptics: confirmationHaptics,
            motionIntensity: motionIntensity.rawValue,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }
}

struct HydrationCompositionBand: Codable, Hashable, Sendable {
    let kind: HydrationKind
    let paletteToken: String
    let iconToken: String
    let milliliters: Int
}

struct HydrationCompanionSnapshot: Codable, Equatable, Sendable {
    let ownerID: UUID
    let localDate: String
    let totalML: Int
    let targetML: Int
    let events: [HydrationEvent]
    let presets: [HydrationPreset]
    let preferences: WatchHydrationPreferences
    let composition: [HydrationCompositionBand]
    let revision: String
    let acknowledgedDeleteIDs: [UUID]?

    static func make(
        ownerID: UUID,
        date: String,
        events: [HydrationEvent],
        presets: [HydrationPreset],
        preferences: WatchHydrationPreferences,
        legacyDrinkLiters: Double,
        revision: String,
        acknowledgedDeleteIDs: [UUID] = []
    ) -> HydrationCompanionSnapshot {
        let ownedEvents = events.filter { $0.userID == ownerID && $0.localDate == date }
        let ownedPresets = presets.filter { $0.userID == ownerID && $0.enabled }
            .sorted { ($0.sortOrder, $0.createdAt, $0.id) < ($1.sortOrder, $1.createdAt, $1.id) }
        let resolved = HydrationLedger.resolve(
            ownerID: ownerID,
            date: date,
            events: ownedEvents,
            legacyDrinkLiters: legacyDrinkLiters
        )
        return HydrationCompanionSnapshot(
            ownerID: ownerID,
            localDate: date,
            totalML: resolved.totalML,
            targetML: Int((preferences.targetLiters * 1_000).rounded()),
            events: ownedEvents,
            presets: ownedPresets,
            preferences: preferences,
            composition: resolved.composition,
            revision: revision,
            acknowledgedDeleteIDs: acknowledgedDeleteIDs
        )
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> HydrationCompanionSnapshot {
        try JSONDecoder().decode(HydrationCompanionSnapshot.self, from: data)
    }
}

struct HydrationWidgetState: Codable, Equatable, Sendable {
    let ownerID: UUID
    let localDate: String
    let totalML: Int
    let targetML: Int
    let composition: [HydrationCompositionBand]
    let revision: String
    let healthAnchor: [HydrationHealthSampleAnchor]?
    let healthQueryAnchorData: Data?
    let canonicalSampleIDs: [UUID]?
    let healthOverlay: [HydrationPendingMutation]?

    init(snapshot: HydrationCompanionSnapshot) {
        ownerID = snapshot.ownerID
        localDate = snapshot.localDate
        totalML = snapshot.totalML
        targetML = snapshot.targetML
        composition = snapshot.composition
        revision = snapshot.revision
        healthAnchor = nil
        healthQueryAnchorData = nil
        canonicalSampleIDs = Array(snapshot.events.reduce(into: Set<UUID>()) { result, event in
            result.insert(event.id)
            if let healthKitSampleID = event.healthKitSampleID {
                result.insert(healthKitSampleID)
            }
        }).sorted { $0.uuidString < $1.uuidString }
        healthOverlay = []
    }

    init(
        ownerID: UUID,
        localDate: String,
        totalML: Int,
        targetML: Int,
        composition: [HydrationCompositionBand],
        revision: String,
        healthAnchor: [HydrationHealthSampleAnchor]? = nil,
        healthQueryAnchorData: Data? = nil,
        canonicalSampleIDs: [UUID]? = nil,
        healthOverlay: [HydrationPendingMutation]? = nil
    ) {
        self.ownerID = ownerID
        self.localDate = localDate
        self.totalML = max(0, totalML)
        self.targetML = max(250, targetML)
        self.composition = composition
        self.revision = revision
        self.healthAnchor = healthAnchor
        self.healthQueryAnchorData = healthQueryAnchorData
        self.canonicalSampleIDs = canonicalSampleIDs
        self.healthOverlay = healthOverlay
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> HydrationWidgetState {
        try JSONDecoder().decode(HydrationWidgetState.self, from: data)
    }
}

struct HydrationWidgetHealthState: Codable, Equatable, Sendable {
    let ownerID: UUID
    let localDate: String
    let baseRevision: String
    let observationRevision: String?
    let totalML: Int
    let composition: [HydrationCompositionBand]
    let healthAnchor: [HydrationHealthSampleAnchor]
    let healthQueryAnchorData: Data?
    let healthOverlay: [HydrationPendingMutation]

    init(
        ownerID: UUID,
        localDate: String,
        baseRevision: String,
        observationRevision: String? = nil,
        totalML: Int,
        composition: [HydrationCompositionBand],
        healthAnchor: [HydrationHealthSampleAnchor],
        healthQueryAnchorData: Data?,
        healthOverlay: [HydrationPendingMutation]
    ) {
        self.ownerID = ownerID
        self.localDate = localDate
        self.baseRevision = baseRevision
        self.observationRevision = observationRevision
        self.totalML = max(0, totalML)
        self.composition = composition
        self.healthAnchor = healthAnchor
        self.healthQueryAnchorData = healthQueryAnchorData
        self.healthOverlay = healthOverlay
    }

    func matches(_ state: HydrationWidgetState) -> Bool {
        ownerID == state.ownerID
            && localDate == state.localDate
            && baseRevision == state.revision
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> HydrationWidgetHealthState {
        try JSONDecoder().decode(HydrationWidgetHealthState.self, from: data)
    }
}

enum HydrationHealthSidecarWritePolicy {
    static func shouldPersist(
        existing: HydrationWidgetHealthState?,
        incoming: HydrationWidgetHealthState,
        canonical: HydrationWidgetState
    ) -> Bool {
        guard incoming.matches(canonical) else { return false }
        guard let existing, existing.matches(canonical) else { return true }
        switch (existing.observationRevision, incoming.observationRevision) {
        case (_, nil):
            return existing.observationRevision == nil
        case (nil, .some):
            return true
        case let (.some(current), .some(incoming)):
            return HydrationComplicationRefreshPolicy.shouldAcceptSnapshot(
                currentRevision: current,
                incomingRevision: incoming
            )
        }
    }
}

struct HydrationWidgetResolvedState: Equatable, Sendable {
    let totalML: Int
    let composition: [HydrationCompositionBand]
    let healthAnchor: [HydrationHealthSampleAnchor]?
    let healthQueryAnchorData: Data?
    let healthOverlay: [HydrationPendingMutation]
}

enum HydrationWidgetStateResolver {
    static func resolve(
        canonical: HydrationWidgetState,
        healthState: HydrationWidgetHealthState?
    ) -> HydrationWidgetResolvedState {
        guard let healthState, healthState.matches(canonical) else {
            return HydrationWidgetResolvedState(
                totalML: canonical.totalML,
                composition: canonical.composition,
                healthAnchor: canonical.healthAnchor,
                healthQueryAnchorData: canonical.healthQueryAnchorData,
                healthOverlay: canonical.healthOverlay ?? []
            )
        }
        /* The companion snapshot is the account-owned source of truth. A
           HealthKit sidecar may surface an external addition before the app
           has absorbed it, but it must never erase a canonical APEX event.
           Deleted HealthKit samples are reconciled by the Watch app, which
           can update the canonical snapshot and its causal revision. */
        let visibleHealthOverlay = healthState.healthOverlay.filter {
            $0.action == .upsert
        }
        let reconciled = HydrationHealthReconciler.replacingOverlay(
            canonical.healthOverlay ?? [],
            with: visibleHealthOverlay,
            inTotalML: canonical.totalML,
            composition: canonical.composition
        )
        return HydrationWidgetResolvedState(
            totalML: reconciled.totalML,
            composition: reconciled.composition,
            healthAnchor: healthState.healthAnchor,
            healthQueryAnchorData: healthState.healthQueryAnchorData,
            healthOverlay: visibleHealthOverlay
        )
    }
}

struct HydrationCompanionMutation: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case upsertEvent = "upsert_event"
        case deleteEvent = "delete_event"
        case updatePreferences = "update_preferences"
    }

    let id: UUID
    let ownerID: UUID
    let action: Action
    let event: HydrationEvent?
    let eventID: UUID?
    let preferences: WatchHydrationPreferences?
    let createdAt: String

    static func upserting(_ event: HydrationEvent) -> HydrationCompanionMutation {
        HydrationCompanionMutation(
            id: UUID(), ownerID: event.userID, action: .upsertEvent,
            event: event, eventID: nil, preferences: nil,
            createdAt: Date().ISO8601Format()
        )
    }

    static func deleting(eventID: UUID, ownerID: UUID) -> HydrationCompanionMutation {
        HydrationCompanionMutation(
            id: UUID(), ownerID: ownerID, action: .deleteEvent,
            event: nil, eventID: eventID, preferences: nil,
            createdAt: Date().ISO8601Format()
        )
    }

    static func updating(
        _ preferences: WatchHydrationPreferences,
        ownerID: UUID
    ) -> HydrationCompanionMutation {
        HydrationCompanionMutation(
            id: UUID(), ownerID: ownerID, action: .updatePreferences,
            event: nil, eventID: nil, preferences: preferences,
            createdAt: Date().ISO8601Format()
        )
    }

    func belongs(to activeOwnerID: UUID) -> Bool {
        guard ownerID == activeOwnerID else { return false }
        switch action {
        case .upsertEvent:
            return event?.userID == ownerID && eventID == nil && preferences == nil
        case .deleteEvent:
            return event == nil && eventID != nil && preferences == nil
        case .updatePreferences:
            return event == nil && eventID == nil && preferences != nil
        }
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> HydrationCompanionMutation {
        try JSONDecoder().decode(HydrationCompanionMutation.self, from: data)
    }
}

struct HydrationDayResolution: Hashable, Sendable {
    let drinkML: Int
    let foodML: Int
    let totalML: Int
    let composition: [HydrationCompositionBand]
    let usesLegacyAggregate: Bool
}

struct HydrationLegacyMigration: Equatable, Sendable {
    let baselineML: Int
    let importCutoff: Date?
}

enum HydrationMutationOrdering {
    static func accepts(event: HydrationEvent, afterTombstoneRevision revision: String?) -> Bool {
        guard let revision else { return true }
        return event.updatedAt > revision
    }

    static func acceptsPreference(incomingRevision: String, currentRevision: String?) -> Bool {
        guard let currentRevision else { return true }
        return incomingRevision > currentRevision
    }
}

struct HydrationEventReplacement: Sendable {
    let original: HydrationEvent
    var replacement: HydrationEvent
}

struct HydrationReductionPlan: Sendable {
    let resultingEvents: [HydrationEvent]
    let deletedEvents: [HydrationEvent]
    let replacements: [HydrationEventReplacement]
    let drinkML: Int
}

@MainActor
final class HydrationMutationQueue {
    private var tail: Task<Double, Never>?
    private var revision: UInt64 = 0

    func enqueue(
        _ operation: @escaping @MainActor @Sendable () async -> Double
    ) -> Task<Double, Never> {
        let previous = tail
        revision &+= 1
        let operationRevision = revision
        let task = Task { @MainActor [weak self] in
            _ = await previous?.value
            let value = await operation()
            if self?.revision == operationRevision {
                self?.tail = nil
            }
            return value
        }
        tail = task
        return task
    }
}

enum HydrationLedger {
    static let legacyAnchorPalette = "legacy_anchor"
    static let legacyAdjustedPalette = "legacy_adjusted"

    static let defaultPresetTemplates: [HydrationPresetTemplate] = [
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000251")!, name: "Glass", amountML: 250, kind: .water, paletteToken: "aqua", iconToken: "drop.fill", sortOrder: 0, enabled: true),
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000500")!, name: "Bottle", amountML: 500, kind: .water, paletteToken: "blue", iconToken: "waterbottle.fill", sortOrder: 1, enabled: true),
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000190")!, name: "Coffee", amountML: 190, kind: .coffee, paletteToken: "espresso", iconToken: "cup.and.saucer.fill", sortOrder: 2, enabled: true),
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000252")!, name: "Tea", amountML: 250, kind: .tea, paletteToken: "tea", iconToken: "mug.fill", sortOrder: 3, enabled: true),
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000253")!, name: "Juice", amountML: 250, kind: .juice, paletteToken: "citrus", iconToken: "takeoutbag.and.cup.and.straw.fill", sortOrder: 4, enabled: true),
        .init(id: UUID(uuidString: "00000000-0000-4000-8000-000000000350")!, name: "Shake", amountML: 350, kind: .shake, paletteToken: "cocoa", iconToken: "waterbottle.fill", sortOrder: 5, enabled: true),
    ]

    private struct IdempotencyKey: Hashable {
        let userID: UUID
        let clientKey: String
    }

    static func merge(current: [HydrationEvent], incoming: [HydrationEvent]) -> [HydrationEvent] {
        var rows: [IdempotencyKey: HydrationEvent] = [:]
        for candidate in current + incoming {
            let key = IdempotencyKey(userID: candidate.userID, clientKey: candidate.clientIdempotencyKey)
            if let existing = rows[key], existing.updatedAt > candidate.updatedAt { continue }
            rows[key] = candidate
        }
        return rows.values.sorted { $0.occurredAt > $1.occurredAt }
    }

    static func reductionPlan(
        ownerID: UUID,
        date: String,
        events: [HydrationEvent],
        amountML: Int,
        updatedAt: String
    ) -> HydrationReductionPlan {
        var resultingEvents = events
        var deletedEvents: [HydrationEvent] = []
        var replacements: [HydrationEventReplacement] = []
        var remaining = max(0, amountML)
        let candidates = events.filter {
            $0.userID == ownerID && $0.localDate == date
                && ($0.source == .iPhone || $0.source == .legacy)
                && $0.kind != .food && $0.amountML > 0
        }.sorted {
            ($0.occurredAt, $0.createdAt, $0.id.uuidString)
                > ($1.occurredAt, $1.createdAt, $1.id.uuidString)
        }

        for original in candidates where remaining > 0 {
            if original.amountML <= remaining {
                remaining -= original.amountML
                deletedEvents.append(original)
                resultingEvents.removeAll {
                    $0.id == original.id && $0.userID == ownerID
                }
            } else {
                var replacement = original
                replacement.amountML = original.amountML - remaining
                replacement.healthKitSampleID = nil
                replacement.updatedAt = updatedAt
                remaining = 0
                replacements.append(.init(original: original, replacement: replacement))
                if let index = resultingEvents.firstIndex(where: {
                    $0.id == original.id && $0.userID == ownerID
                }) {
                    resultingEvents[index] = replacement
                }
            }
        }

        let resolved = resolve(
            ownerID: ownerID,
            date: date,
            events: resultingEvents,
            legacyDrinkLiters: 0
        )
        return HydrationReductionPlan(
            resultingEvents: resultingEvents,
            deletedEvents: deletedEvents,
            replacements: replacements,
            drinkML: resolved.drinkML
        )
    }

    static func legacyMigration(
        legacyDrinkLiters: Double,
        previouslyImportedLiters: Double?,
        anchor: Date
    ) -> HydrationLegacyMigration {
        let legacyML = legacyDrinkLiters.isFinite
            ? max(0, Int((legacyDrinkLiters * 1_000).rounded()))
            : 0
        guard let previouslyImportedLiters, previouslyImportedLiters.isFinite else {
            return HydrationLegacyMigration(baselineML: legacyML, importCutoff: anchor)
        }
        let importedML = max(0, Int((previouslyImportedLiters * 1_000).rounded()))
        return HydrationLegacyMigration(
            baselineML: max(0, legacyML - importedML),
            importCutoff: nil
        )
    }

    static func shouldImportHealthSample(
        occurredAt: Date,
        ownerID: UUID,
        date: String,
        events: [HydrationEvent]
    ) -> Bool {
        guard let anchor = events.first(where: {
            $0.userID == ownerID && $0.localDate == date
                && $0.source == .legacy
                && ($0.paletteToken == legacyAnchorPalette || $0.paletteToken == "legacy")
        }), let cutoff = ISO8601DateFormatter().date(from: anchor.occurredAt) else {
            return true
        }
        return occurredAt > cutoff
    }

    static func eventsDeletedByHealthKit(
        events: [HydrationEvent],
        ownerID: UUID,
        deletedSampleIDs: Set<UUID>
    ) -> [HydrationEvent] {
        guard !deletedSampleIDs.isEmpty else { return [] }
        return events.filter {
            $0.userID == ownerID
                && $0.healthKitSampleID.map(deletedSampleIDs.contains) == true
        }
    }

    static func resolve(
        ownerID: UUID,
        date: String,
        events: [HydrationEvent],
        legacyDrinkLiters: Double
    ) -> HydrationDayResolution {
        let facts = merge(current: [], incoming: events).filter {
            $0.userID == ownerID && $0.localDate == date && $0.amountML > 0
        }
        let hasDrinkFacts = facts.contains { $0.kind != .food }
        let legacyML = hasDrinkFacts || !legacyDrinkLiters.isFinite
            ? 0
            : max(0, Int((legacyDrinkLiters * 1_000).rounded()))

        struct BandKey: Hashable {
            let kind: HydrationKind
            let palette: String
            let icon: String
        }
        struct BandAggregate {
            var milliliters: Int
            var latestOccurredAt: String
            var latestCreatedAt: String
            var latestID: String
        }
        var totals: [BandKey: BandAggregate] = [:]
        for fact in facts {
            let key = BandKey(kind: fact.kind, palette: fact.paletteToken, icon: fact.iconToken)
            let factOrder = (fact.occurredAt, fact.createdAt, fact.id.uuidString)
            if var aggregate = totals[key] {
                aggregate.milliliters += fact.amountML
                let aggregateOrder = (
                    aggregate.latestOccurredAt,
                    aggregate.latestCreatedAt,
                    aggregate.latestID
                )
                if factOrder > aggregateOrder {
                    aggregate.latestOccurredAt = fact.occurredAt
                    aggregate.latestCreatedAt = fact.createdAt
                    aggregate.latestID = fact.id.uuidString
                }
                totals[key] = aggregate
            } else {
                totals[key] = BandAggregate(
                    milliliters: fact.amountML,
                    latestOccurredAt: fact.occurredAt,
                    latestCreatedAt: fact.createdAt,
                    latestID: fact.id.uuidString
                )
            }
        }
        if legacyML > 0 {
            totals[BandKey(kind: .legacy, palette: "legacy", icon: "drop.circle")] = BandAggregate(
                milliliters: legacyML,
                latestOccurredAt: "",
                latestCreatedAt: "",
                latestID: ""
            )
        }

        let order: [HydrationKind: Int] = [
            .water: 0, .coffee: 1, .tea: 2, .juice: 3, .shake: 4,
            .other: 5, .external: 6, .food: 7, .legacy: 8,
        ]
        let composition = totals.sorted { lhs, rhs in
            let lhsOrder = (
                lhs.value.latestOccurredAt,
                lhs.value.latestCreatedAt,
                lhs.value.latestID
            )
            let rhsOrder = (
                rhs.value.latestOccurredAt,
                rhs.value.latestCreatedAt,
                rhs.value.latestID
            )
            if lhsOrder != rhsOrder { return lhsOrder > rhsOrder }
            return (order[lhs.key.kind] ?? Int.max, lhs.key.palette, lhs.key.icon)
                < (order[rhs.key.kind] ?? Int.max, rhs.key.palette, rhs.key.icon)
        }.map { key, aggregate in
            HydrationCompositionBand(
                kind: key.kind,
                paletteToken: key.palette,
                iconToken: key.icon,
                milliliters: aggregate.milliliters
            )
        }
        let foodML = composition.filter { $0.kind == .food }.reduce(0) { $0 + $1.milliliters }
        let drinkML = composition.filter { $0.kind != .food }.reduce(0) { $0 + $1.milliliters }
        return HydrationDayResolution(
            drinkML: drinkML,
            foodML: foodML,
            totalML: drinkML + foodML,
            composition: composition,
            usesLegacyAggregate: legacyML > 0
        )
    }
}
