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

    func testCoachToolsNeedServerCoachCapabilityAndMealListsRemainIndividual() {
        let premium = Entitlement.Access.subscribed(.premium)
        XCTAssertFalse(Entitlement.allows(.clientRoster, access: premium))
        XCTAssertFalse(Entitlement.allows(.clientRoster, access: .founding))
        // Predefined meal lists are useful to anyone who eats the same things
        // most weeks, so they are not a coach feature at all.
        XCTAssertFalse(
            Entitlement.CoachFeature.allCases.contains { $0.rawValue.contains("meal") },
            "meal lists must stay available to individual accounts"
        )
        // Beta and founding access never invent a server coach role.
        XCTAssertFalse(Entitlement.allows(.planAuthoring, access: .beta))
        XCTAssertFalse(Entitlement.allows(.planAuthoring, access: .locked))
    }

    func testActiveSponsoredSeatUnlocksClientAppWithoutIndividualOrCoachAccess() {
        let access = Entitlement.access(
            foundingMember: false,
            betaCodeRedeemed: false,
            subscribedTier: nil,
            subscriptionExpires: nil,
            sponsoredSeatActive: true
        )
        XCTAssertEqual(access, .sponsored)
        XCTAssertTrue(Entitlement.isUnlocked(access))
        XCTAssertFalse(Entitlement.allows(.clientRoster, access: access))
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
        let bindOwner = try XCTUnwrap(
            callback.range(of: "authenticatedOwnerID = userID")
        )
        let clear = try XCTUnwrap(callback.range(of: "data = .empty"))
        let refresh = try XCTUnwrap(
            callback.range(of: "try await refreshDashboard(expectedUserID: userID)")
        )

        XCTAssertLessThan(reset.lowerBound, authenticate.lowerBound)
        XCTAssertLessThan(authenticate.lowerBound, bindOwner.lowerBound)
        XCTAssertLessThan(bindOwner.lowerBound, scope.lowerBound)
        XCTAssertLessThan(scope.lowerBound, clear.lowerBound)
        XCTAssertLessThan(clear.lowerBound, refresh.lowerBound)
        XCTAssertTrue(callback.contains("var switchedAccounts = false"))
        XCTAssertTrue(callback.contains("switchedAccounts = true"))
        XCTAssertTrue(callback.contains("if !switchedAccounts {"))
        XCTAssertTrue(callback.contains("await resolveEntitlements()"))
        XCTAssertTrue(callback.contains("if route == .portal, let operation = accountOperationLease()"))
        XCTAssertTrue(callback.contains("await startRealtimeSync(operation: operation)"))
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

    @MainActor
    func testAccountBoundaryImmediatelyClearsPublishedPrivateAccountState() {
        let session = AppSession()
        session.data = APEXDebugFixture.dashboard()
        session.brainSynergies = [
            FBSynergyEvent(
                date: "2026-09-02",
                kind: .proteinStrength,
                label: "private account A signal"
            )
        ]
        session.navigationPath = [.settings]
        session.greetingPersona = .constantine
        session.awaitingConfirmationFor = "private@example.com"
        session.alertMessage = "private account A message"

        session.beginAccountBoundary()

        XCTAssertNil(session.data.profile)
        XCTAssertNil(session.data.settings)
        XCTAssertTrue(session.data.snapshots.isEmpty)
        XCTAssertTrue(session.brainSynergies.isEmpty)
        XCTAssertTrue(session.navigationPath.isEmpty)
        XCTAssertNil(session.greetingPersona)
        XCTAssertNil(session.awaitingConfirmationFor)
        XCTAssertNil(session.alertMessage)
    }

    @MainActor
    func testProfilelessDashboardCannotRetainPriorAccountsBrainSynergies() {
        let session = AppSession()
        session.brainSynergies = [
            FBSynergyEvent(
                date: "2026-09-02",
                kind: .hydrationEndurance,
                label: "private account A signal"
            )
        ]

        session.data = .empty

        XCTAssertTrue(session.brainSynergies.isEmpty)
    }

    @MainActor
    func testOwnedOperationLeaseExpiresAtTheAccountBoundary() throws {
        let ownerID = UUID()
        let session = AppSession()
        session.data = APEXDebugFixture.dashboard(userID: ownerID)
        let operation = try XCTUnwrap(session.accountOperationLease())

        XCTAssertTrue(session.accountOperationIsCurrent(operation))
        session.beginAccountBoundary()
        XCTAssertFalse(
            session.accountOperationIsCurrent(operation),
            "work queued by account A must already be invalid before it can enter an async mutation under B"
        )
    }

    @MainActor
    func testAccountBoundarySynchronouslyResetsEntitlementOwnership() {
        let ownerID = UUID()
        EntitlementStore.shared.prepareForAccount(ownerID)
        XCTAssertEqual(EntitlementStore.shared.resolvedUserID, ownerID)

        AppSession().beginAccountBoundary()

        XCTAssertNil(EntitlementStore.shared.resolvedUserID)
        XCTAssertEqual(EntitlementStore.shared.access, .locked)
    }

    func testGuardedPersistenceCannotPublishNestedFailureAcrossAnAccountBoundary() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift"))
        let start = try XCTUnwrap(source.range(of: "private func persistUpsert"))
        let end = try XCTUnwrap(source.range(of: "private func persistDelete", range: start.upperBound..<source.endIndex))
        let persistence = String(source[start.lowerBound..<end.lowerBound])
        let nestedCatch = try XCTUnwrap(persistence.range(of: "            } catch {", options: .backwards))
        let failureTail = String(persistence[nestedCatch.lowerBound...])

        XCTAssertTrue(
            failureTail.contains("guard accountGeneration.accepts(expectedAccountToken)")
                && failureTail.contains("verifiedPersistenceOwnerID(ownerID) == persistenceOwnerID"),
            "an offline-store failure must not alert whichever account became active while it was suspended"
        )
    }

    func testBetaRedemptionIsBoundToTheInitiatingAuthenticatedAccount() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let store = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Core/Engine/EntitlementStore.swift")
        )
        let session = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let paywall = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Settings/PaywallView.swift")
        )

        let storeStart = try XCTUnwrap(store.range(of: "func redeemBeta("))
        let storeEnd = try XCTUnwrap(
            store.range(of: "private func hash", range: storeStart.upperBound..<store.endIndex)
        )
        let redemption = String(store[storeStart.lowerBound..<storeEnd.lowerBound])
        XCTAssertTrue(
            redemption.contains(") async throws -> RedeemOutcome"),
            "beta redemption must be able to propagate account-bound cancellation"
        )
        let expectedOwner = try XCTUnwrap(redemption.range(of: "expectedUserID: UUID"))
        let localOwner = try XCTUnwrap(redemption.range(of: "resolvedUserID == expectedUserID"))
        let authOwner = try XCTUnwrap(redemption.range(of: "service.currentUserID()"))
        let rpc = try XCTUnwrap(redemption.range(of: "service.redeemBetaCode"))
        let postflight = try XCTUnwrap(
            redemption.range(of: "service.currentUserID()", range: rpc.upperBound..<redemption.endIndex)
        )
        XCTAssertLessThan(expectedOwner.lowerBound, localOwner.lowerBound)
        XCTAssertLessThan(localOwner.lowerBound, authOwner.lowerBound)
        XCTAssertLessThan(authOwner.lowerBound, rpc.lowerBound)
        XCTAssertLessThan(rpc.lowerBound, postflight.lowerBound)
        let cancellation = try XCTUnwrap(redemption.range(of: "catch is CancellationError"))
        let genericFailure = try XCTUnwrap(
            redemption.range(of: "catch {", range: cancellation.upperBound..<redemption.endIndex)
        )
        XCTAssertLessThan(cancellation.lowerBound, genericFailure.lowerBound)
        XCTAssertTrue(
            redemption[cancellation.lowerBound..<genericFailure.lowerBound].contains("throw CancellationError()"),
            "task cancellation must not be translated into an unavailable beta-code outcome"
        )

        let sessionStart = try XCTUnwrap(session.range(of: "func redeemBetaAccess("))
        let sessionEnd = try XCTUnwrap(
            session.range(of: "func loadCoachRoster", range: sessionStart.upperBound..<session.endIndex)
        )
        let guardedRedemption = String(session[sessionStart.lowerBound..<sessionEnd.lowerBound])
        XCTAssertTrue(guardedRedemption.contains("operation: AccountOperationLease"))
        XCTAssertGreaterThanOrEqual(
            guardedRedemption.components(separatedBy: "try requireCurrentAccountOperation(operation)").count - 1,
            2
        )
        XCTAssertTrue(guardedRedemption.contains("expectedUserID: operation.ownerID"))

        let capture = try XCTUnwrap(
            paywall.range(of: "guard let operation = session.accountOperationLease() else")
        )
        let task = try XCTUnwrap(
            paywall.range(of: "Task { await submitCode(operation: operation) }")
        )
        XCTAssertLessThan(capture.lowerBound, task.lowerBound)
        XCTAssertTrue(paywall.contains("session.redeemBetaAccess(code: code, operation: operation)"))
        XCTAssertTrue(paywall.contains("refreshDashboard(expectedUserID: operation.ownerID)"))
        XCTAssertTrue(paywall.contains("catch is CancellationError"))
        XCTAssertTrue(paywall.contains("session.accountOperationIsCurrent(operation)"))
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
            try body("private func submitInduction", before: "/// Deterministic authenticated first-run"),
            try body("func installInductionPlan", before: "private func applyInductionPlan"),
            try body("func restoreOriginalProgramme", before: "/// Store a rewritten predefined list"),
        ]
        for mutation in mutations {
            XCTAssertTrue(mutation.contains("operation: AccountOperationLease"))
            XCTAssertGreaterThanOrEqual(
                mutation.components(separatedBy: "requireCurrentAccountOperation(operation)").count - 1
                    + mutation.components(separatedBy: "accountOperationIsCurrent(operation)").count - 1,
                2
            )
            XCTAssertFalse(mutation.contains("let accountToken = accountGeneration.token"))
        }
    }

    func testDelayedFitnessPlanIntroductionCannotPersistIntoAnotherAccount() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Portal/PortalHomeView.swift")
        )
        let start = try XCTUnwrap(source.range(of: "private func beginIntroductionReveal()"))
        let end = try XCTUnwrap(
            source.range(of: "private func cancelReveal()", range: start.upperBound..<source.endIndex)
        )
        let reveal = String(source[start.lowerBound..<end.lowerBound])

        let lease = try XCTUnwrap(reveal.range(of: "session.accountOperationLease()"))
        let task = try XCTUnwrap(reveal.range(of: "revealTask = Task"))
        XCTAssertLessThan(lease.lowerBound, task.lowerBound)
        XCTAssertGreaterThanOrEqual(
            reveal.components(separatedBy: "session.accountOperationIsCurrent(operation)").count - 1,
            2
        )
        XCTAssertTrue(reveal.contains("operation: operation"))
    }

    func testWeeklyCalibrationCannotPublishAfterItsAccountExpires() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let start = try XCTUnwrap(source.range(of: "private func considerWeeklyCalibration("))
        let end = try XCTUnwrap(
            source.range(of: "func refreshFailedSyncOperations", range: start.upperBound..<source.endIndex)
        )
        let calibration = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(calibration.contains("operation: AccountOperationLease"))
        XCTAssertTrue(calibration.contains("profile.userID == operation.ownerID"))
        XCTAssertTrue(
            calibration.contains("$0.userID == operation.ownerID"),
            "weekly calibration must never sample another account's cached daily rows"
        )
        XCTAssertGreaterThanOrEqual(
            calibration.components(separatedBy: "requireCurrentAccountOperation(operation)").count - 1,
            3
        )
        XCTAssertTrue(calibration.contains("ownerID: operation.ownerID"))
        XCTAssertTrue(calibration.contains("expectedAccountToken: operation.generation"))
    }

    func testPersistenceHelpersSnapshotTheVerifiedOwnerBeforeSuspending() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        func body(_ start: String, before end: String) throws -> String {
            let lower = try XCTUnwrap(source.range(of: start))
            let upper = try XCTUnwrap(
                source.range(of: end, range: lower.upperBound..<source.endIndex)
            )
            return String(source[lower.lowerBound..<upper.lowerBound])
        }

        let upsert = try body("private func persistUpsert", before: "private func persistDelete")
        let delete = try body("private func persistDelete", before: "private func saveLocalSnapshot(operation:")
        for helper in [upsert, delete] {
            XCTAssertTrue(helper.contains("if let persistenceOwnerID"))
            XCTAssertTrue(helper.contains("let snapshot = data"))
            XCTAssertTrue(helper.contains("offlineStore.saveDashboard(snapshot, for: persistenceOwnerID)"))
            XCTAssertFalse(helper.contains("await saveLocalSnapshot()"))
        }
    }

    func testRealtimeCallbacksRetainTheAccountThatOpenedTheirChannel() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let start = try XCTUnwrap(source.range(of: "private func startRealtimeSync("))
        let end = try XCTUnwrap(
            source.range(of: "func refreshExternalWorkouts", range: start.upperBound..<source.endIndex)
        )
        let realtime = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(realtime.contains("scheduleRealtimeRefresh(operation: operation)"))
        XCTAssertTrue(realtime.contains("accountOperationIsCurrent(operation)"))
        XCTAssertTrue(realtime.contains("refreshDashboard(expectedUserID: operation.ownerID)"))
        XCTAssertFalse(realtime.contains("await self?.refresh()"))
    }

    func testPersonaMismatchRevokesTheAuthenticatedOwnerBeforePublishingItsError() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let start = try XCTUnwrap(source.range(of: "func signIn(email:"))
        let end = try XCTUnwrap(
            source.range(of: "func signUp(email:", range: start.upperBound..<source.endIndex)
        )
        let signIn = String(source[start.lowerBound..<end.lowerBound])
        let mismatch = try XCTUnwrap(signIn.range(of: "APEXServiceError.personaMismatch"))
        let prefix = String(signIn[..<mismatch.lowerBound])
        XCTAssertTrue(prefix.contains("accountToken = beginAccountBoundary()"))
    }

    func testAuthCallbackCannotExposeWritableInductionBeforeDashboardOwnershipIsProven() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let start = try XCTUnwrap(source.range(of: "func handleAuthCallback("))
        let end = try XCTUnwrap(
            source.range(of: "func toggleMeal(", range: start.upperBound..<source.endIndex)
        )
        let callback = String(source[start.lowerBound..<end.lowerBound])
        let stopRealtime = try XCTUnwrap(callback.range(of: "await service.stopRealtime()"))
        let loading = try XCTUnwrap(callback.range(of: "route = .launching"))
        let refresh = try XCTUnwrap(
            callback.range(of: "try await refreshDashboard(expectedUserID: userID)")
        )
        XCTAssertLessThan(loading.lowerBound, stopRealtime.lowerBound)
        XCTAssertLessThan(loading.lowerBound, refresh.lowerBound)
        XCTAssertTrue(callback.contains("offlineStore.loadDashboard(for: userID)"))
        XCTAssertTrue(callback.contains("TrainingInduction.belongsToAccount(cached, userID: userID)"))
        XCTAssertTrue(callback.contains("try? await service.signOut()"))
        XCTAssertTrue(callback.contains("accountToken = beginAccountBoundary()"))
        XCTAssertTrue(callback.contains("route = .welcome"))
    }

    func testAuthCallbackRefreshFailureRevalidatesAndReactivatesAnOwnedCache() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let start = try XCTUnwrap(source.range(of: "func handleAuthCallback("))
        let end = try XCTUnwrap(
            source.range(of: "func toggleMeal(", range: start.upperBound..<source.endIndex)
        )
        let callback = String(source[start.lowerBound..<end.lowerBound])

        let recovery = try XCTUnwrap(callback.range(of: "else if switchedAccounts,"))
        let recoveryBody = String(callback[recovery.lowerBound...])
        let revalidate = try XCTUnwrap(recoveryBody.range(of: "await service.currentUserID()"))
        let coach = try XCTUnwrap(recoveryBody.range(of: "await refreshCoachContext(expectedUserID: ownerID)"))
        let entitlements = try XCTUnwrap(recoveryBody.range(of: "await resolveEntitlements()"))
        let realtime = try XCTUnwrap(recoveryBody.range(of: "await startRealtimeSync(operation: operation)"))

        XCTAssertLessThan(revalidate.lowerBound, coach.lowerBound)
        XCTAssertLessThan(coach.lowerBound, entitlements.lowerBound)
        XCTAssertLessThan(entitlements.lowerBound, realtime.lowerBound)
        XCTAssertTrue(recoveryBody.contains("currentUserID == ownerID"))
        XCTAssertTrue(recoveryBody.contains("TrainingInduction.belongsToAccount(data, userID: ownerID)"))
        XCTAssertTrue(recoveryBody.contains("accountOperationLease()"))
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
