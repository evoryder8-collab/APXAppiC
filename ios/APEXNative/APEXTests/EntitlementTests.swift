import XCTest
@testable import APEX

final class EntitlementTests: XCTestCase {

    private func date(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    }

    func testTheFourBespokeAccountsNeverSeeAPriceOrACountdown() {
        // Founding outranks every other reason, including an expired trial,
        // so a bespoke account is never shown a paywall by accident.
        let access = Entitlement.access(
            foundingMember: true,
            developerCodeRedeemed: false,
            subscribedTier: nil,
            subscriptionExpires: nil,
            trialStarted: date(daysAgo: 400)
        )
        XCTAssertEqual(access, .founding)
        XCTAssertTrue(Entitlement.isUnlocked(access))
    }

    func testTheTrialRunsForOneTrainingWeekThenAsks() {
        func remaining(_ daysAgo: Int) -> Entitlement.Access {
            Entitlement.access(
                foundingMember: false, developerCodeRedeemed: false,
                subscribedTier: nil, subscriptionExpires: nil,
                trialStarted: date(daysAgo: daysAgo))
        }
        XCTAssertEqual(remaining(0), .trial(daysRemaining: 7))
        XCTAssertEqual(remaining(6), .trial(daysRemaining: 1))
        XCTAssertEqual(remaining(7), .expired)
        XCTAssertEqual(remaining(90), .expired)
    }

    func testAnUnopenedAccountHasNotBurnedItsTrial() {
        // The clock starts on first open, not on creation, so an account made
        // in advance does not expire sitting unopened.
        XCTAssertEqual(
            Entitlement.access(
                foundingMember: false, developerCodeRedeemed: false,
                subscribedTier: nil, subscriptionExpires: nil, trialStarted: nil),
            .trial(daysRemaining: 7)
        )
    }

    func testAPayingCustomerIsNotLockedOutOverAMissingExpiry() {
        // Failing open is the right way round here: a missing field should
        // never lock out someone who has paid.
        XCTAssertEqual(
            Entitlement.access(
                foundingMember: false, developerCodeRedeemed: false,
                subscribedTier: .premium, subscriptionExpires: nil, trialStarted: nil),
            .subscribed(.premium)
        )
        // An expiry in the past does end access.
        XCTAssertEqual(
            Entitlement.access(
                foundingMember: false, developerCodeRedeemed: false,
                subscribedTier: .premium, subscriptionExpires: date(daysAgo: 1),
                trialStarted: date(daysAgo: 400)),
            .expired
        )
    }

    func testYearlyPricingSavesWhatTheLabelWillClaim() {
        // 9.90 a month is 118.80 a year, against 79 for the yearly plan.
        XCTAssertEqual(Entitlement.price(.premium).yearlySavingPercent, 34)
        // 29 a month is 348 a year, against 229 for the yearly plan.
        XCTAssertEqual(Entitlement.price(.coach).yearlySavingPercent, 34)
    }

    func testCoachSeatsAreFreeUpToThreeThenSixFrancsEach() {
        XCTAssertEqual(Entitlement.coachMonthlyRappen(seats: 1), 2_900)
        XCTAssertEqual(Entitlement.coachMonthlyRappen(seats: 3), 2_900)
        XCTAssertEqual(Entitlement.coachMonthlyRappen(seats: 4), 3_500)
        XCTAssertEqual(Entitlement.coachMonthlyRappen(seats: 10), 7_100)
    }

    func testCoachToolsNeedTheCoachTierButMealListsDoNot() {
        let premium = Entitlement.Access.subscribed(.premium)
        let coach = Entitlement.Access.subscribed(.coach)
        XCTAssertFalse(Entitlement.allows(.clientRoster, access: premium))
        XCTAssertTrue(Entitlement.allows(.clientRoster, access: coach))
        // Predefined meal lists are useful to anyone who eats the same things
        // most weeks, so they are not a coach feature at all.
        XCTAssertFalse(
            Entitlement.CoachFeature.allCases.contains { $0.rawValue.contains("meal") },
            "meal lists must stay available to individual accounts"
        )
        // The trial shows everything, including the coach tools.
        XCTAssertTrue(Entitlement.allows(.planAuthoring, access: .trial(daysRemaining: 3)))
        XCTAssertFalse(Entitlement.allows(.planAuthoring, access: .expired))
    }

    @MainActor
    func testProfilelessAccountCannotInheritAnotherAccountsAccess() throws {
        let store = EntitlementStore()
        var founder = try XCTUnwrap(APEXDebugFixture.dashboard().profile)
        founder.foundingMember = true

        store.resolve(profile: founder)
        XCTAssertEqual(store.access, .founding)

        let profilelessAccount = UUID()
        store.prepareForAccount(profilelessAccount)
        XCTAssertEqual(store.resolvedUserID, profilelessAccount)
        XCTAssertEqual(store.access, .trial(daysRemaining: Entitlement.trialDays))
        XCTAssertNotEqual(store.access, .founding)

        store.resetAccount()
        XCTAssertNil(store.resolvedUserID)
        XCTAssertEqual(store.access, .trial(daysRemaining: Entitlement.trialDays))
    }

    func testAuthCallbackDropsTheOldAccountBeforeAFallibleDashboardRefresh() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSession = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let start = try XCTUnwrap(appSession.range(of: "func handleAuthCallback"))
        let end = try XCTUnwrap(
            appSession.range(of: "func toggleMeal", range: start.upperBound..<appSession.endIndex)
        )
        let callback = String(appSession[start.lowerBound..<end.lowerBound])

        let reset = try XCTUnwrap(callback.range(of: "EntitlementStore.shared.resetAccount()"))
        let authenticate = try XCTUnwrap(
            callback.range(of: "let userID = try await service.handleAuthCallback(url)")
        )
        let scope = try XCTUnwrap(
            callback.range(of: "EntitlementStore.shared.prepareForAccount(userID)")
        )
        let clear = try XCTUnwrap(callback.range(of: "data = .empty"))
        let refresh = try XCTUnwrap(
            callback.range(of: "try await refreshDashboard(expectedUserID: userID)")
        )

        XCTAssertLessThan(reset.lowerBound, authenticate.lowerBound)
        XCTAssertLessThan(authenticate.lowerBound, scope.lowerBound)
        XCTAssertLessThan(scope.lowerBound, clear.lowerBound)
        XCTAssertLessThan(clear.lowerBound, refresh.lowerBound)
        XCTAssertTrue(callback.contains("var switchedAccounts = false"))
        XCTAssertTrue(callback.contains("switchedAccounts = true"))
        XCTAssertTrue(callback.contains("if !switchedAccounts {"))
        XCTAssertTrue(callback.contains("await resolveEntitlements()"))
        XCTAssertTrue(callback.contains("if route == .portal { await startRealtimeSync() }"))
    }

    func testAccountGenerationRejectsACompletionFromBeforeAnAuthBoundary() {
        var generation = AccountGenerationGate()
        let accountA = generation.token
        XCTAssertTrue(generation.accepts(accountA))

        generation.advance()
        let capturedDuringTransition = generation.token
        XCTAssertTrue(generation.accepts(capturedDuringTransition))
        generation.advance()

        XCTAssertFalse(generation.accepts(accountA))
        XCTAssertFalse(generation.accepts(capturedDuringTransition))
        XCTAssertTrue(generation.accepts(generation.token))
    }

    func testRefreshAndInductionMutationsCheckTheAccountGeneration() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        func body(_ start: String, before end: String) throws -> String {
            let lower = try XCTUnwrap(source.range(of: start))
            let upper = try XCTUnwrap(source.range(of: end, range: lower.upperBound..<source.endIndex))
            return String(source[lower.lowerBound..<upper.lowerBound])
        }

        for boundary in ["func signIn(email:", "func signUp(email:", "func signInWithApple(", "func signOut()", "func handleAuthCallback("] {
            let start = try XCTUnwrap(source.range(of: boundary))
            let tail = String(source[start.lowerBound...])
            XCTAssertTrue(
                tail.prefix(500).contains("var accountToken = beginAccountBoundary()"),
                "missing account boundary in \(boundary)"
            )
            XCTAssertTrue(
                tail.prefix(1_500).contains("accountToken = completeAccountBoundary()"),
                "missing completed account boundary in \(boundary)"
            )
        }

        let refresh = try body("func refreshDashboard", before: "/// Store a new profile picture")
        XCTAssertTrue(refresh.contains("let accountToken = accountGeneration.token"))
        XCTAssertTrue(refresh.contains("guard accountGeneration.accepts(accountToken) else { throw CancellationError() }"))
        XCTAssertTrue(refresh.contains("let currentUserID = await service.currentUserID()"))
        XCTAssertTrue(refresh.contains("TrainingInduction.isCompatibleDashboard(next, userID: currentUserID)"))

        let mutations = [
            (try body("private func submitInduction", before: "/// Deterministic authenticated first-run"), 6),
            (try body("func installInductionPlan", before: "private func applyInductionPlan"), 8),
            (try body("func restoreOriginalProgramme", before: "/// Store a rewritten predefined list"), 2),
        ]
        for (mutation, minimumChecks) in mutations {
            XCTAssertTrue(mutation.contains("let accountToken = accountGeneration.token"))
            XCTAssertGreaterThanOrEqual(
                mutation.components(separatedBy: "guard accountGeneration.accepts(accountToken) else { return }").count - 1,
                minimumChecks
            )
        }
    }

}

/// A dashboard cached by an earlier build has none of the entitlement columns.
/// Losing the whole profile over an absent flag would empty the app.
final class ProfileEntitlementDecodingTests: XCTestCase {

    func testAProfileFromBeforeTheseColumnsExistedStillDecodes() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "user_id": "00000000-0000-0000-0000-000000000002",
          "persona": "constantine",
          "display_name": "Constantine",
          "sex": "male",
          "weight_kg": 78,
          "body_fat_pct": 18,
          "height_cm": 183,
          "birthdate": "1992-07-25",
          "activity_level": "moderate",
          "goal": "recomp",
          "training_time": "19:00",
          "baseline_date": "2026-01-01",
          "profile_note": "",
          "seed_version": 1,
          "calibration_k": 1.0,
          "calibration_history": [],
          "updated_at": "2026-01-01T00:00:00Z"
        }
        """
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        XCTAssertNil(profile.foundingMember)
        XCTAssertNil(profile.trialStartedAt)
        // And an unknown flag must not accidentally grant permanent free access.
        XCTAssertEqual(
            Entitlement.access(
                foundingMember: profile.foundingMember ?? false,
                developerCodeRedeemed: false,
                subscribedTier: nil, subscriptionExpires: nil, trialStarted: nil),
            .trial(daysRemaining: Entitlement.trialDays)
        )
    }
}
