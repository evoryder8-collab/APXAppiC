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

    func testTestFlightLockedStateIsRecoveryOnlyAndAlwaysOffersAnExit() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlement = try String(contentsOf: nativeRoot.appending(path: "APEX/Core/Engine/Entitlement.swift"))
        let root = try String(contentsOf: nativeRoot.appending(path: "APEX/App/AppRootView.swift"))
        let recoveryURL = nativeRoot.appending(path: "APEX/Features/Settings/AccessRecoveryView.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))
        let recovery = try String(contentsOf: recoveryURL)

        XCTAssertFalse(entitlement.contains("monthlyRappen"))
        XCTAssertFalse(entitlement.contains("yearlyRappen"))
        XCTAssertFalse(recovery.contains("Entitlement.price"))
        XCTAssertFalse(recovery.contains("CHF"))
        XCTAssertFalse(recovery.localizedCaseInsensitiveContains("purchase()"))
        XCTAssertTrue(recovery.contains("Purchases are not available in this TestFlight build."))
        XCTAssertTrue(recovery.contains("Check access again"))
        XCTAssertTrue(recovery.contains("session.refreshAccountAccess(expectedUserID: operation.ownerID)"))
        XCTAssertTrue(recovery.contains("await session.signOut()"))
        XCTAssertTrue(root.contains("AccessRecoveryView"))
        XCTAssertFalse(root.contains("PaywallView"))
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
        let founder = try XCTUnwrap(APEXDebugFixture.dashboard().profile)

        store.resolveDebugFixture(userID: founder.userID)
        XCTAssertEqual(store.access, .testFlight)

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
    func testHistoricalProfileTrialCannotReplaceTheServerAccessAnswer() throws {
        let store = EntitlementStore()
        var profile = try XCTUnwrap(APEXDebugFixture.dashboard().profile)
        profile.trialStartedAt = Date().ISO8601Format()

        store.prepareForAccount(profile.userID)
        let missing = AccountAccessEnvelope(
            userID: profile.userID,
            state: .missing,
            expiresAt: nil,
            updatedAt: nil,
            serverNow: Date().ISO8601Format(),
            sponsoredSeatActive: false,
            minimumBuild: 0,
            updateRequired: false,
            webBetaCodesEnabled: false
        )
        store.resolve(envelope: missing, expectedUserID: profile.userID)

        XCTAssertEqual(store.access, .locked)
        XCTAssertFalse(store.isUnlocked)
    }

    func testTestFlightAuthorityIsServerScopedAndNativeHasNoCodePath() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlement = try String(contentsOf: nativeRoot.appending(path: "APEX/Core/Engine/Entitlement.swift"))
        let store = try String(contentsOf: nativeRoot.appending(path: "APEX/Core/Engine/EntitlementStore.swift"))
        let session = try String(contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift"))
        let recovery = try String(contentsOf: nativeRoot.appending(path: "APEX/Features/Settings/AccessRecoveryView.swift"))
        let auth = try String(contentsOf: nativeRoot.appending(path: "APEX/Features/Auth/EmailAuthView.swift"))
        let service = try String(contentsOf: nativeRoot.appending(path: "APEX/Core/Networking/SupabaseService.swift"))
        let migration = try String(contentsOf: nativeRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "supabase/migrations/050_testflight_account_entitlements.sql"))

        XCTAssertFalse(entitlement.contains("trialDays"))
        XCTAssertFalse(entitlement.contains("case trial"))
        XCTAssertFalse(store.contains("UserDefaults.standard"))
        XCTAssertFalse(store.contains("developerCodeHash"))
        XCTAssertFalse(store.contains("redeemBeta"))
        XCTAssertFalse(session.contains("profile.trialStartedAt ="))
        XCTAssertFalse(session.contains("redeemBetaAccess"))
        XCTAssertFalse(recovery.contains("days left in your trial"))
        XCTAssertFalse(recovery.contains("Your trial has ended"))
        XCTAssertFalse(recovery.localizedCaseInsensitiveContains("beta code"))
        XCTAssertFalse(auth.contains("Seven days, everything unlocked"))
        XCTAssertTrue(auth.contains("TestFlight access is included for every account through 31 December 2027."))
        XCTAssertTrue(service.contains("get_my_app_access"))
        XCTAssertFalse(service.contains("func redeemBetaCode"))
        XCTAssertTrue(migration.contains("account_entitlements"))
        XCTAssertTrue(migration.contains("2027-12-31T23:59:59Z"))
        XCTAssertTrue(migration.contains("get_my_app_access"))
        XCTAssertTrue(migration.contains("revoke all on table public.account_entitlements"))

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

    func testAccountAccessRefreshIsBoundToTheInitiatingAuthenticatedAccount() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let store = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Core/Engine/EntitlementStore.swift")
        )
        let session = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let recovery = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Settings/AccessRecoveryView.swift")
        )

        XCTAssertTrue(store.contains("envelope.userID == expectedUserID"))
        XCTAssertTrue(store.contains("observation < latestObservation"))
        XCTAssertFalse(store.contains("func redeemBeta("))

        let sessionStart = try XCTUnwrap(session.range(of: "func refreshAccountAccess("))
        let sessionEnd = try XCTUnwrap(
            session.range(of: "func resolveEntitlements", range: sessionStart.upperBound..<session.endIndex)
        )
        let refresh = String(session[sessionStart.lowerBound..<sessionEnd.lowerBound])
        XCTAssertTrue(refresh.contains("let accountToken = accountGeneration.token"))
        XCTAssertTrue(refresh.contains("authenticatedOwnerID == ownerID"))
        XCTAssertTrue(refresh.contains("service.loadAccountAccess"))
        XCTAssertTrue(refresh.contains("envelope: envelope"))
        XCTAssertTrue(refresh.contains("expectedUserID: ownerID"))
        XCTAssertTrue(refresh.contains("offlineStore.saveAccountAccess"))

        let capture = try XCTUnwrap(
            recovery.range(of: "guard let operation = session.accountOperationLease() else")
        )
        let task = try XCTUnwrap(
            recovery.range(of: "Task { await checkAccess(operation: operation) }")
        )
        XCTAssertLessThan(capture.lowerBound, task.lowerBound)
        XCTAssertTrue(recovery.contains("refreshAccountAccess(expectedUserID: operation.ownerID)"))
        XCTAssertFalse(recovery.contains("redeemBetaAccess"))
        XCTAssertTrue(recovery.contains("catch is CancellationError"))
        XCTAssertTrue(recovery.contains("session.accountOperationIsCurrent(operation)"))
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

    func testLockedAccountCanAcceptCoachInvitationAndRefreshAccess() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let recovery = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Settings/AccessRecoveryView.swift")
        )
        let coachPlan = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Features/Coach/CoachPlanView.swift")
        )
        let session = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )

        XCTAssertTrue(recovery.contains("CoachInvitationAcceptanceCard"))
        XCTAssertTrue(recovery.contains("Accept coach invitation"))
        XCTAssertTrue(coachPlan.contains("struct CoachInvitationAcceptanceCard"))

        let acceptStart = try XCTUnwrap(session.range(of: "func acceptCoachInvitation("))
        let acceptEnd = try XCTUnwrap(
            session.range(of: "func loadCoachClientOverview", range: acceptStart.upperBound..<session.endIndex)
        )
        let acceptBody = String(session[acceptStart.lowerBound..<acceptEnd.lowerBound])
        XCTAssertTrue(acceptBody.contains("refreshAccountAccess(expectedUserID: operation.ownerID)"))
        XCTAssertFalse(acceptBody.contains("await resolveEntitlements()"))
    }

    func testDeniedAccessStopsDashboardOutboxRealtimeAndHealthWork() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )

        XCTAssertTrue(source.contains("func accountAccessAllowsPrivateWork(for ownerID: UUID) -> Bool"))
        XCTAssertTrue(source.contains("func routeToAccessRecoveryBoundary(for ownerID: UUID)"))

        let bootstrapStart = try XCTUnwrap(source.range(of: "func bootstrap() async"))
        let bootstrapEnd = try XCTUnwrap(
            source.range(of: "func choose(_ persona:", range: bootstrapStart.upperBound..<source.endIndex)
        )
        let bootstrap = String(source[bootstrapStart.lowerBound..<bootstrapEnd.lowerBound])
        let bootstrapAccess = try XCTUnwrap(bootstrap.range(of: "refreshAccountAccess(expectedUserID: userID)"))
        let bootstrapGuard = try XCTUnwrap(
            bootstrap.range(of: "accountAccessAllowsPrivateWork(for: userID)", range: bootstrapAccess.upperBound..<bootstrap.endIndex)
        )
        let bootstrapFlush = try XCTUnwrap(bootstrap.range(of: "flushPendingChanges(for: userID)"))
        XCTAssertLessThan(bootstrapGuard.lowerBound, bootstrapFlush.lowerBound)

        let dashboardStart = try XCTUnwrap(source.range(of: "func refreshDashboard("))
        let dashboardEnd = try XCTUnwrap(
            source.range(of: "func setAvatar(", range: dashboardStart.upperBound..<source.endIndex)
        )
        let dashboard = String(source[dashboardStart.lowerBound..<dashboardEnd.lowerBound])
        let dashboardAccess = try XCTUnwrap(dashboard.range(of: "await resolveEntitlements()"))
        let dashboardGuard = try XCTUnwrap(
            dashboard.range(of: "accountAccessAllowsPrivateWork(for: ownerID)", range: dashboardAccess.upperBound..<dashboard.endIndex)
        )
        let dashboardLoad = try XCTUnwrap(dashboard.range(of: "service.loadDashboard()"))
        XCTAssertLessThan(dashboardGuard.lowerBound, dashboardLoad.lowerBound)

        let refreshStart = try XCTUnwrap(source.range(of: "private func refresh(includeAccess:"))
        let refreshEnd = try XCTUnwrap(
            source.range(of: "func onAppBecameActive()", range: refreshStart.upperBound..<source.endIndex)
        )
        let refresh = String(source[refreshStart.lowerBound..<refreshEnd.lowerBound])
        let refreshGuard = try XCTUnwrap(refresh.range(of: "accountAccessAllowsPrivateWork(for: ownerID)"))
        let refreshFlush = try XCTUnwrap(refresh.range(of: "flushPendingChanges(for: ownerID)"))
        XCTAssertLessThan(refreshGuard.lowerBound, refreshFlush.lowerBound)

        let foregroundStart = try XCTUnwrap(source.range(of: "func onAppBecameActive()"))
        let foregroundEnd = try XCTUnwrap(
            source.range(of: "func handleAuthCallback(", range: foregroundStart.upperBound..<source.endIndex)
        )
        let foreground = String(source[foregroundStart.lowerBound..<foregroundEnd.lowerBound])
        let foregroundGuard = try XCTUnwrap(foreground.range(of: "accountAccessAllowsPrivateWork(for: ownerID)"))
        let hydration = try XCTUnwrap(foreground.range(of: "retryPendingHydrationMutations"))
        XCTAssertLessThan(foregroundGuard.lowerBound, hydration.lowerBound)

        for (start, end, ownerExpression) in [
            ("func importHealthQuietly(", "func connectHealth(", "operation.ownerID"),
            ("func applyHealthSnapshot(", "func importHealthWorkoutChanges(", "operation.ownerID"),
            ("private func flushPendingChanges(", "private func bindHealthBackgroundMonitoring(", "userID"),
            ("private func bindHealthBackgroundMonitoring(", "private func retryPendingHydrationMutations(", "operation.ownerID"),
            ("private func startRealtimeSync(", "private func scheduleRealtimeRefresh(", "operation.ownerID")
        ] {
            let bodyStart = try XCTUnwrap(source.range(of: start))
            let bodyEnd = try XCTUnwrap(
                source.range(of: end, range: bodyStart.upperBound..<source.endIndex)
            )
            let body = String(source[bodyStart.lowerBound..<bodyEnd.lowerBound])
            XCTAssertTrue(
                body.contains("accountAccessAllowsPrivateWork(for: \(ownerExpression))"),
                "\(start) must independently reject denied or cross-account work"
            )
        }

        let callbackStart = try XCTUnwrap(source.range(of: "func handleAuthCallback("))
        let callbackEnd = try XCTUnwrap(
            source.range(of: "func toggleMeal(", range: callbackStart.upperBound..<source.endIndex)
        )
        let callback = String(source[callbackStart.lowerBound..<callbackEnd.lowerBound])
        let callbackGuard = try XCTUnwrap(
            callback.range(of: "if accountAccessAllowsPrivateWork(for: userID)")
        )
        let callbackCache = try XCTUnwrap(callback.range(of: "loadDashboard(for: userID)"))
        XCTAssertLessThan(callbackGuard.lowerBound, callbackCache.lowerBound)
        XCTAssertTrue(callback.contains("catch is CancellationError"))
    }

}

final class AccountAccessEnvelopeTests: XCTestCase {

    private let ownerID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let otherOwnerID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let now = Date(timeIntervalSince1970: 1_788_220_800) // 2026-09-01T00:00:00Z

    private func envelope(
        ownerID: UUID? = nil,
        state: AccountAccessEnvelope.State = .granted,
        expiresAt: String? = "2027-12-31T23:59:59Z",
        serverNow: String = "2026-09-01T00:00:00Z",
        sponsored: Bool = false,
        updateRequired: Bool = false,
        minimumBuild: Int = 0
    ) -> AccountAccessEnvelope {
        AccountAccessEnvelope(
            userID: ownerID ?? self.ownerID,
            state: state,
            expiresAt: expiresAt,
            updatedAt: "2026-09-01T00:00:00Z",
            serverNow: serverNow,
            sponsoredSeatActive: sponsored,
            minimumBuild: minimumBuild,
            updateRequired: updateRequired,
            webBetaCodesEnabled: false
        )
    }

    @MainActor
    func testProfilelessTestFlightAccountUnlocksFromOwnedServerEnvelope() {
        let store = EntitlementStore()
        store.prepareForAccount(ownerID)

        XCTAssertTrue(store.resolve(envelope: envelope(), expectedUserID: ownerID, now: now))
        XCTAssertEqual(store.resolution, .resolved)
        XCTAssertEqual(store.access, .testFlight)
        XCTAssertTrue(store.hasIndividualAccess)
        XCTAssertTrue(store.isUnlocked)
    }

    @MainActor
    func testLiveServerStateAndServerClockIgnoreDeviceWallClockSkew() throws {
        let futureDeviceClock = Date(timeIntervalSince1970: 4_102_444_800)
        let granted = EntitlementStore()
        granted.prepareForAccount(ownerID)

        XCTAssertTrue(granted.resolve(
            envelope: envelope(
                expiresAt: "2026-09-01T01:00:00Z",
                serverNow: "2026-09-01T00:00:00Z"
            ),
            expectedUserID: ownerID,
            now: futureDeviceClock,
            systemUptime: 100
        ))
        XCTAssertEqual(granted.access, .testFlight)
        XCTAssertTrue(granted.hasIndividualAccess)
        XCTAssertEqual(
            try XCTUnwrap(granted.scheduledAccessDeadlineUptime),
            3_700,
            accuracy: 0.001
        )

        let pastDeviceClock = Date(timeIntervalSince1970: 0)
        let denied = EntitlementStore()
        denied.prepareForAccount(ownerID)
        XCTAssertTrue(denied.resolve(
            envelope: envelope(
                state: .expired,
                expiresAt: "2099-01-01T00:00:00Z"
            ),
            expectedUserID: ownerID,
            now: pastDeviceClock,
            systemUptime: 100
        ))
        XCTAssertEqual(denied.access, .locked)
        XCTAssertFalse(denied.isUnlocked)
    }

    @MainActor
    func testExpiredRevokedMissingAndUpdateRequiredFailClosed() {
        for (state, reason) in [
            (AccountAccessEnvelope.State.expired, EntitlementStore.RecoveryReason.expired),
            (.revoked, .revoked),
            (.locked, .locked),
            (.missing, .locked),
        ] {
            let store = EntitlementStore()
            store.prepareForAccount(ownerID)
            XCTAssertTrue(store.resolve(
                envelope: envelope(state: state),
                expectedUserID: ownerID,
                now: now
            ))
            XCTAssertEqual(store.access, .locked)
            XCTAssertEqual(store.recoveryReason, reason)
            XCTAssertFalse(store.isUnlocked)
        }

        let expired = EntitlementStore()
        expired.prepareForAccount(ownerID)
        XCTAssertTrue(expired.resolve(
            envelope: envelope(expiresAt: "2026-08-31T23:59:59Z"),
            expectedUserID: ownerID,
            now: now
        ))
        XCTAssertEqual(expired.access, .locked)
        XCTAssertEqual(expired.recoveryReason, .expired)

        let update = EntitlementStore()
        update.prepareForAccount(ownerID)
        XCTAssertTrue(update.resolve(
            envelope: envelope(updateRequired: true),
            expectedUserID: ownerID,
            now: now
        ))
        XCTAssertEqual(update.access, .updateRequired)
        XCTAssertEqual(update.recoveryReason, .updateRequired)
        XCTAssertFalse(update.isUnlocked)
    }

    @MainActor
    func testSponsoredSeatUnlocksWithoutIndividualGrant() throws {
        let store = EntitlementStore()
        store.prepareForAccount(ownerID)
        XCTAssertTrue(store.resolve(
            envelope: envelope(state: .locked, sponsored: true),
            expectedUserID: ownerID,
            now: Date(timeIntervalSince1970: 4_102_444_800),
            systemUptime: 500
        ))
        XCTAssertEqual(store.access, .sponsored)
        XCTAssertFalse(store.hasIndividualAccess)
        XCTAssertTrue(store.isUnlocked)
        XCTAssertEqual(
            try XCTUnwrap(store.scheduledAccessDeadlineUptime),
            500 + (24 * 60 * 60),
            accuracy: 0.001
        )
    }

    @MainActor
    func testCachedIndividualGrantUsesServerNowPlusNonnegativeElapsedTime() throws {
        let savedAt = now
        let cached = CachedAccountAccess(
            envelope: envelope(expiresAt: "2026-09-01T01:00:00Z"),
            savedAt: savedAt,
            savedSystemUptime: 1_000
        )

        let active = EntitlementStore()
        active.prepareForAccount(ownerID)
        XCTAssertTrue(active.resolve(
            cached: cached,
            expectedUserID: ownerID,
            currentBuild: 100,
            now: savedAt.addingTimeInterval(3_599),
            systemUptime: 4_599
        ))
        XCTAssertEqual(active.access, .testFlight)
        XCTAssertEqual(
            try XCTUnwrap(active.scheduledAccessDeadlineUptime),
            4_600,
            accuracy: 0.001
        )

        let expired = EntitlementStore()
        expired.prepareForAccount(ownerID)
        XCTAssertTrue(expired.resolve(
            cached: cached,
            expectedUserID: ownerID,
            currentBuild: 100,
            now: savedAt.addingTimeInterval(3_600),
            systemUptime: 4_600
        ))
        XCTAssertEqual(expired.access, .locked)
        XCTAssertFalse(expired.isUnlocked)
    }

    @MainActor
    func testCachedMinimumBuildReevaluatesAfterUpgradeOrDowngrade() {
        let previouslyOutdated = CachedAccountAccess(
            envelope: envelope(updateRequired: true, minimumBuild: 100),
            savedAt: now,
            savedSystemUptime: 1
        )
        let upgraded = EntitlementStore()
        upgraded.prepareForAccount(ownerID)
        XCTAssertTrue(upgraded.resolve(
            cached: previouslyOutdated,
            expectedUserID: ownerID,
            currentBuild: 100,
            now: now,
            systemUptime: 1
        ))
        XCTAssertEqual(upgraded.access, .testFlight)
        XCTAssertTrue(upgraded.isUnlocked)

        let previouslyCompliant = CachedAccountAccess(
            envelope: envelope(updateRequired: false, minimumBuild: 100),
            savedAt: now,
            savedSystemUptime: 1
        )
        let downgraded = EntitlementStore()
        downgraded.prepareForAccount(ownerID)
        XCTAssertTrue(downgraded.resolve(
            cached: previouslyCompliant,
            expectedUserID: ownerID,
            currentBuild: 99,
            now: now,
            systemUptime: 1
        ))
        XCTAssertEqual(downgraded.access, .updateRequired)
        XCTAssertFalse(downgraded.isUnlocked)
    }

    @MainActor
    func testCachedWallClockRollbackFailsClosedRatherThanExtendingAccess() {
        let cached = CachedAccountAccess(
            envelope: envelope(expiresAt: "2026-09-01T01:00:00Z"),
            savedAt: now,
            savedSystemUptime: 1_000
        )
        let store = EntitlementStore()
        store.prepareForAccount(ownerID)

        XCTAssertFalse(store.resolve(
            cached: cached,
            expectedUserID: ownerID,
            currentBuild: 100,
            now: now.addingTimeInterval(-1),
            systemUptime: 1_001
        ))
        XCTAssertEqual(store.resolution, .resolving)
        XCTAssertEqual(store.access, .locked)
        XCTAssertFalse(store.isUnlocked)
    }

    @MainActor
    func testPartialWallClockRollbackDuringSameBootAlsoFailsClosed() {
        let cached = CachedAccountAccess(
            envelope: envelope(expiresAt: "2026-09-02T00:00:00Z"),
            savedAt: now,
            savedSystemUptime: 1_000
        )
        let store = EntitlementStore()
        store.prepareForAccount(ownerID)

        XCTAssertFalse(store.resolve(
            cached: cached,
            expectedUserID: ownerID,
            currentBuild: 100,
            // Ten monotonic hours elapsed, but the wall clock reports only
            // five. Accepting five would extend the offline grant by five.
            now: now.addingTimeInterval(5 * 60 * 60),
            systemUptime: 1_000 + (10 * 60 * 60)
        ))
        XCTAssertEqual(store.access, .locked)
        XCTAssertFalse(store.isUnlocked)
    }

    @MainActor
    func testDeviceRebootCannotExtendFiniteOrSponsoredOfflineAccess() {
        let finite = CachedAccountAccess(
            envelope: envelope(expiresAt: "2026-09-02T00:00:00Z"),
            savedAt: now,
            savedSystemUptime: 86_400,
            savedBootSessionID: "previous-boot"
        )
        let finiteStore = EntitlementStore()
        finiteStore.prepareForAccount(ownerID)
        XCTAssertFalse(finiteStore.resolve(
            cached: finite,
            expectedUserID: ownerID,
            currentBuild: 100,
            now: now.addingTimeInterval(60),
            systemUptime: 10,
            bootSessionID: "current-boot"
        ))
        XCTAssertFalse(finiteStore.isUnlocked)

        let sponsored = CachedAccountAccess(
            envelope: envelope(state: .locked, expiresAt: nil, sponsored: true),
            savedAt: now,
            savedSystemUptime: 86_400,
            savedBootSessionID: "previous-boot"
        )
        let sponsoredStore = EntitlementStore()
        sponsoredStore.prepareForAccount(ownerID)
        XCTAssertFalse(sponsoredStore.resolve(
            cached: sponsored,
            expectedUserID: ownerID,
            currentBuild: 100,
            now: now.addingTimeInterval(60),
            systemUptime: 10,
            bootSessionID: "current-boot"
        ))
        XCTAssertFalse(sponsoredStore.isUnlocked)

        let permanent = CachedAccountAccess(
            envelope: envelope(expiresAt: nil),
            savedAt: now,
            savedSystemUptime: 86_400,
            savedBootSessionID: "previous-boot"
        )
        let permanentStore = EntitlementStore()
        permanentStore.prepareForAccount(ownerID)
        XCTAssertTrue(permanentStore.resolve(
            cached: permanent,
            expectedUserID: ownerID,
            currentBuild: 100,
            now: now.addingTimeInterval(60),
            systemUptime: 10,
            bootSessionID: "current-boot"
        ))
        XCTAssertTrue(permanentStore.isUnlocked)
    }

    func testSystemUptimeUseDeclaresApplesElapsedTimePrivacyReason() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try String(
            contentsOf: nativeRoot.appending(path: "APEX/PrivacyInfo.xcprivacy")
        )

        XCTAssertTrue(manifest.contains("NSPrivacyAccessedAPICategorySystemBootTime"))
        XCTAssertTrue(manifest.contains("35F9.1"))
    }

    func testInvalidAccessEvidenceCannotRemainResolvingAndDenialStopsPrivateSensors() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let session = try String(
            contentsOf: nativeRoot.appending(path: "APEX/App/AppSession.swift")
        )
        let store = try String(
            contentsOf: nativeRoot.appending(path: "APEX/Core/Engine/EntitlementStore.swift")
        )

        XCTAssertTrue(session.contains("AccountAccessValidationError.invalidEnvelope"))
        XCTAssertTrue(session.contains("markUnavailable(expectedUserID: ownerID)"))
        XCTAssertTrue(store.contains("setAccessDeniedHandler"))

        let boundaryStart = try XCTUnwrap(
            session.range(of: "func routeToAccessRecoveryBoundary(for ownerID: UUID)")
        )
        let boundaryEnd = try XCTUnwrap(
            session.range(of: "var interfaceMode:", range: boundaryStart.upperBound..<session.endIndex)
        )
        let boundary = String(session[boundaryStart.lowerBound..<boundaryEnd.lowerBound])
        XCTAssertTrue(boundary.contains("OrbitLocationManager.shared.releaseForAccountBoundary()"))
        XCTAssertTrue(boundary.contains("HealthKitManager.shared.suspendPrivateWorkForAccessDenial()"))
        XCTAssertTrue(boundary.contains("service.stopRealtime()"))
        XCTAssertTrue(boundary.contains("isBusy = false"))
        XCTAssertTrue(boundary.contains("isRefreshing = false"))
    }

    @MainActor
    func testCachedSponsoredOnlyAccessExpiresAfterTwentyFourHours() {
        let cached = CachedAccountAccess(
            envelope: envelope(state: .locked, expiresAt: nil, sponsored: true),
            savedAt: now,
            savedSystemUptime: 10
        )
        let active = EntitlementStore()
        active.prepareForAccount(ownerID)
        XCTAssertTrue(active.resolve(
            cached: cached,
            expectedUserID: ownerID,
            currentBuild: 100,
            now: now.addingTimeInterval((24 * 60 * 60) - 1),
            systemUptime: 10 + (24 * 60 * 60) - 1
        ))
        XCTAssertEqual(active.access, .sponsored)

        let stale = EntitlementStore()
        stale.prepareForAccount(ownerID)
        XCTAssertTrue(stale.resolve(
            cached: cached,
            expectedUserID: ownerID,
            currentBuild: 100,
            now: now.addingTimeInterval(24 * 60 * 60),
            systemUptime: 10 + (24 * 60 * 60)
        ))
        XCTAssertEqual(stale.access, .locked)
        XCTAssertFalse(stale.isUnlocked)
    }

    @MainActor
    func testRebootWhoseUptimeOvertakesSavedUptimeCannotUndercountCacheAge() {
        let cached = CachedAccountAccess(
            envelope: envelope(state: .locked, expiresAt: nil, sponsored: true),
            savedAt: now,
            savedSystemUptime: 600,
            savedBootSessionID: "previous-boot"
        )
        let store = EntitlementStore()
        store.prepareForAccount(ownerID)

        XCTAssertFalse(store.resolve(
            cached: cached,
            expectedUserID: ownerID,
            currentBuild: 100,
            now: now.addingTimeInterval(48 * 60 * 60),
            // This new boot has now run longer than the old boot had when the
            // cache was saved. Comparing uptime values alone is insufficient.
            systemUptime: 3_600,
            bootSessionID: "current-boot"
        ))
        XCTAssertEqual(store.access, .locked)
        XCTAssertFalse(store.isUnlocked)
    }

    @MainActor
    func testNewBootCannotMasqueradeAsOldBootAfterItsUptimeOvertakesSavedUptime() {
        let cached = CachedAccountAccess(
            envelope: envelope(expiresAt: "2026-09-02T00:00:00Z"),
            savedAt: now,
            savedSystemUptime: 600,
            savedBootSessionID: "previous-boot"
        )
        let store = EntitlementStore()
        store.prepareForAccount(ownerID)

        XCTAssertFalse(store.resolve(
            cached: cached,
            expectedUserID: ownerID,
            currentBuild: 100,
            // A rolled-back wall clock can make the calculated boot epoch look
            // continuous after the new uptime overtakes the old value.
            now: now.addingTimeInterval(60),
            systemUptime: 601,
            bootSessionID: "current-boot"
        ))
        XCTAssertFalse(store.isUnlocked)
    }

    @MainActor
    func testOneShotDeadlineInvalidatesWithoutPollingAndNoOpRecheckDoesNotRepublish() throws {
        let store = EntitlementStore()
        store.prepareForAccount(ownerID)
        XCTAssertTrue(store.resolve(
            envelope: envelope(expiresAt: "2026-09-01T00:01:00Z"),
            expectedUserID: ownerID,
            now: now,
            systemUptime: 100
        ))
        XCTAssertEqual(
            try XCTUnwrap(store.scheduledAccessDeadlineUptime),
            160,
            accuracy: 0.001
        )

        XCTAssertFalse(store.reevaluateAccess(systemUptime: 159))
        XCTAssertEqual(store.access, .testFlight)
        XCTAssertEqual(
            try XCTUnwrap(store.scheduledAccessDeadlineUptime),
            160,
            accuracy: 0.001
        )

        XCTAssertTrue(store.reevaluateAccess(systemUptime: 160))
        XCTAssertEqual(store.access, .locked)
        XCTAssertNil(store.scheduledAccessDeadlineUptime)
    }

    @MainActor
    func testWrongOwnerAndDelayedOlderEnvelopeCannotReplaceCurrentAccess() {
        let store = EntitlementStore()
        store.prepareForAccount(ownerID)
        XCTAssertFalse(store.resolve(
            envelope: envelope(ownerID: otherOwnerID),
            expectedUserID: ownerID,
            now: now
        ))
        XCTAssertEqual(store.resolution, .resolving)

        XCTAssertTrue(store.resolve(
            envelope: envelope(serverNow: "2026-09-01T12:00:00Z"),
            expectedUserID: ownerID,
            now: now
        ))
        XCTAssertFalse(store.resolve(
            envelope: envelope(
                state: .revoked,
                serverNow: "2026-09-01T11:59:59Z"
            ),
            expectedUserID: ownerID,
            now: now
        ))
        XCTAssertEqual(store.access, .testFlight)
    }

    @MainActor
    func testUnavailableResolutionNeverErasesAValidOwnedCache() {
        let cached = EntitlementStore()
        cached.prepareForAccount(ownerID)
        XCTAssertTrue(cached.resolve(envelope: envelope(), expectedUserID: ownerID, now: now))
        cached.markUnavailable(expectedUserID: ownerID)
        XCTAssertEqual(cached.resolution, .resolved)
        XCTAssertTrue(cached.isUnlocked)

        let empty = EntitlementStore()
        empty.prepareForAccount(ownerID)
        empty.markUnavailable(expectedUserID: ownerID)
        XCTAssertEqual(empty.resolution, .failed)
        XCTAssertFalse(empty.isUnlocked)
    }

    func testAccessCacheIsOwnerScopedAndRejectsMismatchedEnvelope() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("APEXAccessCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let cache = OfflineStore(rootURL: rootURL)
        let owned = envelope()

        try await cache.saveAccountAccess(
            owned,
            for: ownerID,
            savedAt: now,
            systemUptime: 123
        )
        let loadedOwner = try await cache.loadAccountAccess(for: ownerID)
        let loadedOther = try await cache.loadAccountAccess(for: otherOwnerID)
        XCTAssertEqual(
            loadedOwner,
            CachedAccountAccess(
                envelope: owned,
                savedAt: now,
                savedSystemUptime: 123
            )
        )
        XCTAssertNil(loadedOther)
        do {
            try await cache.saveAccountAccess(owned, for: otherOwnerID)
            XCTFail("an envelope must never be written into another owner's cache")
        } catch {
            // Expected: the embedded owner is part of the cache boundary.
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
