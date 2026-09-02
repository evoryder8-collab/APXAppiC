import Foundation
import UserNotifications

struct NudgeNotificationPermission: Equatable, Sendable {
    let authorised: Bool
    let canAsk: Bool
}

@MainActor
protocol NudgeNotificationScheduling: AnyObject {
    func readPermission() async -> NudgeNotificationPermission
    func requestPermission() async -> Bool
    func pendingNotificationIdentifiers() async -> [String]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
private final class SystemNudgeNotificationScheduler: NudgeNotificationScheduling {
    private let centre: UNUserNotificationCenter

    init(centre: UNUserNotificationCenter = .current()) {
        self.centre = centre
    }

    func readPermission() async -> NudgeNotificationPermission {
        let status = await centre.notificationSettings().authorizationStatus
        return NudgeNotificationPermission(
            authorised: [.authorized, .provisional, .ephemeral].contains(status),
            canAsk: status == .notDetermined
        )
    }

    func requestPermission() async -> Bool {
        (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func pendingNotificationIdentifiers() async -> [String] {
        await centre.pendingNotificationRequests().map(\.identifier)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        centre.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await centre.add(request)
    }
}

/// Decides what today deserves a reminder about, and delivers it two ways:
/// a local notification in the evening, and a bell inside the app.
///
/// There is no server here, so the evening notification is rescheduled from
/// live data every time the app is opened or something is logged. If the day
/// no longer warrants it, the pending request is cancelled rather than left to
/// fire on stale information, which is the failure people actually notice:
/// being told they are short on protein an hour after they hit the target.
@Observable
@MainActor
final class NudgeCenter {

    static let shared = NudgeCenter()

    private(set) var pending: [DailyNudges.Nudge] = []
    private var activeOwnerID: UUID?
    private var schedulingGeneration: UInt64 = 0
    private var accountCleanupGeneration: UInt64 = 0
    private let notificationScheduler: any NudgeNotificationScheduling
    private let defaults: UserDefaults

    /* The scheduling half of a refresh, held so a newer refresh can cancel it.
       Being on the main actor stops two refreshes running at once, but not from
       interleaving: each suspends at its first await and the other resumes.
       Two of them racing could re-add a reminder the newer one had just
       cleared, which is the exact failure this type exists to avoid, telling
       someone they are short on protein an hour after they hit the target.
       Cancelling means the most recent view of the day is the one that wins. */
    private var scheduling: Task<Void, Never>?
    private var accountCleanup: Task<Void, Never>?
    private(set) var authorised = false

    /// Nudges the user has already opened, so the bell stops claiming they are new.
    private var readIDs: Set<String> {
        get {
            guard let activeOwnerID else { return [] }
            return Set(defaults.stringArray(forKey: Self.readKey(for: activeOwnerID)) ?? [])
        }
        set {
            guard let activeOwnerID else { return }
            defaults.set(Array(newValue), forKey: Self.readKey(for: activeOwnerID))
        }
    }
    private static let identifierPrefix = "apex.nudge."

    init(
        notificationScheduler: any NudgeNotificationScheduling = SystemNudgeNotificationScheduler(),
        defaults: UserDefaults = .standard
    ) {
        self.notificationScheduler = notificationScheduler
        self.defaults = defaults
    }

    /// Establish the account which owns the bell's visible state and local
    /// notifications. AppSession calls this only after its dashboard identity
    /// is verified.
    func activate(ownerID: UUID) {
        guard activeOwnerID != ownerID else { return }
        let previousOwnerID = activeOwnerID
        invalidateScheduling()
        invalidateAccountCleanup()
        activeOwnerID = ownerID
        pending = []
        if let previousOwnerID {
            removeKnownScheduledNotifications(for: previousOwnerID)
        }
        reconcileScheduledAsynchronously(activeOwnerID: ownerID)
    }

    /// Synchronously removes account-owned UI state and every known reminder
    /// at logout or before an account switch. An asynchronous inventory pass
    /// follows to catch legacy identifiers.
    func clearAccountBoundary() {
        let previousOwnerID = activeOwnerID
        invalidateScheduling()
        invalidateAccountCleanup()
        activeOwnerID = nil
        pending = []
        if let previousOwnerID {
            removeKnownScheduledNotifications(for: previousOwnerID)
        }
        reconcileScheduledAsynchronously(activeOwnerID: nil)
    }

    static func notificationIdentifier(ownerID: UUID, kind: DailyNudges.Kind) -> String {
        identifierPrefix + ownerID.uuidString.lowercased() + "." + kind.rawValue
    }

    var unreadCount: Int { pending.filter { !readIDs.contains($0.id) }.count }

    func isRead(_ nudge: DailyNudges.Nudge) -> Bool { readIDs.contains(nudge.id) }

    func markRead(_ nudge: DailyNudges.Nudge) { readIDs.insert(nudge.id) }

    func markAllRead(ownerID: UUID) {
        guard activeOwnerID == ownerID else { return }
        readIDs.formUnion(pending.map(\.id))
    }

    /// Turn on evening delivery from an explicit tap, and schedule immediately
    /// so the first reminder is not lost to the gap before the next refresh.
    func enableEveningDelivery(ownerID: UUID) async {
        /* The sheet supplies the owner captured at tap time. Never recover the
           owner here from mutable singleton state: a queued Account-A tap may
           not start until Account B is already active. */
        guard activeOwnerID == ownerID else { return }
        let generation = schedulingGeneration
        guard await requestPermission(ownerID: ownerID) else { return }
        guard schedulingIsCurrent(ownerID: ownerID, generation: generation) else { return }
        await reschedule(pending, ownerID: ownerID, generation: generation)
    }

    /// Whether the system prompt has never been shown, so the sheet knows to
    /// offer it rather than silently doing nothing.
    private(set) var canAskForPermission = false

    /// Read the current state without prompting for anything.
    func readPermission(ownerID: UUID) async {
        guard activeOwnerID == ownerID else { return }
        let generation = accountCleanupGeneration
        let permission = await notificationScheduler.readPermission()
        guard accountCleanupIsCurrent(
            activeOwnerID: ownerID,
            generation: generation
        ) else { return }
        authorised = permission.authorised
        canAskForPermission = permission.canAsk
    }

    /// Ask, only ever from an explicit tap.
    ///
    /// Prompting on first launch, before the app has done anything for anyone,
    /// is how an app earns a permanent no. The bell works either way; the
    /// system prompt only buys the evening delivery.
    @discardableResult
    func requestPermission(ownerID: UUID) async -> Bool {
        activate(ownerID: ownerID)
        let generation = schedulingGeneration
        let granted = await notificationScheduler.requestPermission()
        guard schedulingIsCurrent(ownerID: ownerID, generation: generation) else { return false }
        authorised = granted
        canAskForPermission = false
        return authorised
    }

    /// Recompute the day and re-register the evening reminder.
    func refresh(
        proteinConsumedG: Double,
        proteinTargetG: Double,
        goal: String,
        bodyweightKG: Double,
        creatineInStack: Bool,
        creatineLoggedToday: Bool
    ) async {
        var nudges: [DailyNudges.Nudge] = []
        if let protein = DailyNudges.proteinShortfall(
            consumedG: proteinConsumedG,
            targetG: proteinTargetG,
            goal: goal,
            bodyweightKG: bodyweightKG
        ) {
            nudges.append(protein)
        }
        if let creatine = DailyNudges.creatineMissed(
            loggedToday: creatineLoggedToday,
            inStack: creatineInStack
        ) {
            nudges.append(creatine)
        }
        /* Computed without suspending, so what the bell shows is always the
           newest answer even if the scheduling below is overtaken. */
        pending = nudges

        guard let ownerID = activeOwnerID else { return }
        invalidateScheduling()
        let generation = schedulingGeneration
        let work = Task { @MainActor [weak self, nudges, ownerID, generation] in
            guard let self else { return }
            guard !nudges.isEmpty else {
                await self.clearScheduled(for: ownerID, generation: generation)
                return
            }
            /* Only ever schedules against permission the user has already
               given. Nothing here can raise the system prompt, so opening the
               app never costs the user a dialog they did not ask for. */
            await self.readPermission(ownerID: ownerID)
            guard self.schedulingIsCurrent(ownerID: ownerID, generation: generation), self.authorised else { return }
            await self.reschedule(nudges, ownerID: ownerID, generation: generation)
        }
        scheduling = work
        await work.value
    }

    // MARK: - Delivery

    private func reschedule(
        _ nudges: [DailyNudges.Nudge],
        ownerID: UUID,
        generation: UInt64
    ) async {
        guard schedulingIsCurrent(ownerID: ownerID, generation: generation) else { return }
        await clearScheduled(for: ownerID, generation: generation)
        guard schedulingIsCurrent(ownerID: ownerID, generation: generation) else { return }

        // Hour and minute only: the system resolves the next moment that
        // matches, so this can never be scheduled for a time already gone.
        let components = DailyNudges.eveningSlot

        for nudge in nudges {
            let content = UNMutableNotificationContent()
            /* Composed here rather than stored on the nudge, so the reminder
               arrives in the language the app is set to. */
            content.title = NudgeCopy.title(nudge, LanguageState.shared)
            content.body = NudgeCopy.body(nudge, LanguageState.shared)
            content.sound = .default
            content.userInfo = [
                "kind": nudge.kind.rawValue,
                "owner_id": ownerID.uuidString.lowercased()
            ]

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = Self.notificationIdentifier(ownerID: ownerID, kind: nudge.kind)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            guard schedulingIsCurrent(ownerID: ownerID, generation: generation) else { return }
            try? await notificationScheduler.add(request)
            guard schedulingIsCurrent(ownerID: ownerID, generation: generation) else {
                notificationScheduler.removePendingNotificationRequests(withIdentifiers: [identifier])
                return
            }
        }
    }

    private func clearScheduled(for ownerID: UUID, generation: UInt64? = nil) async {
        let existing = await notificationScheduler.pendingNotificationIdentifiers()
        guard generation == nil || schedulingIsCurrent(ownerID: ownerID, generation: generation!) else { return }
        let prefix = Self.identifierPrefix + ownerID.uuidString.lowercased() + "."
        let mine = existing.filter { $0.hasPrefix(prefix) }
        notificationScheduler.removePendingNotificationRequests(withIdentifiers: mine)
    }

    /// Account boundaries cannot wait for an asynchronous notification-centre
    /// inventory: the old process may terminate or a due reminder may fire
    /// before that query returns. Remove every currently supported identifier
    /// immediately; reconciliation still follows for legacy and future IDs.
    private func removeKnownScheduledNotifications(for ownerID: UUID) {
        let identifiers = [
            DailyNudges.Kind.proteinShort,
            DailyNudges.Kind.creatineMissed
        ].map { Self.notificationIdentifier(ownerID: ownerID, kind: $0) }
        notificationScheduler.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func invalidateScheduling() {
        schedulingGeneration &+= 1
        scheduling?.cancel()
        scheduling = nil
    }

    private func invalidateAccountCleanup() {
        accountCleanupGeneration &+= 1
        accountCleanup?.cancel()
        accountCleanup = nil
    }

    private func schedulingIsCurrent(ownerID: UUID, generation: UInt64) -> Bool {
        !Task.isCancelled && activeOwnerID == ownerID && schedulingGeneration == generation
    }

    private func reconcileScheduledAsynchronously(activeOwnerID ownerID: UUID?) {
        let generation = accountCleanupGeneration
        accountCleanup = Task { @MainActor [weak self] in
            await self?.reconcileScheduledNotifications(
                activeOwnerID: ownerID,
                generation: generation
            )
        }
    }

    private func reconcileScheduledNotifications(
        activeOwnerID expectedOwnerID: UUID?,
        generation: UInt64
    ) async {
        let existing = await notificationScheduler.pendingNotificationIdentifiers()
        guard accountCleanupIsCurrent(
            activeOwnerID: expectedOwnerID,
            generation: generation
        ) else { return }
        let activePrefix = expectedOwnerID.map {
            Self.identifierPrefix + $0.uuidString.lowercased() + "."
        }
        let stale = existing.filter { identifier in
            guard identifier.hasPrefix(Self.identifierPrefix) else { return false }
            guard let activePrefix else { return true }
            return identifier.hasPrefix(activePrefix) == false
        }
        guard stale.isEmpty == false else { return }
        notificationScheduler.removePendingNotificationRequests(withIdentifiers: stale)
    }

    private func accountCleanupIsCurrent(
        activeOwnerID expectedOwnerID: UUID?,
        generation: UInt64
    ) -> Bool {
        !Task.isCancelled
            && activeOwnerID == expectedOwnerID
            && accountCleanupGeneration == generation
    }

    private static func readKey(for ownerID: UUID) -> String {
        "apex.nudges.read." + ownerID.uuidString.lowercased()
    }
}
