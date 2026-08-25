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

enum HydrationCompanionKeys {
    static let snapshot = "apex_hydration_snapshot_v1"
    static let mutation = "apex_hydration_mutation_v1"
    static let disconnected = "apex_hydration_disconnected_v1"
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
    enum Action: String, Codable, Sendable { case stop }

    let id: UUID
    let ownerID: UUID
    let action: Action
    let createdAt: String

    static func stopping(ownerID: UUID) -> WatchWorkoutCommand {
        WatchWorkoutCommand(id: UUID(), ownerID: ownerID, action: .stop, createdAt: Date().ISO8601Format())
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> WatchWorkoutCommand {
        try JSONDecoder().decode(WatchWorkoutCommand.self, from: data)
    }
}

enum HydrationWidgetStorage {
    static let suiteName = "group.ch.apexperformance.APEX"
    static let stateKey = "apex_hydration_widget_state_v1"
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

enum HydrationSource: String, Codable, Hashable, Sendable {
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
    let kind: HydrationKind
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
    var kind: HydrationKind
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
}

extension WatchHydrationPreferences {
    init(account preferences: HydrationAccountPreferences) {
        self.init(
            targetLiters: Double(preferences.targetML) / 1_000,
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
            targetML: Int((targetLiters * 1_000).rounded()),
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

    static func make(
        ownerID: UUID,
        date: String,
        events: [HydrationEvent],
        presets: [HydrationPreset],
        preferences: WatchHydrationPreferences,
        legacyDrinkLiters: Double,
        revision: String
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
            revision: revision
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

    init(snapshot: HydrationCompanionSnapshot) {
        ownerID = snapshot.ownerID
        localDate = snapshot.localDate
        totalML = snapshot.totalML
        targetML = snapshot.targetML
        composition = snapshot.composition
        revision = snapshot.revision
    }

    init(
        ownerID: UUID,
        localDate: String,
        totalML: Int,
        targetML: Int,
        composition: [HydrationCompositionBand],
        revision: String
    ) {
        self.ownerID = ownerID
        self.localDate = localDate
        self.totalML = max(0, totalML)
        self.targetML = max(250, targetML)
        self.composition = composition
        self.revision = revision
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> HydrationWidgetState {
        try JSONDecoder().decode(HydrationWidgetState.self, from: data)
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
        var totals: [BandKey: Int] = [:]
        for fact in facts {
            let key = BandKey(kind: fact.kind, palette: fact.paletteToken, icon: fact.iconToken)
            totals[key, default: 0] += fact.amountML
        }
        if legacyML > 0 {
            totals[BandKey(kind: .legacy, palette: "legacy", icon: "drop.circle")] = legacyML
        }

        let order: [HydrationKind: Int] = [
            .water: 0, .coffee: 1, .tea: 2, .juice: 3, .shake: 4,
            .other: 5, .external: 6, .food: 7, .legacy: 8,
        ]
        let composition = totals.map { key, value in
            HydrationCompositionBand(
                kind: key.kind,
                paletteToken: key.palette,
                iconToken: key.icon,
                milliliters: value
            )
        }.sorted {
            (order[$0.kind] ?? Int.max, $0.paletteToken, $0.iconToken)
                < (order[$1.kind] ?? Int.max, $1.paletteToken, $1.iconToken)
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
