import XCTest
import UserNotifications
@testable import APEX

final class DailyNudgesTests: XCTestCase {

    func testTheSingleSittingCapScalesWithBodyweight() {
        // Roughly 0.4 g per kg is where muscle protein synthesis saturates in
        // one meal, so 40 g is a sensible catch-up at 100 kg and far too much
        // of a day's target at 45 kg.
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 50), 20)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 60), 25)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 70), 30)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 80), 30)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 100), 40)
        // And it stays sane at both extremes rather than following the maths off a cliff.
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 35), 20)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 200), 60)
        XCTAssertEqual(DailyNudges.singleSittingCapGrams(bodyweightKG: 0), 30)
    }

    func testProteinNudgeIsStricterWhenLosingWeight() {
        // 80% of target: fine when maintaining, worth saying on a cut, because
        // that is where protein is holding muscle rather than adding it.
        XCTAssertNil(DailyNudges.proteinShortfall(
            consumedG: 120, targetG: 150, goal: "maintain", bodyweightKG: 80))
        XCTAssertNotNil(DailyNudges.proteinShortfall(
            consumedG: 120, targetG: 150, goal: "recomp", bodyweightKG: 80))
    }

    func testNoNudgeWhenTheDayWentFine() {
        XCTAssertNil(DailyNudges.proteinShortfall(
            consumedG: 155, targetG: 150, goal: "cut", bodyweightKG: 80))
        // A reminder that fires most days is one people switch off.
        XCTAssertNil(DailyNudges.proteinShortfall(
            consumedG: 140, targetG: 150, goal: "cut", bodyweightKG: 80))
    }

    func testTheProteinNudgeCarriesACeilingNotJustAShortfall() {
        let nudge = DailyNudges.proteinShortfall(
            consumedG: 40, targetG: 160, goal: "fat_loss", bodyweightKG: 70)
        guard let nudge else { return XCTFail("no nudge for a 120 g shortfall") }
        XCTAssertEqual(nudge.shortfallG, 120)
        // The predictable response to "you are short" is to drink the whole
        // deficit at once, so the number to have tonight is capped.
        XCTAssertEqual(nudge.capG, 30)
        XCTAssertEqual(nudge.tonightG, 30)
        XCTAssertTrue(nudge.losingWeight)
    }

    func testASmallShortfallIsNotInflatedToTheCap() {
        // Tonight is the shortfall or the ceiling, whichever is smaller. Being
        // 25 g under should not turn into an instruction to eat the full 30.
        let small = DailyNudges.proteinShortfall(
            consumedG: 75, targetG: 100, goal: "cut", bodyweightKG: 70)
        XCTAssertEqual(small?.capG, 30)
        XCTAssertEqual(small?.tonightG, 25)
        // And a large shortfall is held down to the ceiling rather than repeated whole.
        let large = DailyNudges.proteinShortfall(
            consumedG: 88, targetG: 160, goal: "cut", bodyweightKG: 70)
        XCTAssertEqual(large?.shortfallG, 72)
        XCTAssertEqual(large?.tonightG, 30)
        XCTAssertNil(
            DailyNudges.proteinShortfall(consumedG: 150, targetG: 160, goal: "cut", bodyweightKG: 70),
            "10 g under is not worth a notification"
        )
    }

    func testCreatineNudgeOnlyForPeopleWhoActuallyTakeIt() {
        XCTAssertNil(DailyNudges.creatineMissed(loggedToday: false, inStack: false))
        XCTAssertNil(DailyNudges.creatineMissed(loggedToday: true, inStack: true))
        XCTAssertNotNil(DailyNudges.creatineMissed(loggedToday: false, inStack: true))
    }

    func testTheEveningIsLateEnoughToJudgeAndEarlyEnoughToAct() {
        XCTAssertGreaterThanOrEqual(DailyNudges.eveningHour, 19)
        XCTAssertLessThanOrEqual(DailyNudges.eveningHour, 20)
    }
}

extension DailyNudgesTests {

    /// The trigger must carry no date, only a time.
    ///
    /// This is the shape of the bug rather than one instance of it: a calendar
    /// trigger that names a year, month or day can name one that has passed,
    /// and a trigger whose moment has gone is accepted by the system and then
    /// never delivered. Leaving the date out is what makes that impossible.
    func testTheEveningTriggerCarriesNoDate() {
        let slot = DailyNudges.eveningSlot
        XCTAssertEqual(slot.hour, DailyNudges.eveningHour)
        XCTAssertEqual(slot.minute, DailyNudges.eveningMinute)
        XCTAssertNil(slot.year)
        XCTAssertNil(slot.month)
        XCTAssertNil(slot.day)
    }

    /// Whatever the clock says, the next matching moment is still ahead.
    func testTheSlotAlwaysResolvesToAFutureMoment() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        // Including the times that used to produce a dead trigger, and the last
        // minute of a month, where a hand-rolled date could land on the 32nd.
        for (day, hour, minute) in [(21, 9, 0), (21, 19, 29), (21, 20, 15), (21, 23, 50), (31, 22, 0)] {
            let now = calendar.date(from: DateComponents(
                year: 2026, month: 8, day: day, hour: hour, minute: minute
            ))!
            let next = calendar.nextDate(
                after: now,
                matching: DailyNudges.eveningSlot,
                matchingPolicy: .nextTime
            )
            XCTAssertNotNil(next, "no next occurrence from \(now)")
            XCTAssertGreaterThan(next!, now, "resolved a moment that has already passed")
        }
    }
}

@MainActor
extension DailyNudgesTests {

    func testReadStateIsScopedToTheActiveOwner() {
        let defaults = isolatedDefaults()
        let centre = NudgeCenter(
            notificationScheduler: RecordingNudgeNotificationScheduler(),
            defaults: defaults
        )
        let firstOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let nudge = DailyNudges.Nudge(kind: .proteinShort, date: "2026-09-02")

        centre.activate(ownerID: firstOwner)
        centre.markRead(nudge)

        centre.activate(ownerID: secondOwner)
        XCTAssertFalse(centre.isRead(nudge))

        centre.activate(ownerID: firstOwner)
        XCTAssertTrue(centre.isRead(nudge))
    }

    func testAccountBoundaryClearsTheBellSynchronously() async {
        let defaults = isolatedDefaults()
        let centre = NudgeCenter(
            notificationScheduler: RecordingNudgeNotificationScheduler(),
            defaults: defaults
        )
        centre.activate(ownerID: UUID())
        await centre.refresh(
            proteinConsumedG: 0,
            proteinTargetG: 150,
            goal: "cut",
            bodyweightKG: 80,
            creatineInStack: false,
            creatineLoggedToday: true
        )
        XCTAssertFalse(centre.pending.isEmpty)

        centre.clearAccountBoundary()

        XCTAssertTrue(centre.pending.isEmpty)
        XCTAssertEqual(centre.unreadCount, 0)
    }

    func testNotificationIdentifiersAreQualifiedByOwner() {
        let firstOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        XCTAssertEqual(
            NudgeCenter.notificationIdentifier(ownerID: firstOwner, kind: .proteinShort),
            "apex.nudge.00000000-0000-0000-0000-000000000001.proteinShort"
        )
        XCTAssertNotEqual(
            NudgeCenter.notificationIdentifier(ownerID: firstOwner, kind: .proteinShort),
            NudgeCenter.notificationIdentifier(ownerID: secondOwner, kind: .proteinShort)
        )
    }

    func testColdLaunchActivationRemovesAnotherOwnersPendingNotifications() async {
        let defaults = isolatedDefaults()
        let scheduler = RecordingNudgeNotificationScheduler()
        let centre = NudgeCenter(notificationScheduler: scheduler, defaults: defaults)
        let firstOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let firstIdentifier = NudgeCenter.notificationIdentifier(
            ownerID: firstOwner,
            kind: .proteinShort
        )
        let secondIdentifier = NudgeCenter.notificationIdentifier(
            ownerID: secondOwner,
            kind: .creatineMissed
        )
        let unrelatedIdentifier = "another.app.reminder"
        scheduler.pendingIdentifiers = [firstIdentifier, secondIdentifier, unrelatedIdentifier]
        let removed = expectation(description: "foreign APEX notification removed")
        scheduler.onRemoval = { identifiers in
            if identifiers.contains(firstIdentifier) { removed.fulfill() }
        }

        /* A fresh NudgeCenter has no in-memory previousOwnerID. Activating B
           must still reconcile notification-center state left by A before the
           previous process was terminated. */
        centre.activate(ownerID: secondOwner)
        await fulfillment(of: [removed], timeout: 1)

        XCTAssertEqual(
            Set(scheduler.pendingIdentifiers),
            Set([secondIdentifier, unrelatedIdentifier]),
            "activation should preserve this owner's reminder and notifications outside APEX"
        )
    }

    func testAccountSwitchSynchronouslyRemovesThePreviousOwnersKnownNotifications() {
        let defaults = isolatedDefaults()
        let scheduler = RecordingNudgeNotificationScheduler()
        let centre = NudgeCenter(notificationScheduler: scheduler, defaults: defaults)
        let firstOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let firstIdentifiers = [
            NudgeCenter.notificationIdentifier(ownerID: firstOwner, kind: .proteinShort),
            NudgeCenter.notificationIdentifier(ownerID: firstOwner, kind: .creatineMissed)
        ]
        let secondIdentifier = NudgeCenter.notificationIdentifier(
            ownerID: secondOwner,
            kind: .proteinShort
        )
        let unrelatedIdentifier = "another.app.reminder"

        centre.activate(ownerID: firstOwner)
        scheduler.pendingIdentifiers = firstIdentifiers + [secondIdentifier, unrelatedIdentifier]

        centre.activate(ownerID: secondOwner)

        XCTAssertEqual(
            Set(scheduler.pendingIdentifiers),
            Set([secondIdentifier, unrelatedIdentifier]),
            "Account A's known reminders must be gone before Account B becomes usable"
        )
    }

    func testLogoutSynchronouslyRemovesTheActiveOwnersKnownNotifications() {
        let defaults = isolatedDefaults()
        let scheduler = RecordingNudgeNotificationScheduler()
        let centre = NudgeCenter(notificationScheduler: scheduler, defaults: defaults)
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let ownerIdentifiers = [
            NudgeCenter.notificationIdentifier(ownerID: ownerID, kind: .proteinShort),
            NudgeCenter.notificationIdentifier(ownerID: ownerID, kind: .creatineMissed)
        ]
        let unrelatedIdentifier = "another.app.reminder"

        centre.activate(ownerID: ownerID)
        scheduler.pendingIdentifiers = ownerIdentifiers + [unrelatedIdentifier]

        centre.clearAccountBoundary()

        XCTAssertEqual(
            scheduler.pendingIdentifiers,
            [unrelatedIdentifier],
            "logout must not leave a health reminder able to fire after the process exits"
        )
    }

    func testDelayedCleanupCannotRemoveNotificationsWhenTheOwnerBecomesActiveAgain() async {
        let defaults = isolatedDefaults()
        let scheduler = RecordingNudgeNotificationScheduler()
        let centre = NudgeCenter(notificationScheduler: scheduler, defaults: defaults)
        let firstOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        /* Let first activation's cold-launch reconciliation finish so the test
           below isolates the A -> B -> A race rather than relying on task
           scheduling order. */
        let initialInspection = expectation(description: "initial notification inspection")
        scheduler.onPendingRequests = { initialInspection.fulfill() }
        centre.activate(ownerID: firstOwner)
        await fulfillment(of: [initialInspection], timeout: 1)

        let firstIdentifier = NudgeCenter.notificationIdentifier(
            ownerID: firstOwner,
            kind: .proteinShort
        )
        scheduler.pendingIdentifiers = [firstIdentifier]
        let delayedInspection = expectation(description: "delayed cleanup inspected notifications")
        scheduler.onPendingRequests = {
            /* Simulate A becoming current again while B's cleanup is suspended
               inside the notification-center query. Its freshly restored
               reminder must survive B's now-stale asynchronous cleanup. */
            centre.activate(ownerID: firstOwner)
            scheduler.pendingIdentifiers.append(firstIdentifier)
            delayedInspection.fulfill()
        }

        centre.activate(ownerID: secondOwner)
        await fulfillment(of: [delayedInspection], timeout: 1)

        XCTAssertTrue(
            scheduler.pendingIdentifiers.contains(firstIdentifier),
            "cleanup initiated for B must not remove A's reminder after A becomes active again"
        )
    }

    func testOlderOwnerRescheduleCannotPublishAfterANewerOwnerActivates() async {
        let defaults = isolatedDefaults()
        let scheduler = RecordingNudgeNotificationScheduler()
        let centre = NudgeCenter(notificationScheduler: scheduler, defaults: defaults)
        let firstOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        scheduler.onPendingRequests = { centre.activate(ownerID: secondOwner) }
        centre.activate(ownerID: firstOwner)

        await centre.refresh(
            proteinConsumedG: 0,
            proteinTargetG: 150,
            goal: "cut",
            bodyweightKG: 80,
            creatineInStack: false,
            creatineLoggedToday: true
        )

        XCTAssertTrue(scheduler.addedIdentifiers.isEmpty)
        XCTAssertTrue(centre.pending.isEmpty)
    }

    func testExplicitPermissionRequestEstablishesTheOwningAccount() async {
        let defaults = isolatedDefaults()
        let scheduler = RecordingNudgeNotificationScheduler()
        let centre = NudgeCenter(notificationScheduler: scheduler, defaults: defaults)
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let granted = await centre.requestPermission(ownerID: ownerID)
        XCTAssertTrue(granted)
        await centre.refresh(
            proteinConsumedG: 0,
            proteinTargetG: 150,
            goal: "cut",
            bodyweightKG: 80,
            creatineInStack: false,
            creatineLoggedToday: true
        )

        XCTAssertTrue(
            scheduler.addedIdentifiers.allSatisfy { $0.contains(ownerID.uuidString.lowercased()) },
            "consent-time permission must schedule only for the account that initiated it"
        )
        XCTAssertFalse(scheduler.addedIdentifiers.isEmpty)
    }

    func testDelayedDeliveryTapCannotAdoptTheNewActiveOwner() async {
        let defaults = isolatedDefaults()
        let scheduler = RecordingNudgeNotificationScheduler()
        let centre = NudgeCenter(notificationScheduler: scheduler, defaults: defaults)
        let firstOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        /* The sheet captured A at tap time, but its unstructured Task did not
           start until B had become active. It must not ask permission or
           schedule B's reminders on behalf of A's stale interaction. */
        centre.activate(ownerID: firstOwner)
        centre.activate(ownerID: secondOwner)
        scheduler.requestPermissionCallCount = 0

        await centre.enableEveningDelivery(ownerID: firstOwner)

        XCTAssertEqual(scheduler.requestPermissionCallCount, 0)
        XCTAssertTrue(scheduler.addedIdentifiers.isEmpty)
    }

    func testDelayedSheetReadCannotMarkTheNewOwnersNudgesRead() async {
        let defaults = isolatedDefaults()
        let scheduler = RecordingNudgeNotificationScheduler()
        let centre = NudgeCenter(notificationScheduler: scheduler, defaults: defaults)
        let firstOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        centre.activate(ownerID: secondOwner)
        await centre.refresh(
            proteinConsumedG: 0,
            proteinTargetG: 150,
            goal: "cut",
            bodyweightKG: 80,
            creatineInStack: false,
            creatineLoggedToday: true
        )
        XCTAssertEqual(centre.unreadCount, 1)
        scheduler.readPermissionCallCount = 0

        centre.markAllRead(ownerID: firstOwner)
        await centre.readPermission(ownerID: firstOwner)

        XCTAssertEqual(centre.unreadCount, 1)
        XCTAssertEqual(scheduler.readPermissionCallCount, 0)
    }

    func testNudgeSheetCapturesAnAccountLeaseBeforeStartingAsyncWork() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Portal/NudgeSheet.swift"),
            encoding: .utf8
        ).filter { !$0.isWhitespace }

        XCTAssertTrue(source.contains(
            "guardletoperation=session.accountOperationLease()else{return}Task{guardsession.accountOperationIsCurrent(operation)else{return}awaitnudges.enableEveningDelivery(ownerID:operation.ownerID)"
        ))
        XCTAssertTrue(source.contains(
            ".task{guardletoperation=session.accountOperationLease()else{return}guardsession.accountOperationIsCurrent(operation)else{return}nudges.markAllRead(ownerID:operation.ownerID)awaitnudges.readPermission(ownerID:operation.ownerID)"
        ))
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "DailyNudgesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
private final class RecordingNudgeNotificationScheduler: NudgeNotificationScheduling {
    var permission = NudgeNotificationPermission(authorised: true, canAsk: false)
    var pendingIdentifiers: [String] = []
    var addedIdentifiers: [String] = []
    var onPendingRequests: (() -> Void)?
    var onRemoval: (([String]) -> Void)?
    var readPermissionCallCount = 0
    var requestPermissionCallCount = 0

    func readPermission() async -> NudgeNotificationPermission {
        readPermissionCallCount += 1
        return permission
    }

    func requestPermission() async -> Bool {
        requestPermissionCallCount += 1
        permission = NudgeNotificationPermission(authorised: true, canAsk: false)
        return true
    }

    func pendingNotificationIdentifiers() async -> [String] {
        let action = onPendingRequests
        onPendingRequests = nil
        action?()
        return pendingIdentifiers
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        pendingIdentifiers.removeAll { identifiers.contains($0) }
        onRemoval?(identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedIdentifiers.append(request.identifier)
        pendingIdentifiers.append(request.identifier)
    }
}
