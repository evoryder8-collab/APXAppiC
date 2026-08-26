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
            betaCodeRedeemed: false,
            subscribedTier: nil,
            subscriptionExpires: nil
        )
        XCTAssertEqual(access, .founding)
        XCTAssertTrue(Entitlement.isUnlocked(access))
    }

    func testBetaDoesNotGrantAnAutomaticTrial() {
        let access = Entitlement.access(
            foundingMember: false,
            betaCodeRedeemed: false,
            subscribedTier: nil,
            subscriptionExpires: nil
        )
        XCTAssertEqual(access, .locked)
        XCTAssertFalse(Entitlement.isUnlocked(access))
    }

    func testAClaimedBetaCodeUnlocksOnlyThroughTheAccountProfile() {
        XCTAssertEqual(
            Entitlement.access(
                foundingMember: false,
                betaCodeRedeemed: true,
                subscribedTier: nil,
                subscriptionExpires: nil
            ),
            .beta
        )
    }

    func testAPayingCustomerIsNotLockedOutOverAMissingExpiry() {
        // Failing open is the right way round here: a missing field should
        // never lock out someone who has paid.
        XCTAssertEqual(
            Entitlement.access(
                foundingMember: false, betaCodeRedeemed: false,
                subscribedTier: .premium, subscriptionExpires: nil),
            .subscribed(.premium)
        )
        // An expiry in the past does end access.
        XCTAssertEqual(
            Entitlement.access(
                foundingMember: false, betaCodeRedeemed: false,
                subscribedTier: .premium, subscriptionExpires: date(daysAgo: 1)),
            .locked
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
        // A claimed beta account is deliberately full-access during beta.
        XCTAssertTrue(Entitlement.allows(.planAuthoring, access: .beta))
        XCTAssertFalse(Entitlement.allows(.planAuthoring, access: .locked))
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
        XCTAssertEqual(store.access, .locked)
        XCTAssertNotEqual(store.access, .founding)

        store.resetAccount()
        XCTAssertNil(store.resolvedUserID)
        XCTAssertEqual(store.access, .locked)
    }

    @MainActor
    func testHistoricalTrialDataCannotUnlockTheBetaBuild() throws {
        let store = EntitlementStore()
        var profile = try XCTUnwrap(APEXDebugFixture.dashboard().profile)
        profile.foundingMember = false
        profile.betaCodeRedeemed = false
        profile.subscriptionTier = nil
        profile.subscriptionExpiresAt = nil
        profile.trialStartedAt = Date().ISO8601Format()

        store.resolve(profile: profile)

        XCTAssertEqual(store.access, .locked)
        XCTAssertFalse(store.isUnlocked)
    }

    func testBetaAuthorityAndCopyStayServerScoped() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlement = try String(contentsOf: nativeRoot.appending(path: "APEX/Core/Engine/Entitlement.swift"))
        let store = try String(contentsOf: nativeRoot.appending(path: "APEX/Core/Engine/EntitlementStore.swift"))
        let session = try String(contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift"))
        let paywall = try String(contentsOf: nativeRoot.appending(path: "APEX/Features/Settings/PaywallView.swift"))
        let auth = try String(contentsOf: nativeRoot.appending(path: "APEX/Features/Auth/EmailAuthView.swift"))
        let service = try String(contentsOf: nativeRoot.appending(path: "APEX/Core/Networking/SupabaseService.swift"))
        let migration = try String(contentsOf: nativeRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "supabase/migrations/029_account_scoped_beta_entitlements.sql"))

        XCTAssertFalse(entitlement.contains("trialDays"))
        XCTAssertFalse(entitlement.contains("case trial"))
        XCTAssertFalse(store.contains("UserDefaults.standard"))
        XCTAssertFalse(store.contains("developerCodeHash"))
        XCTAssertFalse(session.contains("profile.trialStartedAt ="))
        XCTAssertFalse(paywall.contains("days left in your trial"))
        XCTAssertFalse(paywall.contains("Your trial has ended"))
        XCTAssertFalse(auth.contains("Seven days, everything unlocked"))
        XCTAssertTrue(store.contains("betaCodeRedeemed"))
        XCTAssertTrue(service.contains("let p_code_hash: String"))
        XCTAssertTrue(service.contains("Params(p_code_hash: hash)"))
        XCTAssertTrue(migration.contains("beta_code_redeemed"))
        XCTAssertTrue(migration.contains("protect_profile_beta_entitlement"))
        XCTAssertTrue(migration.contains("redeem_beta_code"))

        let resourceRoot = nativeRoot.appending(path: "APEX/Resources")
        let localizedFiles = try FileManager.default.contentsOfDirectory(
            at: resourceRoot,
            includingPropertiesForKeys: nil
        ).map { $0.appending(path: "Localizable.strings") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        for file in localizedFiles {
            let text = try String(contentsOf: file)
            XCTAssertFalse(text.contains("7 days free, then"), file.path)
            XCTAssertFalse(text.contains("Fourteen days, everything unlocked"), file.path)
            XCTAssertFalse(text.contains("Start my 14 days"), file.path)
            XCTAssertFalse(text.contains("Start my 7 days"), file.path)
            XCTAssertFalse(text.contains("days left in your trial"), file.path)
            XCTAssertFalse(text.contains("Seven days, everything unlocked"), file.path)
        }
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
        XCTAssertNil(profile.betaCodeRedeemed)
        XCTAssertNil(profile.trialStartedAt)
        // And an unknown flag must not accidentally grant permanent free access.
        XCTAssertEqual(
            Entitlement.access(
                foundingMember: profile.foundingMember ?? false,
                betaCodeRedeemed: profile.betaCodeRedeemed ?? false,
                subscribedTier: nil, subscriptionExpires: nil),
            .locked
        )
    }
}
