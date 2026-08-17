import Foundation

struct OrbitCampaignAssessment: Hashable, Sendable {
    let outcome: String
    let reason: String
    let timelineWarning: String
    let credibleBase: Bool
    let daysUntilRace: Int
}

struct OrbitReadinessComponent: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let state: String
    let reason: String
}

enum OrbitCampaignEngine {
    static let planVersion = "orbit-campaign-1.0.0"
    static let phaseOrder = [
        "foundation", "aerobic_build", "durability", "marathon_specific",
        "peak", "taper", "race_week", "post_marathon"
    ]

    private static let frequency = ["none": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five_plus": 5]
    private static let weeklyKM = ["under_10": 7, "10_20": 15, "20_35": 27, "35_50": 42, "over_50": 55, "unsure": 0]
    private static let longestKM = ["under_5": 4, "5_10": 8, "10_15": 12, "15_21": 18, "over_21": 24, "unsure": 0]
    private static let consistencyMonths = ["none": 0.0, "under_month": 0.5, "one_three_months": 2, "three_six_months": 4.5, "over_six_months": 8]
    private static let availableDays = ["three": 3, "four": 4, "five": 5, "six": 6, "variable": 4]
    private static let demandingMissions = Set(["progression", "tempo", "threshold", "intervals", "hills", "marathon_pace", "performance_test", "long_run"])

    static let emptyAnswers: [String: JSONValue] = [
        "race_name": .string(""), "race_date": .string(""), "race_goal": .string(""),
        "target_time": .string(""), "course_profile": .string(""), "course_surface": .string(""),
        "climate_familiar": .string(""), "running_frequency": .string(""), "weekly_distance": .string(""),
        "longest_run": .string(""), "consistency": .string(""), "race_experience": .string(""),
        "marathon_experience": .string(""), "structured_plan": .string(""), "running_style": .string(""),
        "available_days": .string(""), "long_run_day": .string(""), "unavailable_days": .array([]),
        "strength_days_per_week": .number(0), "constraints": .array([]), "previous_issue": .string(""),
        "previous_surgery": .string(""), "issue_status": .string(""), "pain_changes_movement": .bool(false),
        "chest_discomfort": .bool(false), "fainting": .bool(false), "unusual_breathlessness": .bool(false),
        "recent_illness_or_operation": .bool(false), "professional_restriction": .bool(false),
        "medication": .string("")
    ]

    static func isComplete(_ answers: [String: JSONValue]) -> Bool {
        let required = [
            "race_name", "race_date", "race_goal", "course_profile", "course_surface", "climate_familiar",
            "running_frequency", "weekly_distance", "longest_run", "consistency", "race_experience",
            "marathon_experience", "structured_plan", "running_style", "available_days", "long_run_day",
            "previous_issue", "previous_surgery", "issue_status", "medication"
        ]
        return required.allSatisfy { string($0, answers).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }

    static func assess(_ answers: [String: JSONValue], today: Date = .now) -> OrbitCampaignAssessment {
        guard isComplete(answers) else {
            return .init(
                outcome: "more_information",
                reason: "Complete the remaining induction questions before Orbit assigns a campaign.",
                timelineWarning: "",
                credibleBase: false,
                daysUntilRace: 0
            )
        }
        let issueStatus = string("issue_status", answers)
        let concerning = bool("pain_changes_movement", answers)
            || bool("chest_discomfort", answers)
            || bool("fainting", answers)
            || bool("unusual_breathlessness", answers)
            || bool("recent_illness_or_operation", answers)
            || bool("professional_restriction", answers)
            || ["changes_movement", "rehabilitating", "restricted"].contains(issueStatus)
            || string("previous_surgery", answers) == "under_six_months"

        let raceDate = date(string("race_date", answers)) ?? today
        let daysUntilRace = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: today),
            to: Calendar.current.startOfDay(for: raceDate)
        ).day ?? 0
        let runningFrequency = frequency[string("running_frequency", answers)] ?? 0
        let distance = weeklyKM[string("weekly_distance", answers)] ?? 0
        let longest = longestKM[string("longest_run", answers)] ?? 0
        let consistency = consistencyMonths[string("consistency", answers)] ?? 0
        let credible = runningFrequency >= 3 && distance >= 20 && longest >= 10 && consistency >= 3

        if concerning {
            return .init(
                outcome: "professional_review",
                reason: "A current symptom, unresolved limitation, recent operation or existing restriction was reported. General Orbit remains available, but strenuous marathon preparation is paused pending professional review.",
                timelineWarning: "",
                credibleBase: credible,
                daysUntilRace: daysUntilRace
            )
        }
        if daysUntilRace < 0 {
            return .init(
                outcome: "more_information",
                reason: "The selected race date has already passed. Choose a future event.",
                timelineWarning: "",
                credibleBase: credible,
                daysUntilRace: daysUntilRace
            )
        }
        if credible && daysUntilRace < 84 {
            return .init(
                outcome: "more_information",
                reason: "There are \(daysUntilRace) days until the race, which is shorter than Orbit’s 12-week marathon-specific block. Choose a later event or change the objective rather than compressing the progression.",
                timelineWarning: "The selected timeline is too short for the standard marathon-specific block.",
                credibleBase: true,
                daysUntilRace: daysUntilRace
            )
        }
        if credible == false {
            let foundationWeeks = runningFrequency <= 1 || distance < 10 ? 16 : consistency < 1 ? 8 : 4
            let requiredDays = (foundationWeeks + 12) * 7
            let warning = daysUntilRace < requiredDays
                ? "The race is \(daysUntilRace) days away, but a credible Foundation plus marathon-specific journey needs approximately \(requiredDays) days. A later race is recommended."
                : ""
            return .init(
                outcome: "foundation",
                reason: "Foundation to First Marathon was selected because the recent base is below the marathon-specific gate: \(runningFrequency) run days per week, approximately \(distance) km per week and a longest recent run near \(longest) km.",
                timelineWarning: warning,
                credibleBase: false,
                daysUntilRace: daysUntilRace
            )
        }
        return .init(
            outcome: "ready",
            reason: "Recent frequency, volume, long-run exposure and consistency support entry into a marathon-specific campaign.",
            timelineWarning: "",
            credibleBase: true,
            daysUntilRace: daysUntilRace
        )
    }

    static func createCampaign(
        induction: OrbitInduction,
        programDays: [ProgramDay],
        events: [EventRecord],
        today: Date = .now
    ) -> (campaign: OrbitCampaign, sessions: [OrbitCampaignSession]) {
        let assessment = assess(induction.answers, today: today)
        let family = campaignFamily(answers: induction.answers, outcome: assessment.outcome)
        let now = Date().ISO8601Format()
        let campaignID = stableUUID(
            userID: induction.userID,
            key: "campaign:\(induction.id.uuidString.lowercased()):\(planVersion)"
        )
        let raceDate = string("race_date", induction.answers)
        var campaign = OrbitCampaign(
            id: campaignID,
            userID: induction.userID,
            clientIdempotencyKey: "campaign:\(induction.id.uuidString.lowercased()):\(planVersion)",
            inductionID: induction.id,
            family: family,
            phase: phase(on: today, raceDate: raceDate, outcome: assessment.outcome),
            outcome: assessment.outcome,
            status: assessment.outcome == "professional_review" ? "review_required" : assessment.outcome == "more_information" ? "paused" : "active",
            raceName: string("race_name", induction.answers),
            raceDate: raceDate,
            raceGoal: string("race_goal", induction.answers),
            startedAt: now,
            planVersion: planVersion,
            assignmentReason: assessment.reason,
            timelineWarning: assessment.timelineWarning,
            readiness: [],
            adaptations: [],
            createdAt: now,
            updatedAt: now
        )
        let legWeekdays = programDays
            .filter { ["legs_a", "legs_b"].contains($0.dayType) }
            .map { $0.weekday == 7 ? 0 : $0.weekday }
        var sessions = generateSessions(
            campaign: campaign,
            answers: induction.answers,
            legWeekdays: legWeekdays,
            today: today
        )
        let coordinated = coordinateEvents(
            campaign: campaign,
            sessions: sessions,
            events: events,
            legWeekdays: legWeekdays
        )
        campaign = coordinated.campaign
        sessions = coordinated.sessions
        return (campaign, sessions)
    }

    static func generateSessions(
        campaign: OrbitCampaign,
        answers: [String: JSONValue],
        legWeekdays: [Int],
        today: Date = .now
    ) -> [OrbitCampaignSession] {
        guard campaign.outcome != "professional_review", campaign.outcome != "more_information",
              let raceDate = date(campaign.raceDate)
        else { return [] }

        let startMonday = monday(onOrBefore: today)
        let end = Calendar.current.date(byAdding: .day, value: 14, to: raceDate) ?? raceDate
        let totalDays = max(1, Calendar.current.dateComponents([.day], from: startMonday, to: end).day ?? 1)
        let totalWeeks = min(52, max(1, Int(ceil(Double(totalDays) / 7))))
        let runDays = chooseRunDays(answers: answers, legWeekdays: legWeekdays)
        let preferredLong = longRunWeekday(answers)
        let longDay = runDays.contains(preferredLong) ? preferredLong : (runDays.last ?? 0)
        let runWalk = ["run_walk"].contains(string("running_style", answers))
            || ["none", "one"].contains(string("running_frequency", answers))
        var result: [OrbitCampaignSession] = []

        for week in 0..<totalWeeks {
            guard let weekStart = Calendar.current.date(byAdding: .day, value: week * 7, to: startMonday) else { continue }
            let phase = phase(on: weekStart, raceDate: campaign.raceDate, outcome: campaign.outcome)
            if phase == "post_marathon" {
                if let date = dateForWeekday(weekStart, weekday: 3) {
                    let duration = week == totalWeeks - 1 ? 30 : 20
                    result.append(session(campaign: campaign, date: date, phase: phase, prescription: prescription("recovery", duration, phase, campaign.family)))
                }
                continue
            }
            if phase == "race_week" {
                for day in runDays.prefix(2) {
                    guard let runDate = dateForWeekday(weekStart, weekday: day), runDate < raceDate else { continue }
                    result.append(session(campaign: campaign, date: runDate, phase: phase, prescription: prescription("easy", 22, phase, campaign.family)))
                }
                if Calendar.current.isDate(raceDate, equalTo: weekStart, toGranularity: .weekOfYear) {
                    result.append(session(campaign: campaign, date: raceDate, phase: phase, prescription: prescription("performance_test", 270, phase, campaign.family)))
                }
                continue
            }

            let quality = qualityMission(phase: phase, week: week, runWalk: runWalk)
            let longMinutes = longRunMinutes(answers: answers, phase: phase, week: week)
            let qualityCandidates = runDays.filter { day in
                day != longDay
                    && legWeekdays.contains(day) == false
                    && legWeekdays.contains(where: { circularDistance(day, $0) == 1 }) == false
            }
            let qualityDay = qualityCandidates.first(where: { circularDistance($0, longDay) >= 2 })
                ?? runDays.first(where: { $0 != longDay })
                ?? longDay

            for day in runDays {
                guard let runDate = dateForWeekday(weekStart, weekday: day), runDate <= raceDate else { continue }
                let mission = day == longDay ? "long_run" : day == qualityDay ? quality : phase == "foundation" ? "run_walk" : "easy"
                let duration: Int
                if mission == "long_run" { duration = longMinutes }
                else if mission == "easy" { duration = min(55, 30 + week * 2) }
                else if mission == "run_walk" { duration = min(45, 25 + week * 2) }
                else if phase == "taper" { duration = 35 }
                else { duration = min(65, 42 + week / 2 * 3) }
                result.append(
                    session(
                        campaign: campaign,
                        date: runDate,
                        phase: phase,
                        prescription: prescription(mission, duration, phase, campaign.family, isLong: mission == "long_run")
                    )
                )
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    static func adaptAfterMissed(
        campaign: OrbitCampaign,
        sessions: [OrbitCampaignSession],
        missedID: UUID
    ) -> (campaign: OrbitCampaign, sessions: [OrbitCampaignSession]) {
        guard let missed = sessions.first(where: { $0.id == missedID }) else { return (campaign, sessions) }
        let now = Date().ISO8601Format()
        var next = sessions
        if let index = next.firstIndex(where: { $0.id == missedID }) {
            next[index].status = "missed"
            next[index].updatedAt = now
        }
        guard missed.adapted["demanding"]?.boolValue == true,
              let hardIndex = next.firstIndex(where: {
                  $0.date > missed.date && $0.status == "planned" && $0.adapted["demanding"]?.boolValue == true
              })
        else { return (campaign, next) }

        let reason = "A missed demanding session is not stacked into the next days. The original prescription remains visible and the week continues forward."
        let originalMission = next[hardIndex].original["mission"]?.stringValue ?? "easy"
        next[hardIndex].adapted = easierPrescription(next[hardIndex].original, reason: reason)
        next[hardIndex].adaptationReason = reason
        next[hardIndex].updatedAt = now
        var updatedCampaign = campaign
        updatedCampaign.adaptations.append(.object([
            "id": .string(stableUUID(userID: campaign.userID, key: "missed:\(missed.id):\(next[hardIndex].id)").uuidString.lowercased()),
            "at": .string(now),
            "session_id": .string(next[hardIndex].id.uuidString.lowercased()),
            "reason": .string(reason),
            "original_mission": .string(originalMission),
            "adapted_mission": next[hardIndex].adapted["mission"] ?? .string("recovery"),
            "accepted": .null
        ]))
        updatedCampaign.updatedAt = now
        return (updatedCampaign, next)
    }

    static func adaptAfterRun(
        campaign: OrbitCampaign,
        sessions: [OrbitCampaignSession],
        run: OrbitRunRecord
    ) -> (campaign: OrbitCampaign, sessions: [OrbitCampaignSession]) {
        let effort = Int(run.checkIn["perceived_effort"]?.numberValue ?? 0)
        let legs = run.checkIn["legs"]?.stringValue
        let discomfort = run.checkIn["discomfort"]?.stringValue
        let unexpectedlyHard = effort >= 8 || legs == "very_heavy" || discomfort == "changed_movement"
        guard unexpectedlyHard,
              let hardIndex = sessions.firstIndex(where: {
                  $0.date > run.localDate && $0.status == "planned" && $0.adapted["demanding"]?.boolValue == true
              })
        else { return (campaign, sessions) }

        let reason = "The previous run was harder than intended, so the next demanding session is reduced instead of stacking fatigue."
        var next = sessions
        let originalMission = next[hardIndex].original["mission"]?.stringValue ?? "easy"
        next[hardIndex].adapted = easierPrescription(next[hardIndex].original, reason: reason)
        next[hardIndex].adaptationReason = reason
        next[hardIndex].updatedAt = Date().ISO8601Format()
        var updatedCampaign = campaign
        updatedCampaign.adaptations.append(.object([
            "id": .string(stableUUID(userID: campaign.userID, key: "adaptation:\(run.id):\(next[hardIndex].id)").uuidString.lowercased()),
            "at": .string(Date().ISO8601Format()),
            "session_id": .string(next[hardIndex].id.uuidString.lowercased()),
            "reason": .string(reason),
            "original_mission": .string(originalMission),
            "adapted_mission": next[hardIndex].adapted["mission"] ?? .string("recovery"),
            "accepted": .null
        ]))
        updatedCampaign.updatedAt = Date().ISO8601Format()
        return (updatedCampaign, next)
    }

    static func readiness(
        runs: [OrbitRunRecord],
        sessions: [OrbitCampaignSession],
        campaign: OrbitCampaign
    ) -> [OrbitReadinessComponent] {
        let completed = sessions.filter { $0.status == "completed" }
        let threshold = Calendar.current.date(byAdding: .day, value: -42, to: .now)?.apexDateKey ?? ""
        let recent = runs.filter { $0.localDate >= threshold }
        let longRuns = recent.filter { $0.mission == "long_run" }
        let controlled = recent.filter { ($0.checkIn["perceived_effort"]?.numberValue ?? 10) <= 6 }
        let fueling = longRuns.filter { ($0.checkIn["note"]?.stringValue ?? "").localizedCaseInsensitiveContains("fuel") }
        var result = [
            OrbitReadinessComponent(
                id: "consistency", label: "Consistency",
                state: completed.count >= 10 ? "strong" : completed.count >= 5 ? "on_track" : "developing",
                reason: "\(completed.count) campaign sessions are recorded as completed."
            ),
            OrbitReadinessComponent(
                id: "long_run", label: "Long-run progression",
                state: longRuns.count >= 4 ? "on_track" : longRuns.count >= 2 ? "developing" : "needs_attention",
                reason: "\(longRuns.count) recent long runs are available for comparison."
            ),
            OrbitReadinessComponent(
                id: "aerobic_control", label: "Aerobic control",
                state: controlled.count >= max(3, Int(Double(recent.count) * 0.7)) ? "strong" : controlled.count >= 2 ? "moderate" : "developing",
                reason: "\(controlled.count) recent runs were completed at controlled perceived effort."
            ),
            OrbitReadinessComponent(
                id: "fueling", label: "Fueling practice",
                state: fueling.count >= 3 ? "on_track" : fueling.isEmpty ? "needs_attention" : "developing",
                reason: fueling.isEmpty ? "No completed fueling rehearsal is recorded yet." : "\(fueling.count) long-run notes mention fueling practice."
            ),
            OrbitReadinessComponent(
                id: "strength", label: "Strength coordination",
                state: campaign.family == "hybrid" ? "on_track" : "moderate",
                reason: campaign.family == "hybrid" ? "The campaign is scheduled around the existing APEX strength week." : "Strength work remains visible when Orbit adapts the run week."
            )
        ]
        if ["race_week", "taper"].contains(campaign.phase) {
            result.append(.init(
                id: "race_week", label: "Race-week preparation",
                state: campaign.phase == "race_week" ? "on_track" : "developing",
                reason: "Taper, pacing, fueling and equipment checks are active."
            ))
        }
        return result
    }

    static func campaignFamilyLabel(_ family: String) -> String {
        switch family {
        case "foundation_first": "Foundation to First Marathon"
        case "first_finish": "First Marathon: Finish Strong"
        case "first_performance": "First Marathon: Performance"
        case "personal_best": "Marathon Personal Best"
        case "hybrid": "Hybrid Athlete Marathon"
        default: family.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func phaseLabel(_ phase: String) -> String {
        phase.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func campaignFamily(answers: [String: JSONValue], outcome: String) -> String {
        if outcome == "foundation" { return "foundation_first" }
        if Int(answers["strength_days_per_week"]?.numberValue ?? 0) >= 2 { return "hybrid" }
        if ["two_four", "five_plus"].contains(string("marathon_experience", answers)) { return "personal_best" }
        let performanceGoal = ["target_time", "best_realistic"].contains(string("race_goal", answers))
        let performanceHistory = ["half", "marathon", "multiple_marathons"].contains(string("race_experience", answers))
        return performanceGoal && performanceHistory ? "first_performance" : "first_finish"
    }

    private static func phase(on date: Date, raceDate: String, outcome: String) -> String {
        guard let race = self.date(raceDate) else { return "foundation" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: race)).day ?? 0
        if days < 0 { return "post_marathon" }
        if days <= 6 { return "race_week" }
        if days <= 20 { return "taper" }
        if days <= 27 { return "peak" }
        if days <= 48 { return "marathon_specific" }
        if days <= 69 { return "durability" }
        if days <= 83 { return "aerobic_build" }
        return outcome == "foundation" ? "foundation" : "aerobic_build"
    }

    private static func chooseRunDays(answers: [String: JSONValue], legWeekdays: [Int]) -> [Int] {
        let count = min(6, max(3, availableDays[string("available_days", answers)] ?? 3))
        let blocked = Set((answers["unavailable_days"]?.arrayValue ?? []).compactMap { value -> Int? in
            if let number = value.numberValue { return Int(number) }
            if let string = value.stringValue { return Int(string) }
            return nil
        })
        let preferred = longRunWeekday(answers)
        let long = blocked.contains(preferred) ? ([0, 6, 5].first { blocked.contains($0) == false } ?? 0) : preferred
        var selected = [long]
        while selected.count < count {
            var candidates = Array(0...6).filter { blocked.contains($0) == false && selected.contains($0) == false }
            guard candidates.isEmpty == false else { break }
            candidates.sort { first, second in
                let spacingA = selected.map { circularDistance(first, $0) }.min() ?? 0
                let spacingB = selected.map { circularDistance(second, $0) }.min() ?? 0
                let penaltyA = legWeekdays.contains(first) ? 2 : legWeekdays.contains(where: { circularDistance(first, $0) == 1 }) ? 1 : 0
                let penaltyB = legWeekdays.contains(second) ? 2 : legWeekdays.contains(where: { circularDistance(second, $0) == 1 }) ? 1 : 0
                return spacingA - penaltyA > spacingB - penaltyB
            }
            selected.append(candidates[0])
        }
        return selected.sorted()
    }

    private static func qualityMission(phase: String, week: Int, runWalk: Bool) -> String {
        if runWalk || phase == "foundation" { return "run_walk" }
        if phase == "aerobic_build" { return week.isMultiple(of: 2) ? "hills" : "aerobic_base" }
        if phase == "durability" { return week.isMultiple(of: 2) ? "progression" : "tempo" }
        if phase == "marathon_specific" { return week.isMultiple(of: 2) ? "marathon_pace" : "threshold" }
        if ["peak", "taper"].contains(phase) { return "marathon_pace" }
        return "easy"
    }

    private static func prescription(
        _ mission: String,
        _ duration: Int,
        _ phase: String,
        _ family: String,
        isLong: Bool = false
    ) -> [String: JSONValue] {
        let titles = [
            "recovery": "Recovery reset", "easy": "Easy aerobic run", "aerobic_base": "Aerobic base",
            "long_run": "Long-run durability", "run_walk": "Run-walk foundation", "progression": "Controlled progression",
            "tempo": "Tempo control", "threshold": "Threshold development", "intervals": "Controlled intervals",
            "hills": "Hill strength", "marathon_pace": "Marathon-pace durability", "exploration": "Exploration run",
            "performance_test": "Target marathon", "free_run": "Free run"
        ]
        let demanding = demandingMissions.contains(mission) && mission != "long_run" || isLong && duration >= 90
        let easy = ["recovery", "easy", "aerobic_base", "long_run", "run_walk"].contains(mission)
        let purpose: String
        switch mission {
        case "long_run": purpose = "Build durable time on feet and practise controlled fueling without racing the session."
        case "marathon_pace": purpose = "Develop pace control and durability at the effort required by the target event."
        case "hills": purpose = "Build controlled climbing strength while protecting running form."
        case "run_walk": purpose = "Develop repeatable running frequency with planned walking before fatigue changes movement."
        default: purpose = easy ? "Build aerobic volume without compromising the surrounding strength and recovery work." : "Apply one purposeful quality stimulus while keeping the rest of the week controlled."
        }
        let mainWork: String
        switch mission {
        case "run_walk": mainWork = "Alternate 4 minutes of relaxed running with 1 minute of purposeful walking."
        case "marathon_pace": mainWork = "\(max(12, Int((Double(duration) * 0.45).rounded()))) minutes at controlled marathon effort inside the session."
        case "tempo": mainWork = "\(max(10, Int((Double(duration) * 0.35).rounded()))) minutes at comfortably hard, controlled effort."
        case "threshold": mainWork = "3 controlled blocks of \(max(5, Int((Double(duration) * 0.12).rounded()))) minutes with easy recovery."
        case "hills": mainWork = "Use 6 to 8 controlled climbs with complete easy recoveries."
        case "performance_test": mainWork = "Execute the rehearsed pacing and fueling strategy. Use effort as the fallback when conditions differ."
        default: mainWork = "Stay conversational and finish with the sense that more was available."
        }
        let route = mission == "hills"
            ? "A repeatable climb with a simple recovery descent."
            : ["tempo", "threshold", "marathon_pace"].contains(mission)
                ? "Long uninterrupted sections with low navigation complexity."
                : "Prefer a simple, mostly flat route when recovery is the priority."
        let fueling = duration >= 90
            ? "Use this as a fueling rehearsal with a familiar carbohydrate source and the exact plan already tested in training."
            : duration >= 60
                ? "Begin normally fueled and carry water when conditions or personal experience justify it."
                : "Your normal meal pattern is sufficient unless hunger or timing says otherwise."
        return [
            "mission": .string(mission), "title": .string(titles[mission] ?? mission.capitalized),
            "purpose": .string(purpose), "duration_min": .number(Double(duration)),
            "distance_km": mission == "performance_test" ? .number(42.195) : .null,
            "intensity": .string(easy ? "Conversational effort, RPE 2 to 4" : "Controlled quality, never an all-out opening"),
            "warmup": .string(demanding ? "10 minutes easy plus dynamic movement and 3 short relaxed strides." : "Begin with 5 minutes very easy and let rhythm arrive naturally."),
            "main_work": .string(mainWork),
            "cooldown": .string(demanding ? "8 to 10 minutes easy, then stop. Do not add bonus work." : "Finish with 3 to 5 easy minutes."),
            "route_characteristics": .string(route),
            "minimum_version_min": mission == "performance_test" ? .null : .number(Double(max(18, Int((Double(duration) * 0.65).rounded())))),
            "fueling_note": .string(fueling),
            "why": .string("\(phase.replacingOccurrences(of: "_", with: " ")) phase · \(family.replacingOccurrences(of: "_", with: " ")) campaign · placed to preserve recovery around demanding work."),
            "demanding": .bool(demanding)
        ]
    }

    private static func easierPrescription(_ original: [String: JSONValue], reason: String) -> [String: JSONValue] {
        var result = original
        let originalMission = original["mission"]?.stringValue ?? "easy"
        let mission = originalMission == "long_run" ? "easy" : "recovery"
        let duration = max(20, Int((original["duration_min"]?.numberValue ?? 30) * 0.65))
        result["mission"] = .string(mission)
        result["title"] = .string(mission == "easy" ? "Easy aerobic run" : "Recovery reset")
        result["purpose"] = .string("Absorb the previous workload while preserving movement rhythm.")
        result["duration_min"] = .number(Double(duration))
        result["intensity"] = .string("Conversational effort, RPE 2 to 3")
        result["main_work"] = .string("Keep the entire run easy. Do not replace the removed quality block.")
        result["minimum_version_min"] = .number(18)
        result["why"] = .string(reason)
        result["demanding"] = .bool(false)
        return result
    }

    private static func session(
        campaign: OrbitCampaign,
        date: Date,
        phase: String,
        prescription: [String: JSONValue]
    ) -> OrbitCampaignSession {
        let day = date.apexDateKey
        let mission = prescription["mission"]?.stringValue ?? "easy"
        let id = stableUUID(userID: campaign.userID, key: "campaign-session:\(campaign.id):\(day):\(mission)")
        let now = Date().ISO8601Format()
        return OrbitCampaignSession(
            id: id, userID: campaign.userID, campaignID: campaign.id,
            date: day, prescribedDate: day, phase: phase,
            original: prescription, adapted: prescription,
            status: "planned", completionRunID: nil, adaptationReason: "", userOverride: false,
            createdAt: now, updatedAt: now
        )
    }

    private static func coordinateEvents(
        campaign: OrbitCampaign,
        sessions: [OrbitCampaignSession],
        events: [EventRecord],
        legWeekdays: [Int]
    ) -> (campaign: OrbitCampaign, sessions: [OrbitCampaignSession]) {
        let relevant = events.filter {
            $0.userID == campaign.userID && ["filming_championship", "travel"].contains($0.type)
        }
        guard relevant.isEmpty == false else { return (campaign, sessions) }
        var occupied = Set(sessions.map(\.date))
        var adaptations = campaign.adaptations
        var result = sessions
        for index in result.indices {
            let current = result[index]
            guard current.status == "planned", current.adapted["demanding"]?.boolValue == true,
                  let event = relevant.first(where: { current.date >= $0.startDate && current.date <= $0.endDate }),
                  let originalDate = date(current.date)
            else { continue }
            var moved: Date?
            for offset in 1...3 {
                guard let candidate = Calendar.current.date(byAdding: .day, value: offset, to: originalDate) else { continue }
                let candidateKey = candidate.apexDateKey
                let weekday = (Calendar.current.component(.weekday, from: candidate) + 6) % 7
                let eventConflict = relevant.contains { candidateKey >= $0.startDate && candidateKey <= $0.endDate }
                if eventConflict == false, occupied.contains(candidateKey) == false, legWeekdays.contains(weekday) == false {
                    moved = candidate
                    break
                }
            }
            guard let moved else { continue }
            let movedKey = moved.apexDateKey
            occupied.remove(current.date)
            occupied.insert(movedKey)
            let title = current.adapted["title"]?.stringValue ?? "Session"
            let reason = "\(title) moved from \(current.date) to \(movedKey) because \(event.name) occupies the original date. The original prescription remains visible."
            result[index].date = movedKey
            result[index].adaptationReason = reason
            result[index].updatedAt = Date().ISO8601Format()
            adaptations.append(.object([
                "id": .string(stableUUID(userID: campaign.userID, key: "calendar:\(current.id):\(event.id)").uuidString.lowercased()),
                "at": .string(Date().ISO8601Format()),
                "session_id": .string(current.id.uuidString.lowercased()),
                "reason": .string(reason),
                "original_mission": current.original["mission"] ?? .string("easy"),
                "adapted_mission": current.adapted["mission"] ?? .string("easy"),
                "accepted": .null
            ]))
        }
        var updated = campaign
        updated.adaptations = adaptations
        updated.updatedAt = Date().ISO8601Format()
        return (updated, result.sorted { $0.date < $1.date })
    }

    private static func longRunMinutes(answers: [String: JSONValue], phase: String, week: Int) -> Int {
        let longest = longestKM[string("longest_run", answers)] ?? 0
        let base = max(35, min(130, Int((Double(longest) * 6.3).rounded())))
        if phase == "race_week" { return 20 }
        if phase == "taper" { return max(50, Int((Double(base) * 0.65).rounded())) }
        if phase == "peak" { return min(190, max(120, base + week * 5)) }
        let conservative = ["none", "under_month"].contains(string("consistency", answers))
        var duration = Double(base) * pow(conservative ? 1.05 : 1.08, Double(min(week, 14)))
        if (week + 1).isMultiple(of: 4) { duration *= 0.82 }
        if phase == "foundation" { duration = min(duration, 105) }
        return min(190, Int((duration / 5).rounded()) * 5)
    }

    private static func longRunWeekday(_ answers: [String: JSONValue]) -> Int {
        string("long_run_day", answers) == "saturday" ? 6 : 0
    }

    private static func circularDistance(_ first: Int, _ second: Int) -> Int {
        let distance = abs(first - second)
        return min(distance, 7 - distance)
    }

    private static func monday(onOrBefore date: Date) -> Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let distance = weekday == 1 ? -6 : 2 - weekday
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: distance, to: date) ?? date)
    }

    private static func dateForWeekday(_ monday: Date, weekday: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: weekday == 0 ? 6 : weekday - 1, to: monday)
    }

    private static func string(_ key: String, _ answers: [String: JSONValue]) -> String {
        answers[key]?.stringValue ?? ""
    }

    private static func bool(_ key: String, _ answers: [String: JSONValue]) -> Bool {
        answers[key]?.boolValue ?? false
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter.apexDateOnly.date(from: value)
    }

    private static func stableUUID(userID: UUID, key: String) -> UUID {
        let input = "apex-orbit:\(userID.uuidString.lowercased()):\(key)"
        let seeds: [UInt32] = [0x811c9dc5, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35]
        let raw = seeds.map { seed -> String in
            var hash = seed
            for codeUnit in input.utf16 {
                hash ^= UInt32(codeUnit)
                hash = hash &* 16_777_619
            }
            hash ^= hash >> 16
            hash = hash &* 0x7feb352d
            hash ^= hash >> 15
            return String(format: "%08x", hash)
        }.joined()
        var characters = Array(raw)
        characters[12] = "4"
        let variantValue = (Int(String(characters[16]), radix: 16) ?? 0) & 0x3 | 0x8
        characters[16] = Character(String(variantValue, radix: 16))
        let value = String(characters)
        let formatted = "\(value.prefix(8))-\(value.dropFirst(8).prefix(4))-\(value.dropFirst(12).prefix(4))-\(value.dropFirst(16).prefix(4))-\(value.dropFirst(20).prefix(12))"
        return UUID(uuidString: formatted) ?? UUID()
    }
}
