import Foundation
import UserNotifications

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
    private(set) var authorised = false

    /// Nudges the user has already opened, so the bell stops claiming they are new.
    private var readIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.readKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.readKey) }
    }
    private static let readKey = "apex.nudges.read"
    private static let identifierPrefix = "apex.nudge."

    var unreadCount: Int { pending.filter { !readIDs.contains($0.id) }.count }

    func isRead(_ nudge: DailyNudges.Nudge) -> Bool { readIDs.contains(nudge.id) }

    func markRead(_ nudge: DailyNudges.Nudge) { readIDs.insert(nudge.id) }

    func markAllRead() { readIDs.formUnion(pending.map(\.id)) }

    /// Turn on evening delivery from an explicit tap, and schedule immediately
    /// so the first reminder is not lost to the gap before the next refresh.
    func enableEveningDelivery() async {
        guard await requestPermission() else { return }
        await reschedule(pending)
    }

    /// Whether the system prompt has never been shown, so the sheet knows to
    /// offer it rather than silently doing nothing.
    private(set) var canAskForPermission = false

    /// Read the current state without prompting for anything.
    func readPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        authorised = [.authorized, .provisional, .ephemeral].contains(status)
        canAskForPermission = status == .notDetermined
    }

    /// Ask, only ever from an explicit tap.
    ///
    /// Prompting on first launch, before the app has done anything for anyone,
    /// is how an app earns a permanent no. The bell works either way; the
    /// system prompt only buys the evening delivery.
    @discardableResult
    func requestPermission() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        authorised = (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
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
        pending = nudges

        guard !nudges.isEmpty else {
            await clearScheduled()
            return
        }
        /* Only ever schedules against permission the user has already given.
           Nothing here can raise the system prompt, so opening the app never
           costs the user a dialog they did not ask for. */
        await readPermission()
        guard authorised else { return }
        await reschedule(nudges)
    }

    // MARK: - Delivery

    private func reschedule(_ nudges: [DailyNudges.Nudge]) async {
        let centre = UNUserNotificationCenter.current()
        await clearScheduled()

        // Past the evening slot the day is effectively over; a reminder at
        // midnight helps nobody, so it waits for tomorrow.
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = DailyNudges.eveningHour
        components.minute = DailyNudges.eveningMinute

        for nudge in nudges {
            let content = UNMutableNotificationContent()
            /* Composed here rather than stored on the nudge, so the reminder
               arrives in the language the app is set to. */
            content.title = NudgeCopy.title(nudge, LanguageState.shared)
            content.body = NudgeCopy.body(nudge, LanguageState.shared)
            content.sound = .default
            content.userInfo = ["kind": nudge.kind.rawValue]

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + nudge.kind.rawValue,
                content: content,
                trigger: trigger
            )
            try? await centre.add(request)
        }
    }

    private func clearScheduled() async {
        let centre = UNUserNotificationCenter.current()
        let existing = await centre.pendingNotificationRequests()
        let mine = existing.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        centre.removePendingNotificationRequests(withIdentifiers: mine)
    }
}
