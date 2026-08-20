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

    /// Ask once, and only when there is something worth sending. Prompting on
    /// first launch, before the app has done anything for anyone, is how an app
    /// earns a permanent no.
    func requestPermissionIfNeeded() async {
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            authorised = (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            authorised = true
        default:
            authorised = false
        }
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
        await requestPermissionIfNeeded()
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
