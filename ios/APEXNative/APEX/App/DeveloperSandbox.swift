import Foundation

enum DeveloperSandboxRole: String, CaseIterable, Identifiable, Sendable {
    case individual, coach, invitedClient
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .individual: "Individual subscriber"
        case .coach: "Coach"
        case .invitedClient: "Invited client"
        }
    }
}

/// Each session receives an entirely new sample identity graph.
@MainActor
final class DeveloperSandboxSamples {
    let relationshipID = UUID()
    let planID = UUID()
    let sessionID = UUID()
    let exerciseID = UUID()
    let clientID = UUID()
    var savedPlan: CoachCurrentPlan?

    static func dashboard(ownerID: UUID, name: String) -> DashboardData {
        var data = DashboardData.empty
        data.profile = Profile(
            id: UUID(), userID: ownerID, persona: .constantine,
            profileKind: .standard, bespokeProtocolID: nil, displayName: LanguageState.shared.text(name),
            sex: "female", weightKG: 65, bodyFatPercent: nil,
            heightCM: 168, birthdate: "1990-01-01", activityLevel: .moderate,
            goal: .maintain, targetKcal: nil, targetProteinG: nil,
            targetFatG: nil, targetCarbsG: nil, trainingTime: "18:00",
            baselineDate: Date().apexDateKey, profileNote: "", seedVersion: 0,
            calibrationK: 1, calibrationHistory: [], updatedAt: Date().ISO8601Format()
        )
        data.settings = UserSettings(
            userID: ownerID, voiceOn: false, ticksOn: false, notificationsOn: false,
            guardianFactor: 1, addons: ["uiMode": .string("simple")]
        )
        data.foods = catalogue
        return data
    }

    func coachWorkspaceContext() -> CoachAccountContext {
        CoachAccountContext(
            coach: CoachProfileSummary(
                status: .development,
                displayName: LanguageState.shared.text("Sample coach"),
                seatLimit: 10,
                activeSeats: 1
            ),
            sponsorship: nil,
            currentPlan: nil,
            capabilities: CoachAccountCapabilities(coachWorkspace: true, sponsoredClient: false)
        )
    }

    func coachPlanContext() -> CoachAccountContext {
        let relationshipID = self.relationshipID
        let checklist = CoachPlanChecklist(
            nutrition: true,
            workouts: true,
            supplements: true,
            hydration: true,
            schedule: true,
            reviewDate: true
        )
        let draft = CoachPlanDraft(
            title: LanguageState.shared.text("Foundation strength"),
            objective: LanguageState.shared.text("Build rhythm, strength and confidence."),
            coachNote: LanguageState.shared.text("Keep two good repetitions in reserve."),
            reviewDate: "2026-09-15",
            checklist: checklist,
            sessions: [
                CoachSessionTemplate(
                    id: self.sessionID,
                    weekday: 2,
                    name: LanguageState.shared.text("Full body foundation"),
                    sessionMode: .guided,
                    estimatedMinutes: 45,
                    warmupNote: LanguageState.shared.text("Move smoothly and stay pain-free."),
                    exercises: [
                        CoachExerciseTemplate(
                            id: self.exerciseID,
                            movementID: "bodyweight-squat",
                            name: "Bodyweight Squat",
                            sets: 3,
                            targetMin: 8,
                            targetMax: 10,
                            unit: "reps",
                            perSide: false,
                            restSeconds: 75,
                            tempoUpSeconds: 1,
                            tempoDownSeconds: 2,
                            tempoPauseSeconds: 0,
                            notes: LanguageState.shared.text("Stop if form changes."),
                            optional: false,
                            groupID: nil,
                            groupPosition: nil
                        )
                    ]
                )
            ]
        )
        return CoachAccountContext(
            coach: nil,
            sponsorship: CoachSponsorshipSummary(
                relationshipID: relationshipID,
                coachDisplayName: LanguageState.shared.text("Sample coach"),
                relationshipStatus: .active,
                seatState: .active,
                offeredScopes: [.nutrition, .workouts, .activity, .hydration, .supplements, .avatar, .measurements, .recovery],
                consentedScopes: [.nutrition, .workouts, .activity, .hydration, .supplements, .avatar, .measurements, .recovery],
                graceEndsAt: nil
            ),
            currentPlan: savedPlan ?? CoachCurrentPlan(
                id: self.planID,
                relationshipID: relationshipID,
                version: 2,
                status: .published,
                title: draft.title,
                objective: draft.objective,
                coachNote: draft.coachNote,
                reviewDate: draft.reviewDate,
                checklist: checklist,
                plan: draft,
                publishedAt: "2026-09-01T08:00:00Z",
                acknowledgedAt: nil,
                activatedAt: nil
            ),
            capabilities: CoachAccountCapabilities(coachWorkspace: false, sponsoredClient: true)
        )
    }

    func coachRoster() -> [CoachRosterEntry] {
        [
            CoachRosterEntry(
                id: self.relationshipID,
                clientUserID: self.clientID,
                displayName: "June",
                relationshipStatus: .active,
                seatState: .active,
                consentedScopes: [.nutrition, .workouts, .activity, .hydration, .supplements, .avatar, .measurements, .recovery],
                planVersion: savedPlan?.version ?? 2,
                planTitle: savedPlan?.title ?? LanguageState.shared.text("Foundation strength"),
                reviewDate: "2026-09-15",
                publishedAt: "2026-09-01T08:00:00Z",
                acknowledgedAt: nil,
                activatedAt: nil,
                attention: [.reviewDue, .awaitingAcknowledgement]
            )
        ]
    }

    func coachClientOverview() -> CoachClientOverview? {
        let relationshipID = self.relationshipID
        return CoachClientOverview(
            relationshipID: relationshipID,
            clientUserID: self.clientID,
            displayName: "June",
            relationshipStatus: .active,
            seatState: .active,
            consentedScopes: [.nutrition, .workouts, .activity, .hydration, .supplements, .avatar, .measurements, .recovery],
            measurements: CoachClientMeasurements(
                sex: "female",
                heightCM: 165,
                weightKG: 61.5,
                bodyFatPercent: 24,
                birthdate: "1983-06-15"
            ),
            avatar: nil,
            workouts: CoachClientWorkoutSummary(completed30Days: 12, lastCompletedAt: "2026-08-31T18:30:00Z"),
            nutrition: CoachClientNutritionSummary(daysObserved: 7, averageKcal: 2085),
            hydration: CoachClientHydrationSummary(daysObserved: 7, averageLitres: 2.34),
            visualProgressShared: false,
            currentPlan: coachPlanContext().currentPlan
        )
    }


    nonisolated static let catalogue: [Food] = [
        food(id: UUID(), name: "Oats", brand: nil, kcal: 370, protein: 13, carbs: 60, fat: 7),
        food(id: UUID(), name: "Milk", brand: nil, kcal: 64, protein: 3.4, carbs: 4.8, fat: 3.6),
        food(id: UUID(), name: "Banana", brand: nil, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3),
        food(id: UUID(), name: "Rice", brand: nil, kcal: 130, protein: 2.7, carbs: 28, fat: 0.3)
    ]

    nonisolated private static func food(
        id: UUID,
        name: String,
        brand: String?,
        kcal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fibre: Double? = nil,
        sugar: Double? = nil,
        saturatedFat: Double? = nil,
        nutritionBasis: String = "per_100g",
        source: String = "sample",
        providerProductID: String? = nil
    ) -> Food {
        Food(
            id: id.uuidString, ownerUserID: nil, name: name, namesI18n: [:], brand: brand,
            barcode: nil, source: source, providerProductID: providerProductID, externalImageURL: nil,
            packageQuantity: nil, nutritionBasis: nutritionBasis, preparationState: "as_sold",
            kcal100: kcal, protein100: protein, carbs100: carbs, fat100: fat,
            fibre100: fibre, sugar100: sugar, saturatedFat100: saturatedFat, salt100: nil,
            servingAmount: nil, servingUnit: nil, servingGramsOrML: nil,
            pieceGramsOrML: nil, confidence: "verified"
        )
    }

    func save(plan: CoachPlanDraft, relationshipID: UUID, expectedVersion: Int, publish: Bool) throws -> CoachPlanVersionReceipt {
        guard relationshipID == self.relationshipID,
              expectedVersion == (savedPlan?.version ?? 2),
              CoachPlanValidator.validate(plan, publishing: publish).issues.isEmpty else {
            throw CancellationError()
        }
        let next = CoachCurrentPlan(id: UUID(), relationshipID: relationshipID,
            version: expectedVersion + 1, status: publish ? .published : .draft,
            title: plan.title, objective: plan.objective, coachNote: plan.coachNote,
            reviewDate: plan.reviewDate, checklist: plan.checklist, plan: plan,
            publishedAt: publish ? Date().ISO8601Format() : nil,
            acknowledgedAt: nil, activatedAt: nil)
        savedPlan = next
        return CoachPlanVersionReceipt(id: next.id, relationshipID: relationshipID, version: next.version, status: next.status)
    }
}
