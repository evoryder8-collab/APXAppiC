import XCTest
import Testing
@testable import APEX

@MainActor
struct SponsoredSimpleWorkoutTests {
    @Test(arguments: [false, true], [false, true])
    func retainedPersonalInductionCannotOverrideSponsoredSelection(transition: Bool, main: Bool) {
        let policy = CoachClientPolicy.resolve(relationshipStatus: .active, seatState: .active,
                                               consentedScopes: [.workouts], individualAccess: false)
        let capabilities = CoachAccountCapabilities(coachWorkspace: false, sponsoredClient: true)
        let slug = SimpleHomeLogic.guidedProgramSlug(
            persona: .constantine, mainIsUsable: true, transitionIsUsable: true,
            coachManaged: true, coachIsUsable: false,
            transitionInductionIsUsable: transition, mainInductionIsUsable: main
        )
        #expect(slug == "coach")
        for personalSlug in ["main", "transition", "custom"] {
            #expect(SimpleHomeLogic.canPresentGuidedWorkout(slug: personalSlug, policy: policy,
                                                          capabilities: capabilities) == false)
        }
        #expect(SimpleHomeLogic.canPresentGuidedWorkout(slug: "coach", policy: policy,
                                                      capabilities: capabilities))
    }

    @Test
    func personalSubscriberKeepsInductionAndCoachGraceCannotLaunchPlayer() {
        let personal = CoachClientPolicy.resolve(relationshipStatus: .active, seatState: .active,
                                                 consentedScopes: [.workouts], individualAccess: true)
        let grace = CoachClientPolicy.resolve(relationshipStatus: .grace, seatState: .grace,
                                              consentedScopes: [.workouts], individualAccess: false)
        let capabilities = CoachAccountCapabilities(coachWorkspace: false, sponsoredClient: true)
        let slug = SimpleHomeLogic.guidedProgramSlug(
            persona: .constantine, mainIsUsable: true, transitionIsUsable: true,
            coachManaged: false, transitionInductionIsUsable: true, mainInductionIsUsable: true
        )
        #expect(slug == "transition")
        #expect(SimpleHomeLogic.canPresentGuidedWorkout(slug: slug, policy: personal, capabilities: capabilities))
        #expect(SimpleHomeLogic.canPresentGuidedWorkout(slug: "coach", policy: grace, capabilities: capabilities) == false)
    }

    @Test
    func simpleViewUsesCompleteSelectionAndChecksDirectPresentation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("APEX/Features/Portal/SimpleHomeView.swift"))
        #expect(source.contains("session.trainingSchedule(on: today)"))
        let cover = try #require(source.range(of: ".fullScreenCover(isPresented: $showWorkout)"))
        let player = try #require(source.range(of: "WorkoutPlayerView(", range: cover.upperBound..<source.endIndex))
        #expect(source[cover.upperBound..<player.lowerBound].contains("SimpleHomeLogic.canPresentGuidedWorkout("))
    }
}

final class SimpleHomeLogicTests: XCTestCase {
    func testJuneSundayResolvesTheMainRestDayWithOptionalWalkAcrossPhasePreviews() throws {
        let data = APEXDebugFixture.juneSunday(), date = "2026-11-08"
        let schedule = SimpleHomeLogic.trainingSchedule(in: data, on: date, coachManaged: false, followsCoach: false, includeCustom: true)
        XCTAssertEqual(schedule.primary, "main")
        for lite in [false, true] {
            let active = try XCTUnwrap(schedule.plans(in: data, on: date, lite: lite).first)
            XCTAssertEqual(active.programDay?.name, "Rest · Full recovery")
            XCTAssertTrue(active.exercises.isEmpty)
            XCTAssertTrue(active.hasWalkOnly)
        }
        let preview = try XCTUnwrap(TrainingPlanEngine.programDays(data, slug: "transition", date: date, lite: false).first)
        XCTAssertEqual(preview.programDay?.name, "Pull B · Heavy Pull 2")
        XCTAssertFalse(preview.exercises.isEmpty)
        let monday = try XCTUnwrap(schedule.plans(in: data, on: "2026-11-09", lite: false).first)
        XCTAssertFalse(monday.exercises.isEmpty)
        XCTAssertFalse(monday.hasWalkOnly)
    }

    @MainActor
    func testScheduleCombinesCustomPrescriptionsWithoutIncludingOneOffReceipts() throws {
        let owner = UUID(), date = Date().apexDateKey
        var data = APEXDebugFixture.dashboard(userID: owner)
        let custom = try XCTUnwrap(data.programs.first { $0.userID == owner && $0.slug == "custom" })
        func day(_ name: String) -> ProgramDay {
            ProgramDay(id: UUID(), userID: owner, programID: custom.id,
                       weekday: APEXDateMath.isoWeekday(date), name: name, dayType: "custom",
                       estimatedMinutes: 45, warmupNote: "", sortOrder: 1)
        }
        let scheduled = day("My circuit"), legacy = day("Manual workout")
        data.programDays += [scheduled, legacy]
        data.exercises.append(Exercise(id: UUID(), userID: owner, programDayID: scheduled.id,
            name: "Squat", sets: 3, repMin: 8, repMax: 12, repUnit: "reps", perSide: false,
            restSeconds: 60, tempoUp: 1, tempoDown: 2, tempoPause: 0, tempoNote: "", notes: "",
            incrementKG: 0, isLite: false, optional: false, sortOrder: 1))
        let manual = WorkoutSession(id: UUID(), userID: owner, date: date, programDayID: legacy.id,
            isLite: false, isDeload: false, isEventRecovery: false, completed: true, qualityScore: 1,
            startedAt: nil, completedAt: nil, notes: ManualWorkout.notes(title: "Unscheduled"))
        data.workoutSessions.append(manual)
        let primary = try XCTUnwrap(data.programDays.first { $0.name == "Upper strength" })
        func ids(primary: String?, includeCustom: Bool) -> [UUID] {
            SimpleHomeLogic.workoutPlans(in: data, primarySlug: primary, includeCustom: includeCustom,
                date: date, lite: false).compactMap { $0.programDay?.id }
        }
        XCTAssertEqual(ids(primary: "main", includeCustom: true), [primary.id, scheduled.id])
        XCTAssertEqual(ids(primary: "main", includeCustom: false), [primary.id])
        XCTAssertEqual(ids(primary: nil, includeCustom: true), [scheduled.id])
        XCTAssertEqual(TrainingInduction.visibleProgramDays(in: data, slug: "custom").map(\.id), [scheduled.id])
        XCTAssertEqual(WorkoutReceipt.history(sessions: [manual], days: data.programDays, date: date, ownerID: owner).first?.session.id, manual.id)
    }

    func testPreviewAndPlayerUseAdjustedPrescriptionForAnyAccountAndRejectAnotherDay() {
        let owner = UUID(), dayID = UUID()
        let day = ProgramDay(id: dayID, userID: owner, programID: UUID(), weekday: 2,
                             name: "My plan", dayType: "strength", estimatedMinutes: 30,
                             warmupNote: "", sortOrder: 0, isActive: true)
        let exercise = Exercise(id: UUID(), userID: owner, programDayID: dayID, name: "Split squat",
                                sets: 5, repMin: 8, repMax: 12, repUnit: "reps", perSide: true,
                                restSeconds: 90, tempoUp: 1, tempoDown: 2, tempoPause: 0,
                                tempoNote: "", notes: "", incrementKG: 1, isLite: false,
                                optional: false, sortOrder: 0)
        let plan = PlannedDay(programDay: day, exercises: [
            PlannedExercise(exercise: exercise, plannedSets: 2, swapped: false)
        ])
        let resolved = SimpleHomeLogic.sessionExercises(plan: plan, ownerID: owner, programDayID: dayID)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].id, exercise.id)
        XCTAssertEqual(resolved[0].sets, 2, "Use planned sets, not the original five or a doubled per-side count")
        XCTAssertEqual(resolved[0].restSeconds, 90)
        XCTAssertTrue(resolved[0].perSide)
        XCTAssertTrue(SimpleHomeLogic.sessionExercises(plan: plan, ownerID: UUID(), programDayID: dayID).isEmpty)
        XCTAssertTrue(SimpleHomeLogic.sessionExercises(plan: plan, ownerID: owner, programDayID: UUID()).isEmpty)
    }

    func testDailySessionsKeepMorningOfficialAndCardioCompletionIndependent() {
        let owner = UUID(), foreignOwner = UUID(), programID = UUID()
        let date = "2026-11-04"
        func plan(_ name: String, ownerID: UUID? = nil, active: Bool = true) -> PlannedDay {
            let ownerID = ownerID ?? owner
            let day = ProgramDay(id: UUID(), userID: ownerID, programID: programID,
                                 weekday: 3, name: name, dayType: "push", estimatedMinutes: 20,
                                 warmupNote: "", sortOrder: 0, isActive: active)
            let exercise = Exercise(id: UUID(), userID: ownerID, programDayID: day.id, name: "Push-up",
                                    sets: 3, repMin: 8, repMax: 12, repUnit: "reps", perSide: false,
                                    restSeconds: 90, tempoUp: 1, tempoDown: 2, tempoPause: 0, tempoNote: "", notes: "",
                                    incrementKG: 0, isLite: false, optional: false, sortOrder: 0)
            return PlannedDay(programDay: day, exercises: [PlannedExercise(exercise: exercise, plannedSets: 3, swapped: false)])
        }
        let plans = [plan("AM · Morning circle"), plan("Pull A · Strength"), plan("Focus T25")]
        let ids = plans.map { $0.programDay!.id }
        func receipt(_ dayID: UUID, ownerID: UUID? = nil, on date: String = "2026-11-04", completed: Bool = true) -> WorkoutSession {
            WorkoutSession(id: UUID(), userID: ownerID ?? owner, date: date, programDayID: dayID,
                           isLite: false, isDeload: false, isEventRecovery: false, completed: completed,
                           qualityScore: 1, startedAt: nil, completedAt: nil, notes: "")
        }
        let morningReceipt = receipt(ids[0])
        let receipts = [morningReceipt, receipt(ids[1], on: "2026-11-03"),
                        receipt(ids[1], ownerID: foreignOwner), receipt(ids[2], completed: false), receipt(UUID())]
        let rows = SimpleHomeLogic.dailyGuidedSessions(plans: plans, sessions: receipts, ownerID: owner, date: date,
                                                      resumableModes: [ids[2]: true])
        XCTAssertEqual(rows.map(\.id), ids)
        XCTAssertEqual(rows.map(\.statusLabel), ["Completed", "Start", "Continue"])
        XCTAssertEqual(rows[0].completedSessionID, morningReceipt.id)
        XCTAssertEqual(rows[2].resumeLite, true)
        XCTAssertFalse(rows.allSatisfy { $0.completedSessionID != nil })
        XCTAssertTrue(SimpleHomeLogic.dailyGuidedSessions(plans: plans, sessions: ids.map { receipt($0) }, ownerID: owner, date: date)
            .allSatisfy { $0.completedSessionID != nil })
        XCTAssertTrue(SimpleHomeLogic.dailyGuidedSessions(plans: plans, sessions: receipts, ownerID: owner, date: "2026-11-05")
            .allSatisfy { $0.statusLabel == "Start" })
        let extraPlans = [plans[0], plans[0], plan("Foreign", ownerID: foreignOwner), plan("Old", active: false),
                          PlannedDay(programDay: plans[1].programDay)]
        XCTAssertEqual(SimpleHomeLogic.dailyGuidedSessions(plans: extraPlans, sessions: [], ownerID: owner, date: date).count, 1)
        XCTAssertTrue(SimpleHomeLogic.dailyGuidedSessions(plans: plans, sessions: [], ownerID: nil, date: date).isEmpty)
    }

    func testFitnessPlanIntroductionPersistsOnlyAfterBothPhaseSubtitlesAppear() {
        var state = FitnessPlanDisclosureState()

        state.toggle(introductionSeen: false)

        XCTAssertTrue(state.expanded)
        XCTAssertTrue(state.showsIntroduction)
        XCTAssertEqual(state.presentedIntroductionPhases, [])
        XCTAssertNil(state.activeInfo)
        XCTAssertFalse(state.recordIntroductionPresented(for: .transition))
        XCTAssertEqual(state.presentedIntroductionPhases, [.transition])
        XCTAssertTrue(state.recordIntroductionPresented(for: .main))
        XCTAssertEqual(state.presentedIntroductionPhases, [.transition, .main])
        XCTAssertFalse(state.recordIntroductionPresented(for: .main))
    }

    func testFitnessPlanRecurringDisclosureShowsOneInfoTooltipAndCollapsesCleanly() {
        var state = FitnessPlanDisclosureState()

        state.toggle(introductionSeen: true)

        XCTAssertTrue(state.expanded)
        XCTAssertFalse(state.showsIntroduction)
        XCTAssertEqual(state.presentedIntroductionPhases, [])
        state.selectInfo(.transition)
        XCTAssertEqual(state.activeInfo, .transition)
        state.selectInfo(.main)
        XCTAssertEqual(state.activeInfo, .main)
        state.selectInfo(.main)
        XCTAssertNil(state.activeInfo)

        state.toggle(introductionSeen: true)
        XCTAssertEqual(state, FitnessPlanDisclosureState())
    }

    func testFitnessPlanIntroductionNeverShowsInfoControlsAtTheSameTime() {
        var state = FitnessPlanDisclosureState()

        state.toggle(introductionSeen: false)
        state.selectInfo(.transition)

        XCTAssertTrue(state.showsIntroduction)
        XCTAssertNil(state.activeInfo)
    }

    func testInterfaceModeReadsSharedWebSettingsContract() {
        let userID = UUID()
        var settings = UserSettings(
            userID: userID,
            voiceOn: true,
            ticksOn: true,
            notificationsOn: false,
            guardianFactor: 1.4,
            addons: [:]
        )

        XCTAssertEqual(PortalUIMode.current(from: settings), .advanced)
        settings.addons["uiMode"] = .string("simple")
        XCTAssertEqual(PortalUIMode.current(from: settings), .simple)
    }

    func testCompletionIsRoundedAndClamped() {
        XCTAssertEqual(SimpleHomeLogic.completion(completed: 0, total: 0), 100)
        XCTAssertEqual(SimpleHomeLogic.completion(completed: 2, total: 3), 67)
        XCTAssertEqual(SimpleHomeLogic.completion(completed: 12, total: 10), 100)
        XCTAssertEqual(SimpleHomeLogic.completion(completed: -1, total: 10), 0)
    }

    func testDailyProgressCombinesUsefulPillarsAndWeightsLeanRecompActivity() {
        XCTAssertEqual(
            SimpleHomeLogic.dailyProgress(
                completedMeals: 1,
                totalMeals: 2,
                consumedKcal: 1_000,
                targetKcal: 2_000,
                consumedProteinG: 75,
                targetProteinG: 150,
                consumedCarbsG: 100,
                targetCarbsG: 200,
                consumedFatG: 30,
                targetFatG: 60,
                waterL: 1.35,
                waterTargetL: 3,
                workoutScheduled: true,
                workoutCompleted: true,
                activityProgress: 0.5,
                supplements: [
                    ("Creatine monohydrate", true),
                    ("Whey isolate", false),
                    ("Magnesium glycinate", false),
                ],
                goal: .recomp
            ),
            57
        )
    }

    func testSecondarySupplementsNeverLowerDailyProgress() {
        XCTAssertEqual(
            SimpleHomeLogic.dailyProgress(
                completedMeals: 1,
                totalMeals: 1,
                consumedKcal: 2_000,
                targetKcal: 2_000,
                consumedProteinG: 150,
                targetProteinG: 150,
                consumedCarbsG: 200,
                targetCarbsG: 200,
                consumedFatG: 60,
                targetFatG: 60,
                waterL: 2.7,
                waterTargetL: 3,
                workoutScheduled: false,
                workoutCompleted: false,
                activityProgress: 1,
                supplements: [("Magnesium glycinate", false)],
                goal: .maintain
            ),
            100
        )
        XCTAssertTrue(SimpleHomeLogic.isPrimaryDailySupplement("Creatine monohydrate"))
        XCTAssertTrue(SimpleHomeLogic.isPrimaryDailySupplement("Micellar casein"))
        XCTAssertFalse(SimpleHomeLogic.isPrimaryDailySupplement("Magnesium glycinate"))
    }

    func testActivityProgressUsesPersonaAndGoalThresholds() {
        XCTAssertEqual(
            SimpleHomeLogic.activityProgress(
                persona: .constantine, goal: .recomp,
                steps: 0, activeCalories: 250, exerciseMinutes: 0
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SimpleHomeLogic.activityProgress(
                persona: .constantine, goal: .recomp,
                steps: 0, activeCalories: 0, exerciseMinutes: 25
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SimpleHomeLogic.activityProgress(
                persona: .june, goal: .recomp,
                steps: 0, activeCalories: 175, exerciseMinutes: 0
            ),
            0.5,
            accuracy: 0.001
        )
    }

    func testACutInAnySlotGetsTheDeficitsActivityGoal() {
        let ownerID = UUID()
        let fatLoss = UserSettings(
            userID: ownerID, voiceOn: false, ticksOn: false, notificationsOn: false, guardianFactor: 1,
            addons: ["training_induction": .object(["goal": .string("fat_loss"), "plan_weeks": .number(12)])]
        )
        for slot in Goal.allCases {
            XCTAssertEqual(NutritionGoalPolicy.energyGoal(for: slot, settings: fatLoss), .recomp)
            XCTAssertEqual(
                SimpleHomeLogic.activityProgress(
                    persona: .iulian, goal: NutritionGoalPolicy.energyGoal(for: slot, settings: fatLoss),
                    steps: 0, activeCalories: 250, exerciseMinutes: 0
                ),
                0.5, accuracy: 0.001,
                "\(slot) on a fat-loss plan: 250 kcal is half of the 500 kcal a deficit asks for"
            )
        }
        XCTAssertEqual(NutritionGoalPolicy.energyGoal(for: .maintain, settings: nil), .maintain)
    }

    func testResolvedDailyActivityUsesWearableBurnAndExerciseForItsLevel() {
        let wearable = WearableActivityRecord(
            date: "2026-08-28",
            steps: 0,
            activeCalories: 90,
            exerciseMinutes: 25,
            source: "apple_health",
            updatedAt: "2026-08-28T08:00:00Z"
        )

        let resolved = WearableActivityEngine.resolve(
            persona: .constantine,
            wearable: wearable,
            logs: []
        )

        XCTAssertEqual(resolved.activeCalories, 90)
        XCTAssertEqual(resolved.level, .moderate)
    }

    func testNextActionPrefersLatestDueThenEarliestUpcoming() {
        XCTAssertEqual(SimpleHomeLogic.nextCandidateIndex(times: [420, 720, 1_140], nowMinutes: 800), 1)
        XCTAssertEqual(SimpleHomeLogic.nextCandidateIndex(times: [420, 720, 1_140], nowMinutes: 300), 0)
        XCTAssertNil(SimpleHomeLogic.nextCandidateIndex(times: [], nowMinutes: 800))
    }

    func testBespokeAccountsProjectMainPhaseWithoutChangingOrdinaryAccounts() {
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .constantine,
                mainIsUsable: true,
                transitionIsUsable: true
            ),
            "main"
        )
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .june,
                mainIsUsable: true,
                transitionIsUsable: true
            ),
            "main"
        )
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .constantine,
                mainIsUsable: false,
                transitionIsUsable: true
            ),
            "transition"
        )
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .matthew,
                mainIsUsable: true,
                transitionIsUsable: true
            ),
            "transition"
        )
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .iulian,
                mainIsUsable: true,
                transitionIsUsable: false
            ),
            "main"
        )
    }

    func testSponsoredOnlyClientNeverFallsBackToAPersonalWorkoutPlan() {
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .constantine,
                mainIsUsable: true,
                transitionIsUsable: true,
                coachManaged: true
            ),
            "coach"
        )
        XCTAssertEqual(
            SimpleHomeLogic.guidedProgramSlug(
                persona: .matthew,
                mainIsUsable: false,
                transitionIsUsable: true,
                coachManaged: true
            ),
            "coach"
        )
    }

    func testSeededConstantineSimpleHomeResolvesTheMainWorkout() {
        let data = APEXDebugFixture.dashboard()
        let slug = SimpleHomeLogic.guidedProgramSlug(
            persona: data.profile?.persona,
            mainIsUsable: TrainingInduction.hasUsablePrescription(in: data, slug: "main"),
            transitionIsUsable: TrainingInduction.hasUsablePrescription(in: data, slug: "transition")
        )

        XCTAssertEqual(slug, "main")
        XCTAssertEqual(TrainingInduction.visibleProgramDays(in: data, slug: slug).map(\.name), ["Upper strength"])
    }

    func testCompletedTrainingOpensTheLatestReceiptForThatExactDayAndPrescription() {
        let userID = UUID()
        let dayID = UUID()
        let olderID = UUID()
        let latestID = UUID()
        let sessions = [
            WorkoutSession(
                id: olderID, userID: userID, date: "2026-08-21", programDayID: dayID,
                isLite: false, isDeload: false, isEventRecovery: false, completed: true,
                qualityScore: 1, startedAt: "2026-08-21T17:00:00Z",
                completedAt: "2026-08-21T18:00:00Z", notes: ""
            ),
            WorkoutSession(
                id: UUID(), userID: userID, date: "2026-08-21", programDayID: dayID,
                isLite: false, isDeload: false, isEventRecovery: false, completed: false,
                qualityScore: 1, startedAt: "2026-08-21T19:00:00Z",
                completedAt: nil, notes: ""
            ),
            WorkoutSession(
                id: latestID, userID: userID, date: "2026-08-21", programDayID: dayID,
                isLite: true, isDeload: false, isEventRecovery: false, completed: true,
                qualityScore: 1, startedAt: "2026-08-21T19:30:00Z",
                completedAt: "2026-08-21T20:00:00Z", notes: ""
            ),
            WorkoutSession(
                id: UUID(), userID: userID, date: "2026-08-22", programDayID: dayID,
                isLite: false, isDeload: false, isEventRecovery: false, completed: true,
                qualityScore: 1, startedAt: nil, completedAt: nil, notes: ""
            ),
        ]

        XCTAssertEqual(
            SimpleHomeLogic.completedSessionID(
                sessions: sessions,
                ownerID: userID,
                date: "2026-08-21",
                programDayID: dayID
            ),
            latestID
        )
        XCTAssertNil(
            SimpleHomeLogic.completedSessionID(
                sessions: sessions,
                ownerID: userID,
                date: "2026-08-21",
                programDayID: UUID()
            )
        )
    }

    func testMorningCheckAcceptsWeightWithoutFabricatingAnAppleSleepScore() {
        let metric = MorningCheckLogic.entry(
            sleep: "",
            recovery: "",
            weight: "87,4",
            source: "apple",
            weightUnit: .kilograms
        )

        XCTAssertEqual(metric?.weightKG, 87.4)
        XCTAssertNil(metric?.sleepScore)
        XCTAssertNil(metric?.recoveryScore)

        let imperial = MorningCheckLogic.entry(
            sleep: "57",
            recovery: "",
            weight: "192.7",
            source: "apple",
            weightUnit: .pounds
        )
        XCTAssertEqual(imperial?.sleepScore, 57)
        XCTAssertEqual(imperial?.weightKG ?? 0, 87.41, accuracy: 0.02)
        XCTAssertNil(MorningCheckLogic.entry(
            sleep: "70", recovery: "", weight: "",
            source: "other", weightUnit: .kilograms
        ))
    }

    func testMorningWeightPreservesExistingDailyNutritionFacts() {
        let userID = UUID()
        let existing = DailyLog(
            id: UUID(), userID: userID, date: "2026-08-25",
            kcal: 1_900, proteinG: 160, fatG: 65, carbsG: 210,
            waterL: 2.4, estimatedTDEE: 2_600, computedPAL: 1.55,
            activityMode: "precise", weightKG: 88
        )

        let updated = MorningCheckLogic.applyingWeight(
            87.4,
            to: existing,
            userID: userID,
            date: "2026-08-25",
            activityMode: "quick"
        )

        XCTAssertEqual(updated.id, existing.id)
        XCTAssertEqual(updated.kcal, 1_900)
        XCTAssertEqual(updated.proteinG, 160)
        XCTAssertEqual(updated.waterL, 2.4)
        XCTAssertEqual(updated.activityMode, "precise")
        XCTAssertEqual(updated.weightKG, 87.4)
    }

    func testIdentityHidesOnlyAPersonaThatDuplicatesTheDisplayName() {
        XCTAssertFalse(ProfileIdentityPresentation.showsPersona(
            displayName: "Constantine", personaName: "CONSTANTINE"
        ))
        XCTAssertFalse(ProfileIdentityPresentation.showsPersona(
            displayName: "Iulian", personaName: "IULIÁN"
        ))
        XCTAssertTrue(ProfileIdentityPresentation.showsPersona(
            displayName: "Iulian-Andrei", personaName: "Iulian"
        ))
    }
}
