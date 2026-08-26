#if DEBUG
import Foundation

enum APEXDebugFixture {
    static func dashboard(userID: UUID = UUID()) -> DashboardData {
        let transitionID = UUID()
        let mainID = UUID()
        let transitionDayID = UUID()
        let mainDayID = UUID()
        let now = Date().ISO8601Format()
        let today = Date().apexDateKey
        let priorDate = Calendar.current.date(byAdding: .day, value: -30, to: .now)?.apexDateKey ?? today
        let weekday = apexWeekday(.now)

        let profile = Profile(
            id: UUID(),
            userID: userID,
            persona: .constantine,
            displayName: "Constantine",
            sex: "male",
            weightKG: 70,
            bodyFatPercent: 18,
            heightCM: 178,
            birthdate: "1988-01-01",
            activityLevel: .moderate,
            goal: .recomp,
            targetKcal: nil,
            targetProteinG: nil,
            targetFatG: nil,
            targetCarbsG: nil,
            trainingTime: "19:00",
            baselineDate: today,
            profileNote: "Native UI validation profile",
            seedVersion: 1,
            calibrationK: 1,
            calibrationHistory: [],
            updatedAt: now,
            betaCodeRedeemed: true
        )
        let settings = UserSettings(
            userID: userID,
            voiceOn: true,
            ticksOn: true,
            notificationsOn: false,
            guardianFactor: 1.4,
            addons: [
                "uiMode": .string("advanced"),
                "time_zone": .string("Europe/Zurich"),
                "meal_dayline_density": .string("medium"),
                "food_memory_mode": .string("daily")
            ]
        )

        let meals = [
            Meal(id: UUID(), userID: userID, time: "07:00", name: "Breakfast", foods: "4 eggs + 60 g oats + 30 g nut mix", kcal: 610, proteinG: 42, fatG: 28, carbsG: 50, fullDaysOnly: false, sortOrder: 1),
            Meal(id: UUID(), userID: userID, time: "12:30", name: "Lunch", foods: "Chicken + 100 g dry bulgur + vegetables", kcal: 720, proteinG: 52, fatG: 19, carbsG: 82, fullDaysOnly: false, sortOrder: 2),
            Meal(id: UUID(), userID: userID, time: "18:30", name: "Dinner", foods: "Chicken + 450 g sweet potato + avocado", kcal: 690, proteinG: 43, fatG: 22, carbsG: 78, fullDaysOnly: false, sortOrder: 3),
            Meal(id: UUID(), userID: userID, time: "21:30", name: "Evening recovery", foods: "40 g casein shake", kcal: 180, proteinG: 32, fatG: 2, carbsG: 8, fullDaysOnly: false, sortOrder: 4),
        ]
        let supplements = [
            Supplement(id: UUID(), userID: userID, name: "Taurine", dose: "3 g", timing: "wake", clockTime: "06:30", offsetMinutes: nil, groupLabel: "Wake", trainingDaysOnly: false, sortOrder: 1),
            Supplement(id: UUID(), userID: userID, name: "Fish oil", dose: "2 capsules", timing: "breakfast", clockTime: "07:00", offsetMinutes: nil, groupLabel: "Breakfast", trainingDaysOnly: false, sortOrder: 2),
            Supplement(id: UUID(), userID: userID, name: "Citrulline malate", dose: "8 g", timing: "pre-workout", clockTime: nil, offsetMinutes: -30, groupLabel: "Pre-workout", trainingDaysOnly: true, sortOrder: 3),
            Supplement(id: UUID(), userID: userID, name: "Magnesium bisglycinate", dose: "300 mg", timing: "bed", clockTime: "22:30", offsetMinutes: nil, groupLabel: "Before sleep", trainingDaysOnly: false, sortOrder: 4),
        ]
        let programs = [
            Program(id: transitionID, userID: userID, slug: "transition", name: "Transition Phase", description: "Build movement quality and resilient consistency."),
            Program(id: mainID, userID: userID, slug: "main", name: "Main Phase", description: "Progress strength, power and athletic capacity."),
        ]
        let days = [
            ProgramDay(id: transitionDayID, userID: userID, programID: transitionID, weekday: weekday, name: "Full-body foundation", dayType: "upper", estimatedMinutes: 28, warmupNote: "Controlled movement quality", sortOrder: 1),
            ProgramDay(id: mainDayID, userID: userID, programID: mainID, weekday: weekday, name: "Upper strength", dayType: "push", estimatedMinutes: 42, warmupNote: "Shoulders, trunk and pressing pattern", sortOrder: 1),
        ]
        let exercises = [
            exercise(userID: userID, dayID: transitionDayID, name: "Push-ups", sets: 3, min: 8, max: 15, order: 1),
            exercise(userID: userID, dayID: transitionDayID, name: "Goblet squats", sets: 3, min: 8, max: 12, order: 2),
            exercise(userID: userID, dayID: transitionDayID, name: "Chest-supported rows", sets: 3, min: 8, max: 12, order: 3),
            exercise(userID: userID, dayID: mainDayID, name: "Dumbbell overhead press", sets: 4, min: 6, max: 10, order: 1),
            exercise(userID: userID, dayID: mainDayID, name: "Feet-elevated push-ups", sets: 3, min: 8, max: 12, order: 2),
            exercise(userID: userID, dayID: mainDayID, name: "Lateral raises", sets: 3, min: 15, max: 20, order: 3),
        ]
        let oatsID = UUID()
        let wheyID = UUID()
        let berriesID = UUID()
        let foods = [
            food(id: oatsID, name: "Swiss rolled oats", brand: "APEX Food Memory", kcal: 370, protein: 13, carbs: 60, fat: 7),
            food(
                id: wheyID, name: "High protein milk", brand: "APEX Food Memory",
                kcal: 54, protein: 8, carbs: 5.2, fat: 0.2,
                nutritionBasis: "per_100ml"
            ),
            food(id: berriesID, name: "Strawberries, fresh", brand: nil, kcal: 32, protein: 0.7, carbs: 7.7, fat: 0.3),
        ]
        let breakfastID = UUID()
        let loggedBreakfast = LoggedMeal(
            id: breakfastID, userID: userID, localDate: today, mealSlot: "breakfast",
            displayName: "Breakfast", sourcePresetID: nil, sourcePlannedMealID: meals[0].id,
            loggedAt: now, clientIdempotencyKey: "ui-breakfast", loggedAs: "actual",
            totalKcal: 330, totalProteinG: 23.8, totalCarbsG: 46.4, totalFatG: 4.6
        )
        let loggedEntries = [
            foodEntry(id: UUID(), mealID: breakfastID, userID: userID, food: foods[0], foodID: oatsID, order: 0, quantity: 60),
            foodEntry(
                id: UUID(), mealID: breakfastID, userID: userID, food: foods[1],
                foodID: wheyID, order: 1, quantity: 200, unit: "ml"
            ),
        ]
        let presetID = UUID()
        let breakfastPreset = MealPreset(
            id: presetID, userID: userID, name: "Fast protein breakfast", mealSlot: "breakfast",
            sourcePlannedMealID: meals[0].id, archived: false, version: 1
        )
        let presetItems = [
            MealPresetItem(
                id: UUID(), presetID: presetID, userID: userID, foodID: oatsID, sortOrder: 0,
                quantity: 60, unit: "g", optional: false, locked: false, adjustable: true,
                minimumAmount: 30, maximumAmount: 100, stepAmount: 5, adjustmentRole: "carb"
            ),
            MealPresetItem(
                id: UUID(), presetID: presetID, userID: userID, foodID: wheyID, sortOrder: 1,
                quantity: 200, unit: "ml", optional: false, locked: true, adjustable: false,
                minimumAmount: nil, maximumAmount: nil, stepAmount: nil, adjustmentRole: "protein"
            ),
        ]
        let activityTypes = [
            ActivityType(id: "massage", category: "Work: hands-on therapy", name: "Massage session given", icon: "hands.sparkles", met: 4, inputStyle: .count, defaultDurationMinutes: 60, isTrainingLinked: false, notes: "Count each session and choose its length.", distanceFactor: nil, supportsWatch: false),
            ActivityType(id: "gimbal", category: "Work: camera", name: "Handheld or gimbal filming", icon: "video", met: 3.2, inputStyle: .duration, defaultDurationMinutes: 120, isTrainingLinked: false, notes: "Moving camera work.", distanceFactor: nil, supportsWatch: false),
            ActivityType(id: "run", category: "Training", name: "Jog or run", icon: "figure.run", met: 0, inputStyle: .distance, defaultDurationMinutes: nil, isTrainingLinked: true, notes: "Uses one kcal per kg per kilometre.", distanceFactor: 1, supportsWatch: true),
            ActivityType(id: "steps", category: "Steps", name: "Steps not already covered by the blocks above", icon: "shoeprints.fill", met: 0, inputStyle: .steps, defaultDurationMinutes: nil, isTrainingLinked: false, notes: "Incidental steps only.", distanceFactor: nil, supportsWatch: false),
        ]
        let dailyLog = DailyLog(
            id: UUID(), userID: userID, date: today, kcal: 610, proteinG: 42, fatG: 28, carbsG: 50,
            waterL: 1.25, estimatedTDEE: 2_350, computedPAL: 1.58, activityMode: "quick", weightKG: 70
        )
        let snapshot = RPGSnapshot(
            id: UUID(), userID: userID, date: today, overall: 68, health: 75, joint: 61,
            flexibility: 58, endurance: 66, strength: 72, strengthUpper: 76, strengthLower: 68
        )
        let priorSnapshot = RPGSnapshot(
            id: UUID(), userID: userID, date: priorDate, overall: 62, health: 69, joint: 58,
            flexibility: 53, endurance: 60, strength: 66, strengthUpper: 70, strengthLower: 61
        )
        let workoutSession = WorkoutSession(
            id: UUID(), userID: userID, date: today, programDayID: transitionDayID,
            isLite: false, isDeload: false, isEventRecovery: false, completed: true,
            qualityScore: 0.9, startedAt: now, completedAt: now, notes: "UI validation session"
        )
        let workoutLogs = [
            WorkoutLog(
                id: UUID(), userID: userID, sessionID: workoutSession.id,
                exerciseID: exercises[1].id, exerciseName: exercises[1].name, setNumber: 1,
                weightKG: 18, reps: 12, rir: 2, skipped: false, overrideFlag: false, createdAt: now
            ),
            WorkoutLog(
                id: UUID(), userID: userID, sessionID: workoutSession.id,
                exerciseID: exercises[1].id, exerciseName: exercises[1].name, setNumber: 2,
                weightKG: 18, reps: 11, rir: 1, skipped: false, overrideFlag: false, createdAt: now
            ),
        ]
        let healthMetrics = [
            HealthMetric(id: UUID(), userID: userID, date: priorDate, weightKG: 70.6, vo2Max: 43.1, restingHeartRate: 59),
            HealthMetric(id: UUID(), userID: userID, date: today, weightKG: 70, vo2Max: 44.3, restingHeartRate: 56),
        ]
        let run = OrbitRunRecord(
            id: UUID(), userID: userID, clientIdempotencyKey: "ui-test-run", localDate: today,
            startedAt: now, endedAt: now, mission: "aerobic_base", routeID: nil,
            campaignSessionID: nil, shoeID: nil, samples: [], pauses: [], manualLapsM: [],
            metrics: ["distance_m": .number(5_120), "moving_s": .number(1_890), "avg_pace_sec_km": .number(369)],
            checkIn: ["perceived_effort": .number(4)], nutritionAdjustmentAppliedAt: nil,
            status: "completed", createdAt: now, updatedAt: now
        )

        return DashboardData(
            profile: profile,
            settings: settings,
            meals: meals,
            supplements: supplements,
            programs: programs,
            programDays: days,
            exercises: exercises,
            workoutSessions: [workoutSession],
            workoutLogs: workoutLogs,
            activityTypes: activityTypes,
            dailyLogs: [dailyLog],
            foods: foods,
            mealPresets: [breakfastPreset],
            mealPresetItems: presetItems,
            loggedMeals: [loggedBreakfast],
            loggedFoodEntries: loggedEntries,
            snapshots: [priorSnapshot, snapshot],
            healthMetrics: healthMetrics,
            orbitRuns: [run]
        )
    }

    private static func exercise(
        userID: UUID,
        dayID: UUID,
        name: String,
        sets: Int,
        min: Int,
        max: Int,
        order: Int
    ) -> Exercise {
        Exercise(
            id: UUID(), userID: userID, programDayID: dayID, name: name, sets: sets,
            repMin: min, repMax: max, repUnit: "reps", perSide: false, restSeconds: 90,
            tempoUp: 1, tempoDown: 2, tempoPause: 0, tempoNote: "controlled", notes: "",
            incrementKG: 1, isLite: false, optional: false, sortOrder: order
        )
    }

    private static func food(
        id: UUID,
        name: String,
        brand: String?,
        kcal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        nutritionBasis: String = "per_100g"
    ) -> Food {
        Food(
            id: id.uuidString, ownerUserID: nil, name: name, namesI18n: [:], brand: brand,
            barcode: nil, source: "ui_fixture", providerProductID: nil, externalImageURL: nil,
            packageQuantity: nil, nutritionBasis: nutritionBasis, preparationState: "as_sold",
            kcal100: kcal, protein100: protein, carbs100: carbs, fat100: fat,
            fibre100: nil, sugar100: nil, saturatedFat100: nil, salt100: nil,
            servingAmount: nil, servingUnit: nil, servingGramsOrML: nil,
            pieceGramsOrML: nil, confidence: "verified"
        )
    }

    private static func foodEntry(
        id: UUID,
        mealID: UUID,
        userID: UUID,
        food: Food,
        foodID: UUID,
        order: Int,
        quantity: Double,
        unit: String = "g"
    ) -> LoggedFoodEntry {
        let scale = quantity / 100
        return LoggedFoodEntry(
            id: id, mealID: mealID, userID: userID, foodID: foodID, sortOrder: order,
            snapshotName: food.name, snapshotBrand: food.brand,
            snapshotPreparationState: food.preparationState,
            snapshotNutritionBasis: food.nutritionBasis,
            snapshotKcal100: food.kcal100 ?? 0,
            snapshotProtein100: food.protein100 ?? 0,
            snapshotCarbs100: food.carbs100 ?? 0,
            snapshotFat100: food.fat100 ?? 0,
            quantity: quantity, unit: unit, equivalentAmount: quantity,
            kcal: (food.kcal100 ?? 0) * scale,
            proteinG: (food.protein100 ?? 0) * scale,
            carbsG: (food.carbs100 ?? 0) * scale,
            fatG: (food.fat100 ?? 0) * scale
        )
    }

    private static func apexWeekday(_ date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }
}
#endif
