import XCTest
@testable import APEX

final class EnergyEngineTests: XCTestCase {
    func testNutritionBalanceReportsActualExcessInsteadOfZeroRemaining() {
        let balance = NutritionCalorieBalance.resolve(target: 1_685, consumed: 2_119)

        XCTAssertEqual(balance.label, "Exceeding by")
        XCTAssertEqual(balance.amount, 434)
        XCTAssertTrue(balance.isOverTarget)
    }

    func testNutritionBalanceStillReportsCaloriesRemainingBelowTarget() {
        let balance = NutritionCalorieBalance.resolve(target: 1_685, consumed: 1_200)

        XCTAssertEqual(balance.label, "Remaining")
        XCTAssertEqual(balance.amount, 485)
        XCTAssertFalse(balance.isOverTarget)
    }

    func testActivityCatalogueLeadsWithBroadlyUsefulGroupsBeforeSpecialistWork() {
        XCTAssertEqual(
            ActivityCategoryPresentation.order,
            ["work", "life", "camera", "therapy", "training", "device"]
        )
        XCTAssertEqual(
            ActivityCategoryPresentation.order.map(ActivityCategoryPresentation.title),
            [
                "Work: general",
                "Errands & life",
                "Work: camera",
                "Work: hands-on therapy",
                "Training",
                "Device import",
            ]
        )
    }

    func testQuickSedentaryRecompUsesProfileAndSafetyFloor() {
        let result = EnergyEngine.targets(profile: profile(weight: 70, level: .sedentary, goal: .recomp), logs: [], catalog: [])

        XCTAssertEqual(result.bmr, 1_580)
        XCTAssertEqual(result.tdee, 1_896)
        XCTAssertEqual(result.pal, 1.20, accuracy: 0.001)
        XCTAssertEqual(result.level, .sedentary)
        XCTAssertGreaterThanOrEqual(result.targetCalories, Int((Double(result.bmr) * 1.05).rounded(.down)))
    }

    func testMeasuredRestingEnergyOverridesEstimatedBMRForGenericProfiles() {
        let result = EnergyEngine.targets(
            profile: profile(
                weight: 70,
                level: .moderate,
                goal: .maintain,
                customBMR: 1_683
            ),
            logs: [],
            catalog: []
        )

        XCTAssertEqual(result.bmr, 1_683)
        XCTAssertEqual(result.tdee, 2_609)
        XCTAssertEqual(result.targetCalories, 2_609)
    }

    func testOwnedSettingsMeasuredRestingEnergyOverridesLegacyProfileValue() {
        let storedProfile = profile(
            weight: 70,
            level: .moderate,
            goal: .maintain,
            customBMR: 1_500
        )
        let settings = UserSettings(
            userID: storedProfile.userID,
            voiceOn: true,
            ticksOn: true,
            notificationsOn: true,
            guardianFactor: 0.96,
            addons: ["custom_bmr": .number(1_683)]
        )

        let result = EnergyEngine.targets(
            profile: storedProfile,
            logs: [],
            catalog: [],
            settings: settings
        )

        XCTAssertEqual(result.bmr, 1_683)
        XCTAssertEqual(result.tdee, 2_609)
    }

    func testExplicitNullClearsLegacyMeasuredRestingEnergyForTheSameOwner() {
        let storedProfile = profile(
            weight: 70,
            level: .sedentary,
            goal: .maintain,
            customBMR: 1_683
        )
        let settings = UserSettings(
            userID: storedProfile.userID,
            voiceOn: true,
            ticksOn: true,
            notificationsOn: true,
            guardianFactor: 0.96,
            addons: ["custom_bmr": .null]
        )

        let result = EnergyEngine.targets(
            profile: storedProfile,
            logs: [],
            catalog: [],
            settings: settings
        )

        XCTAssertEqual(result.bmr, 1_580)
        XCTAssertEqual(result.tdee, 1_896)
    }

    func testSettingsMeasuredRestingEnergyNeverCrossesAccountBoundary() {
        let storedProfile = profile(
            weight: 70,
            level: .sedentary,
            goal: .maintain
        )
        let otherAccountsSettings = UserSettings(
            userID: UUID(),
            voiceOn: true,
            ticksOn: true,
            notificationsOn: true,
            guardianFactor: 0.96,
            addons: ["custom_bmr": .number(1_683)]
        )

        let result = EnergyEngine.targets(
            profile: storedProfile,
            logs: [],
            catalog: [],
            settings: otherAccountsSettings
        )

        XCTAssertEqual(result.bmr, 1_580)
        XCTAssertEqual(result.tdee, 1_896)
    }

    func testFreshRemoteExplicitClearWinsOverSameOwnersCachedLegacyMeasuredBMR() {
        let ownerID = UUID()
        var remote = APEXDebugFixture.dashboard(userID: ownerID)
        remote.profile?.customBMR = nil
        remote.settings?.addons["custom_bmr"] = .null
        var cached = APEXDebugFixture.dashboard(userID: ownerID)
        cached.profile?.customBMR = 1_683

        let migrated = RestingEnergyPolicy.migrateLegacyProfileValue(
            in: &remote,
            ownerID: ownerID,
            fallbackProfile: cached.profile
        )

        XCTAssertNil(migrated)
        XCTAssertEqual(remote.settings?.addons["custom_bmr"], .null)
    }

    func testFreshRemoteMissingKeyCanMigrateSameOwnersCachedLegacyMeasuredBMR() {
        let ownerID = UUID()
        var remote = APEXDebugFixture.dashboard(userID: ownerID)
        remote.profile?.customBMR = nil
        remote.settings?.addons.removeValue(forKey: "custom_bmr")
        var cached = APEXDebugFixture.dashboard(userID: ownerID)
        cached.profile?.customBMR = 1_683

        let migrated = RestingEnergyPolicy.migrateLegacyProfileValue(
            in: &remote,
            ownerID: ownerID,
            fallbackProfile: cached.profile
        )

        XCTAssertEqual(migrated?.addons["custom_bmr"]?.numberValue, 1_683)
        XCTAssertEqual(remote.settings?.addons["custom_bmr"]?.numberValue, 1_683)
    }

    func testRemoteProfilePersistencePayloadNeverWritesSettingsBackedCustomBMRColumn() throws {
        let operation = try OfflineOperation.upsert(
            profile(weight: 70, goal: .maintain, customBMR: 1_683),
            table: "profile",
            onConflict: "user_id"
        )
        let encoded = try XCTUnwrap(operation.payload)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertNil(object["custom_bmr"])
        XCTAssertEqual(object["goal"] as? String, Goal.maintain.rawValue)
    }

    func testLegacyJSONProfilePayloadDropsCustomBMRBeforeRemoteReplay() throws {
        let operation = try OfflineOperation.upsert(
            JSONValue.object([
                "id": .string(UUID().uuidString.lowercased()),
                "user_id": .string(UUID().uuidString.lowercased()),
                "goal": .string(Goal.maintain.rawValue),
                "custom_bmr": .number(1_683),
            ]),
            table: "profile",
            onConflict: "user_id"
        )
        let encoded = try XCTUnwrap(operation.payload)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertNil(object["custom_bmr"])
        XCTAssertEqual(object["goal"] as? String, Goal.maintain.rawValue)
    }

    func testLiteralMeasuredBMRAndObservedTDEEResolveEveryCurrentGoalFactor() {
        XCTAssertEqual(
            EnergyEngine.targetCalories(bmr: 1_683, tdee: 1_870, goal: Goal.recomp),
            1_767
        )
        XCTAssertEqual(
            EnergyEngine.targetCalories(bmr: 1_683, tdee: 1_870, goal: Goal.maintain),
            1_870
        )
        XCTAssertEqual(
            EnergyEngine.targetCalories(bmr: 1_683, tdee: 1_870, goal: Goal.bulk),
            2_001
        )
    }

    func testConstantineBespokeModerateRecompRemainsFixedWhenActivityLogsExist() {
        let result = EnergyEngine.targets(
            profile: profile(
                userID: UUID(uuidString: "9a0fffbc-bb02-40ac-834a-d4e339b32574")!,
                weight: 71,
                level: .moderate,
                goal: .recomp,
                persona: .constantine,
                profileKind: .bespoke,
                protocolID: .constantineV85,
                bodyFatPercent: 22.5,
                customBMR: 1_680,
                heightCM: 177,
                birthdate: "1992-07-25"
            ),
            logs: [log(typeID: "watch-strength", kcal: 900)],
            catalog: []
        )

        XCTAssertEqual(result.targetCalories, 2_450)
        XCTAssertEqual(result.tdee, 2_550)
        XCTAssertEqual(result.proteinG, 150)
        XCTAssertEqual(result.fatG, 75)
        XCTAssertEqual(result.carbsG, 294)
    }

    func testJuneBespokeModerateBulkRemainsFixedWhenActivityLogsExist() {
        let result = EnergyEngine.targets(
            profile: profile(
                userID: UUID(uuidString: "f1cc8158-0480-47c9-a2f1-bd03890182f9")!,
                weight: 41,
                level: .moderate,
                goal: .bulk,
                persona: .june,
                profileKind: .bespoke,
                protocolID: .juneV84,
                sex: "female",
                bodyFatPercent: 18,
                heightCM: 153,
                birthdate: "1983-06-19"
            ),
            logs: [log(typeID: "watch-strength", kcal: 900)],
            catalog: []
        )

        XCTAssertEqual(result.targetCalories, 2_400)
        XCTAssertEqual(result.tdee, 2_300)
        XCTAssertEqual(result.proteinG, 85)
        XCTAssertEqual(result.fatG, 95)
        XCTAssertEqual(result.carbsG, 301)
    }

    func testEveryConstantineAndJuneGoalActivityCombinationMatchesAuthoredTables() {
        let levels: [ActivityLevel] = [.sedentary, .light, .moderate, .very, .extra]
        let goals: [Goal] = [.recomp, .maintain, .bulk]
        let fixtures: [(
            userID: UUID,
            persona: Persona,
            protocolID: ProfileIntegrityPolicy.ProtocolID,
            weight: Double,
            calories: [Goal: [Int]],
            maintain: [Int],
            protein: [Goal: Int],
            fat: [Goal: Int]
        )] = [
            (
                UUID(uuidString: "9a0fffbc-bb02-40ac-834a-d4e339b32574")!,
                .constantine,
                .constantineV85,
                71,
                [
                    .recomp: [2_300, 2_400, 2_450, 2_650, 2_900],
                    .maintain: [2_400, 2_500, 2_550, 2_750, 3_000],
                    .bulk: [2_550, 2_650, 2_700, 2_900, 3_150],
                ],
                [2_400, 2_500, 2_550, 2_750, 3_000],
                [.recomp: 150, .maintain: 150, .bulk: 150],
                [.recomp: 75, .maintain: 80, .bulk: 85]
            ),
            (
                UUID(uuidString: "f1cc8158-0480-47c9-a2f1-bd03890182f9")!,
                .june,
                .juneV84,
                41,
                [
                    .recomp: [2_200, 2_200, 2_200, 2_350, 2_550],
                    .maintain: [2_200, 2_250, 2_300, 2_450, 2_650],
                    .bulk: [2_300, 2_350, 2_400, 2_550, 2_750],
                ],
                [2_200, 2_250, 2_300, 2_450, 2_650],
                [.recomp: 85, .maintain: 85, .bulk: 85],
                [.recomp: 90, .maintain: 92, .bulk: 95]
            ),
        ]

        for fixture in fixtures {
            for (levelIndex, level) in levels.enumerated() {
                for goal in goals {
                    let result = EnergyEngine.targets(
                        profile: profile(
                            userID: fixture.userID,
                            weight: fixture.weight,
                            level: level,
                            goal: goal,
                            persona: fixture.persona,
                            profileKind: .bespoke,
                            protocolID: fixture.protocolID,
                            sex: fixture.persona == .june ? "female" : "male"
                        ),
                        logs: [log(typeID: "strength", kcal: 900)],
                        catalog: [],
                        wearableActiveCalories: 1_100
                    )

                    XCTAssertEqual(
                        result.targetCalories,
                        fixture.calories[goal]?[levelIndex],
                        "\(fixture.persona.rawValue) \(goal.rawValue) \(level.rawValue) calories"
                    )
                    XCTAssertEqual(result.tdee, fixture.maintain[levelIndex])
                    XCTAssertEqual(result.proteinG, fixture.protein[goal])
                    XCTAssertEqual(result.fatG, fixture.fat[goal])
                    XCTAssertFalse(result.safetyFloorApplied)
                }
            }
        }
    }

    func testNetBlocksAvoidRestingEnergyDoubleCount() {
        let profile = profile(weight: 70)
        let massage = activity(id: "massage-session", met: 4, input: .count, minutes: 60)
        let market = activity(id: "supermarket-trip", met: 3, input: .count, minutes: 25)
        let steps = activity(id: "incidental-steps", met: 1.2, input: .steps)

        let massageKcal = EnergyEngine.blockCalories(type: massage, quantity: 2, durationMinutes: 60, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let marketKcal = EnergyEngine.blockCalories(type: market, quantity: 1, durationMinutes: 25, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let stepsKcal = EnergyEngine.blockCalories(type: steps, quantity: 8_000, durationMinutes: nil, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let logs = [
            log(typeID: massage.id, kcal: massageKcal),
            log(typeID: market.id, kcal: marketKcal),
            log(typeID: steps.id, kcal: stepsKcal)
        ]
        let result = EnergyEngine.targets(profile: profile, logs: logs, catalog: [massage, market, steps])

        XCTAssertEqual(massageKcal, 392, accuracy: 0.01)
        XCTAssertEqual(marketKcal, 52.5, accuracy: 0.01)
        XCTAssertEqual(stepsKcal, 308, accuracy: 0.01)
        XCTAssertEqual(result.tdee, 2_648)
        XCTAssertEqual(result.level, .moderate)
    }

    func testDistanceAndDiscountedWatchUseMaximumNotSum() {
        let run = activity(id: "jog-run", met: 7, input: .distance, distanceFactor: 1, supportsWatch: true)
        let result = EnergyEngine.blockCalories(
            type: run,
            quantity: 1,
            durationMinutes: nil,
            distanceKM: 5,
            watchKcal: 420,
            weightKG: 70
        )

        XCTAssertEqual(result, 350, accuracy: 0.001)
    }

    func testWearableActiveEnergySupersedesRatherThanAddsActivityEstimates() {
        let logs = [
            log(typeID: "strength", kcal: 400),
            log(typeID: "walk", kcal: 200),
        ]

        XCTAssertEqual(
            EnergyEngine.resolvedActiveCalories(wearableActiveCalories: 900, logs: logs),
            900
        )
        XCTAssertEqual(
            EnergyEngine.resolvedActiveCalories(wearableActiveCalories: nil, logs: logs),
            600
        )
        XCTAssertEqual(
            EnergyEngine.resolvedActiveCalories(wearableActiveCalories: -20, logs: logs),
            600
        )
    }

    func testGenericPreciseTargetsDoNotAddWearableBurnToActivityEstimatesAgain() {
        let result = EnergyEngine.targets(
            profile: profile(
                weight: 70,
                level: .moderate,
                goal: .maintain,
                customBMR: 1_683
            ),
            logs: [
                log(typeID: "strength", kcal: 400),
                log(typeID: "walk", kcal: 200),
            ],
            catalog: [],
            wearableActiveCalories: 900
        )

        XCTAssertEqual(result.tdee, 2_920)
        XCTAssertEqual(result.targetCalories, 2_920)
    }

    func testZeroWearableValueCannotEraseValidActivityLogs() {
        let result = EnergyEngine.targets(
            profile: profile(
                weight: 70,
                level: .moderate,
                goal: .maintain,
                customBMR: 1_683
            ),
            logs: [
                log(typeID: "strength", kcal: 400),
                log(typeID: "walk", kcal: 200),
            ],
            catalog: [],
            wearableActiveCalories: 0
        )

        XCTAssertEqual(result.tdee, 2_620)
        XCTAssertEqual(result.targetCalories, 2_620)
    }

    func testWearableBurnDoesNotActAsQuickModeCalorieEatBack() {
        let generic = profile(
            weight: 70,
            level: .moderate,
            goal: .maintain,
            customBMR: 1_683
        )
        let withoutWearable = EnergyEngine.targets(
            profile: generic,
            logs: [],
            catalog: []
        )
        let withWearable = EnergyEngine.targets(
            profile: generic,
            logs: [],
            catalog: [],
            wearableActiveCalories: 900
        )

        XCTAssertEqual(withWearable, withoutWearable)
        XCTAssertEqual(withWearable.targetCalories, 2_609)
    }

    func testWearableImportNeverSilentlyChangesAnAuthoredPersonalProtocolMode() {
        XCTAssertFalse(
            WearableActivityEngine.shouldAutomaticallyApplyMode(
                profile: profile(
                    userID: UUID(uuidString: "9a0fffbc-bb02-40ac-834a-d4e339b32574")!,
                    weight: 71,
                    persona: .constantine,
                    profileKind: .bespoke,
                    protocolID: .constantineV85
                ),
                requested: true,
                hasActivityLogs: false
            )
        )
        XCTAssertFalse(
            WearableActivityEngine.shouldAutomaticallyApplyMode(
                profile: profile(
                    userID: UUID(uuidString: "f1cc8158-0480-47c9-a2f1-bd03890182f9")!,
                    weight: 41,
                    persona: .june,
                    profileKind: .bespoke,
                    protocolID: .juneV84,
                    sex: "female"
                ),
                requested: true,
                hasActivityLogs: false
            )
        )
        XCTAssertTrue(
            WearableActivityEngine.shouldAutomaticallyApplyMode(
                profile: profile(weight: 70, persona: .iulian),
                requested: true,
                hasActivityLogs: false
            )
        )
        XCTAssertFalse(
            WearableActivityEngine.shouldAutomaticallyApplyMode(
                profile: profile(weight: 70, persona: .iulian),
                requested: true,
                hasActivityLogs: true
            )
        )
    }

    func testWearableTargetEnergyIsIsolatedByOwnerAndDate() {
        let ownerID = UUID()
        let settings = UserSettings(
            userID: ownerID,
            voiceOn: true,
            ticksOn: true,
            notificationsOn: true,
            guardianFactor: 0.96,
            addons: [
                "watch_activity_history": .array([
                    WearableActivityRecord(
                        date: "2026-08-29",
                        steps: 8_000,
                        activeCalories: 640,
                        exerciseMinutes: 55,
                        source: "apple_health",
                        updatedAt: "2026-08-29T20:00:00Z"
                    ).jsonValue,
                    WearableActivityRecord(
                        date: "2026-08-30",
                        steps: 4_000,
                        activeCalories: 320,
                        exerciseMinutes: 25,
                        source: "apple_health",
                        updatedAt: "2026-08-30T12:00:00Z"
                    ).jsonValue,
                ])
            ]
        )

        XCTAssertEqual(
            WearableActivityRecord.activeCalories(
                on: "2026-08-29",
                settings: settings,
                ownerID: ownerID
            ),
            640
        )
        XCTAssertNil(
            WearableActivityRecord.activeCalories(
                on: "2026-08-29",
                settings: settings,
                ownerID: UUID()
            )
        )
        XCTAssertNil(
            WearableActivityRecord.activeCalories(
                on: "2026-08-31",
                settings: settings,
                ownerID: ownerID
            )
        )
    }

    func testChampionshipWorkloadMapsToExtraActive() {
        let profile = profile(weight: 70)
        let filming = activity(id: "gimbal-filming", met: 3.2, input: .duration)
        let travel = activity(id: "travel-day", met: 2.5, input: .duration)
        let filmingKcal = EnergyEngine.blockCalories(type: filming, quantity: 1, durationMinutes: 480, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let travelKcal = EnergyEngine.blockCalories(type: travel, quantity: 1, durationMinutes: 120, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let result = EnergyEngine.targets(
            profile: profile,
            logs: [log(typeID: filming.id, kcal: filmingKcal), log(typeID: travel.id, kcal: travelKcal)],
            catalog: [filming, travel]
        )

        XCTAssertEqual(result.level, .extra)
        XCTAssertGreaterThanOrEqual(result.pal, 2)
    }

    func testGoalChangeRecalculatesEveryMacroAndEnergyStillBalances() {
        let recomp = EnergyEngine.targets(profile: profile(weight: 70, level: .moderate, goal: .recomp), logs: [], catalog: [])
        let maintain = EnergyEngine.targets(profile: profile(weight: 70, level: .moderate, goal: .maintain), logs: [], catalog: [])
        let bulk = EnergyEngine.targets(profile: profile(weight: 70, level: .moderate, goal: .bulk), logs: [], catalog: [])

        XCTAssertGreaterThan(recomp.proteinG, maintain.proteinG)
        XCTAssertGreaterThan(maintain.proteinG, bulk.proteinG)
        XCTAssertLessThan(recomp.fatG, maintain.fatG)
        XCTAssertLessThan(maintain.fatG, bulk.fatG)
        XCTAssertLessThan(recomp.carbsG, maintain.carbsG)
        XCTAssertLessThan(maintain.carbsG, bulk.carbsG)

        for target in [recomp, maintain, bulk] {
            let macroCalories = target.proteinG * 4 + target.fatG * 9 + target.carbsG * 4
            XCTAssertLessThanOrEqual(abs(macroCalories - target.targetCalories), 2)
        }
    }

    func testQuestionnaireGoalsResolveThreePlanAwareEnergyChoices() {
        let expected: [String: [String]] = [
            "rebuild": ["Light balance", "Balanced fitness", "Fuel progress"],
            "muscle": ["Lean recomp", "Maintain", "Lean bulk"],
            "fat_loss": ["Accelerated cut", "Steady cut", "Gentle cut"],
            "strength": ["Strength recomp", "Strength base", "Power surplus"],
            "endurance": ["Light fuel", "Balanced fuel", "High-volume fuel"],
        ]

        for (trainingGoal, labels) in expected {
            let presets = NutritionGoalPolicy.presets(
                context: .init(trainingGoal: trainingGoal, planWeeks: 12)
            )
            XCTAssertEqual(presets.map(\.label), labels)
            XCTAssertEqual(presets.map(\.goal), [.recomp, .maintain, .bulk])
            XCTAssertTrue(presets.allSatisfy { $0.explanation.count > 20 })
            XCTAssertTrue(presets.allSatisfy { $0.caution.count > 20 })
        }
    }

    func testShortFatLossPlanStaysBoundedAndFeedsTheEnergyEngine() {
        let fourWeek = NutritionGoalPolicy.presets(
            context: .init(trainingGoal: "fat_loss", planWeeks: 4)
        )
        let sixMonth = NutritionGoalPolicy.presets(
            context: .init(trainingGoal: "fat_loss", planWeeks: 26)
        )
        XCTAssertEqual(fourWeek[0].factor, 0.80, accuracy: 0.0001)
        XCTAssertEqual(sixMonth[0].factor, 0.86, accuracy: 0.0001)
        XCTAssertTrue(fourWeek.allSatisfy { $0.factor >= 0.80 && $0.factor < 1 })

        let context = NutritionPlanContext(trainingGoal: "fat_loss", planWeeks: 8)
        let result = EnergyEngine.targets(
            profile: profile(weight: 80, level: .moderate, goal: .maintain),
            logs: [],
            catalog: [],
            planContext: context
        )
        let factor = NutritionGoalPolicy.presets(context: context)[1].factor
        XCTAssertEqual(
            result.targetCalories,
            Int(max(Double(result.bmr) * 1.05, Double(result.tdee) * factor).rounded())
        )
        XCTAssertEqual(NutritionGoalPolicy.recommendedGoal(for: "fat_loss"), .maintain)
        XCTAssertEqual(NutritionGoalPolicy.recommendedGoal(for: "muscle"), .bulk)
    }

    func testMacroPolicyMatchesCrossClientLiteralFixtures() {
        XCTAssertEqual(
            EnergyEngine.macroTargets(
                weightKG: 70, level: .moderate, goal: .recomp, targetCalories: 2_200
            ),
            .init(proteinG: 147, fatG: 61, carbsG: 266)
        )
        XCTAssertEqual(
            EnergyEngine.macroTargets(
                weightKG: 70, level: .moderate, goal: .maintain, targetCalories: 2_400
            ),
            .init(proteinG: 133, fatG: 73, carbsG: 303)
        )
        XCTAssertEqual(
            EnergyEngine.macroTargets(
                weightKG: 70, level: .moderate, goal: .bulk, targetCalories: 2_600
            ),
            .init(proteinG: 126, fatG: 81, carbsG: 342)
        )
    }

    func testCalibrationNudgesUpwardAndClamps() {
        let next = EnergyEngine.calibratedK(
            currentK: 1,
            meanDailyIntake: 2_300,
            predictedDailyTDEE: 2_100,
            startingEMAWeight: 70,
            endingEMAWeight: 70,
            elapsedDays: 13
        )
        XCTAssertEqual(next, 1.0190476, accuracy: 0.00001)

        let clamped = EnergyEngine.calibratedK(
            currentK: 1.14,
            meanDailyIntake: 4_000,
            predictedDailyTDEE: 1_800,
            startingEMAWeight: 70,
            endingEMAWeight: 70,
            elapsedDays: 13
        )
        XCTAssertEqual(clamped, 1.15, accuracy: 0.00001)
    }

    func testSameCatalogBlockUsesViewingUsersWeight() {
        let massage = activity(id: "massage-session", met: 4, input: .count, minutes: 60)
        let at70 = EnergyEngine.blockCalories(type: massage, quantity: 1, durationMinutes: 60, distanceKM: nil, watchKcal: nil, weightKG: 70)
        let at58 = EnergyEngine.blockCalories(type: massage, quantity: 1, durationMinutes: 60, distanceKM: nil, watchKcal: nil, weightKG: 58)

        XCTAssertEqual(at70, 196, accuracy: 0.001)
        XCTAssertEqual(at58, 162.4, accuracy: 0.001)
        XCTAssertNotEqual(at70, at58)
    }

    private func profile(
        userID: UUID = UUID(),
        weight: Double,
        level: ActivityLevel = .sedentary,
        goal: Goal = .recomp,
        persona: Persona = .iulian,
        profileKind: ProfileIntegrityPolicy.Kind = .standard,
        protocolID: ProfileIntegrityPolicy.ProtocolID? = nil,
        sex: String = "male",
        bodyFatPercent: Double? = 20,
        bodyFatSource: ProfileIntegrityPolicy.BodyFatSource? = .dexa,
        customBMR: Double? = nil,
        heightCM: Double = 175,
        birthdate: String = "1990-01-01"
    ) -> Profile {
        return Profile(
            id: userID,
            userID: userID,
            persona: persona,
            profileKind: profileKind,
            bespokeProtocolID: protocolID,
            displayName: "Test User",
            sex: sex,
            weightKG: weight,
            bodyFatPercent: bodyFatPercent,
            bodyFatSource: bodyFatSource,
            bodyFatMeasuredAt: nil,
            customBMR: customBMR,
            heightCM: heightCM,
            birthdate: birthdate,
            activityLevel: level,
            goal: goal,
            targetKcal: nil,
            targetProteinG: nil,
            targetFatG: nil,
            targetCarbsG: nil,
            trainingTime: "07:00",
            baselineDate: "2026-01-01",
            profileNote: "",
            seedVersion: 1,
            calibrationK: 1,
            calibrationHistory: [],
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    private func activity(
        id: String,
        met: Double,
        input: ActivityInputStyle,
        minutes: Int? = nil,
        distanceFactor: Double? = nil,
        supportsWatch: Bool = false
    ) -> ActivityType {
        ActivityType(
            id: id,
            category: "test",
            name: id,
            icon: "figure.walk",
            met: met,
            inputStyle: input,
            defaultDurationMinutes: minutes,
            isTrainingLinked: false,
            notes: "",
            distanceFactor: distanceFactor,
            supportsWatch: supportsWatch
        )
    }

    private func log(typeID: String, kcal: Double) -> ActivityLog {
        let id = UUID()
        return ActivityLog(
            id: id,
            userID: id,
            date: "2026-08-16",
            typeID: typeID,
            quantity: 1,
            durationMinutes: nil,
            distanceKM: nil,
            watchKcal: nil,
            computedKcal: kcal,
            source: "manual",
            reconciled: false,
            createdAt: "2026-08-16T00:00:00Z",
            updatedAt: "2026-08-16T00:00:00Z"
        )
    }
}
