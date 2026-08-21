import Charts
import SwiftUI

struct AvatarView: View {
    @State private var engineExpanded = false
    @State private var showEvolutionInfo = false
    @Environment(AppSession.self) private var session
    @State private var animate = false
    @State private var language = LanguageState.shared
    @State private var trendDays = 30
    @State private var jointArms = 3.0
    @State private var jointCore = 3.0
    @State private var jointLegs = 3.0
    @State private var jointSaved = false

    private var snapshots: [RPGSnapshot] {
        session.data.snapshots.sorted { $0.date < $1.date }
    }

    private var snapshot: RPGSnapshot? { snapshots.last }

    private var comparisonSnapshot: RPGSnapshot? {
        guard let latest = snapshot,
              let latestDate = ISO8601DateFormatter.apexDateOnly.date(from: latest.date),
              let cutoff = Calendar.current.date(byAdding: .day, value: -trendDays, to: latestDate) else { return snapshots.dropLast().last }
        return snapshots.last(where: {
            guard let date = ISO8601DateFormatter.apexDateOnly.date(from: $0.date) else { return false }
            return date <= cutoff
        }) ?? snapshots.first
    }

    private var stats: [AvatarStat] {
        let current = snapshot
        let previous = comparisonSnapshot
        return [
            .init(key: "overall", name: "Overall Fitness Level", value: current?.overall ?? 1, previous: previous?.overall, color: APEXColor.green, icon: "sparkles"),
            .init(key: "health", name: "Health", value: current?.health ?? 1, previous: previous?.health, color: APEXColor.amber, icon: "heart.fill"),
            .init(key: "joint", name: "Joint Health Balance", value: current?.joint ?? 1, previous: previous?.joint, color: APEXColor.cyan, icon: "figure.flexibility"),
            .init(key: "flexibility", name: "Body Flexibility", value: current?.flexibility ?? 1, previous: previous?.flexibility, color: APEXColor.teal, icon: "figure.cooldown"),
            .init(key: "endurance", name: "Endurance & VO₂ max", value: current?.endurance ?? 1, previous: previous?.endurance, color: APEXColor.violet, icon: "lungs.fill"),
            .init(key: "upper", name: "Upper Body Strength", value: current?.strengthUpper ?? 1, previous: previous?.strengthUpper, color: APEXColor.amberDeep, icon: "figure.strengthtraining.traditional"),
            .init(key: "lower", name: "Lower Body Strength", value: current?.strengthLower ?? 1, previous: previous?.strengthLower, color: APEXColor.amberDeep, icon: "figure.stairs"),
        ]
    }

    private var bodySignals: [AvatarStat] { Array(stats.dropFirst()) }
    private var strongest: AvatarStat? { bodySignals.max(by: { $0.value < $1.value }) }
    private var weakest: AvatarStat? { bodySignals.min(by: { $0.value < $1.value }) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                APEXTopBar(profile: session.profile) { session.navigationPath.append(.settings) }
                pageHeader
                /* Ordered by how often it is looked at, not by when it was
                   built. Who you are, then the index, then the shape of the
                   index, then the numbers behind it. The long prose blocks sit
                   below the things people open this page for. */
                AvatarHero(profile: session.profile)
                bodyIndexCard
                radarCard
                statsCard
                needsCard
                StrengthHistoryCard(sessions: session.data.workoutSessions, logs: session.data.workoutLogs, days: trendDays)
                jointCheckCard
                assessmentCard
                visualProgressLink
                engineCard
                healthEvidenceCard
                metabolicRhythmCard
                evolutionCard
            }
            .padding(18)
            .padding(.bottom, 34)
.dockClearance()
        }
        .navigationTitle(session.profile?.displayName ?? language.text("Avatar"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadJointCheck()
            withAnimation(.easeOut(duration: 0.9).delay(0.12)) { animate = true }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text("Avatar")).font(APEXFont.display(38))
            Text(language.text("Your body, as a living stat sheet"))
                .font(APEXFont.body(15, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
            Capsule().fill(APEXColor.green.gradient).frame(width: 64, height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visualProgressLink: some View {
        NavigationLink(value: PortalDestination.visualProgress) {
            HStack(spacing: 15) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 25, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("Private Visual Progress")).font(APEXFont.display(20))
                    Text(language.text("Before, after and the stats behind the change"))
                        .font(APEXFont.body(12, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(APEXColor.ink).padding(17)
            .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 29, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).stroke(.white.opacity(0.9)))
        }
        .buttonStyle(.plain)
    }

    private var bodyIndexCard: some View {
        let overall = snapshot?.overall ?? 1
        let best = snapshots.map(\.overall).max() ?? overall
        let nextUnlock = max(5, ceil((overall + 0.01) / 5) * 5)
        let delta = comparisonSnapshot.map { overall - $0.overall }
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(language.text("APEX BODY INDEX")).font(APEXFont.mono(10)).tracking(2.6)
                Spacer()
                Text(language.text("LIVE PROFILE")).font(APEXFont.mono(9)).tracking(1.5)
                    .padding(.horizontal, 12).padding(.vertical, 8).overlay(Capsule().stroke(APEXColor.green.opacity(0.55)))
            }
            HStack(alignment: .center, spacing: 18) {
                Text("\(Int(overall.rounded()))").font(APEXFont.mono(66, weight: .bold))
                VStack(alignment: .leading, spacing: 5) {
                    Text(language.text(bodyIndexTitle(overall))).font(APEXFont.display(23)).lineLimit(2)
                    Text(language.format("Your strongest signal is %@ at %d.", language.text(strongest?.name ?? "Building evidence"), Int((strongest?.value ?? 0).rounded())))
                        .font(APEXFont.body(11, weight: .medium)).foregroundStyle(.white.opacity(0.63))
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(language.text("PROGRESS TO NEXT UNLOCK")).font(APEXFont.mono(9)).tracking(1.5)
                    Spacer(); Text("\(Int(nextUnlock))").font(APEXFont.mono(10))
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.11))
                        Capsule().fill(LinearGradient(colors: [APEXColor.teal, APEXColor.cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * min(1, max(0.025, overall / nextUnlock)))
                    }
                }.frame(height: 8)
            }
            Divider().overlay(.white.opacity(0.14))
            HStack(spacing: 8) {
                darkMetric("\(trendDays)-DAY CHANGE", delta.map(signed) ?? "—", delta.map { $0 >= 0 ? APEXColor.green : APEXColor.amber } ?? .white)
                darkMetric("PERSONAL BEST", "\(Int(best.rounded()))", APEXColor.amber)
                darkMetric("NEXT UNLOCK", "\(Int(nextUnlock))", APEXColor.green)
            }
        }
        .foregroundStyle(.white).padding(22)
        .background(
            LinearGradient(colors: [Color(red: 0.015, green: 0.085, blue: 0.075), Color(red: 0.015, green: 0.035, blue: 0.055)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 34, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(APEXColor.green.opacity(0.3)))
        .shadow(color: APEXColor.teal.opacity(0.18), radius: 28, y: 14)
    }

    private var radarCard: some View {
        GlassCard(radius: 34, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(language.text("Your performance body")).font(APEXFont.display(25))
                Text(language.text("Six visible signals. No hidden mystery score."))
                    .font(APEXFont.body(12, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                AvatarRadarChart(stats: bodySignals).frame(height: 330).padding(.vertical, 4)
            }
        }
    }

    /* Closed by default. It is a page of prose about rules that fired, which
       is worth reading occasionally and worth nobody scrolling past every day. */
    private var engineCard: some View {
        GlassCard(radius: 32, padding: engineExpanded ? 20 : 15) {
            VStack(alignment: .leading, spacing: engineExpanded ? 15 : 0) {
                Button {
                    withAnimation(.snappy(duration: 0.26)) { engineExpanded.toggle() }
                } label: {
                    HStack {
                        Text(language.text("The engine"))
                            .font(APEXFont.display(engineExpanded ? 26 : 19))
                            .foregroundStyle(APEXColor.ink)
                        Spacer(minLength: 8)
                        if !engineExpanded, !engineFacts.isEmpty {
                            Text("\(engineFacts.count)")
                                .font(APEXFont.mono(10, weight: .bold))
                                .foregroundStyle(APEXColor.green)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(APEXColor.green.opacity(0.12), in: Capsule())
                        }
                        Image(systemName: engineExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if engineExpanded {
                    Text(language.text("NUTRITION × TRAINING × RECOVERY"))
                        .font(APEXFont.mono(8)).tracking(1).foregroundStyle(APEXColor.green)
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .overlay(Capsule().stroke(APEXColor.green.opacity(0.3)))
                    if engineFacts.isEmpty {
                        evidenceRow("Complete meals, training or daily logs to start the evidence feed.", date: nil, color: APEXColor.secondaryInk)
                    } else {
                        ForEach(engineFacts) { fact in evidenceRow(fact.text, date: fact.date, color: fact.color) }
                    }
                }
            }
        }
    }

    private var metabolicRhythmCard: some View {
        let rhythm = MetabolicRhythm(data: session.data, days: trendDays)
        return VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(language.text("EATING PATTERN")).font(APEXFont.mono(9)).tracking(2)
                    /* "Metabolic rhythm" under "avatar input signal" told
                       nobody what this measures. It measures how regularly you
                       eat, so it says that. */
                    Text(language.text("How regularly you eat")).font(APEXFont.display(26))
                }
                Spacer(); periodPicker(dark: true)
            }
            Text(language.text("Based on how many days you logged meals and how close to the same times. It is about the pattern of your eating, not what was in the food."))
                .font(APEXFont.body(12, weight: .medium)).foregroundStyle(.white.opacity(0.66)).lineSpacing(4)
            if let score = rhythm.score {
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.1), lineWidth: 15)
                        Circle().trim(from: 0, to: score / 100).stroke(APEXColor.green.gradient, style: StrokeStyle(lineWidth: 15, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text("\(Int(score.rounded()))").font(APEXFont.mono(34, weight: .bold))
                            Text(language.text("OUT OF 100")).font(APEXFont.mono(7)).tracking(1)
                        }
                    }.frame(width: 142, height: 142)
                    VStack(alignment: .leading, spacing: 9) {
                        darkDataRow("Recorded meals", "\(rhythm.mealCount)")
                        darkDataRow("Days with meal evidence", "\(rhythm.daysWithMeals)")
                        darkDataRow("Typical timing variation", rhythm.timingVariation.map { "\(Int($0.rounded())) min" } ?? "—")
                    }
                }
                Text(language.text("Logging on more days raises it. Eating at wildly different times lowers it. Change your timezone in Settings if the hours look wrong."))
                    .font(APEXFont.body(10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            } else {
                Label(language.text("Log three meals and this starts working."), systemImage: "waveform.path.ecg")
                    .font(APEXFont.body(13, weight: .semibold)).foregroundStyle(.white.opacity(0.72)).padding(.vertical, 22)
            }
        }
        .foregroundStyle(.white).padding(22)
        .background(LinearGradient(colors: [Color(red: 0.015, green: 0.08, blue: 0.075), Color(red: 0.025, green: 0.03, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var healthEvidenceCard: some View {
        let metrics = recentHealthMetrics
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("SOURCE-AWARE AVATAR SIGNAL")).font(APEXFont.mono(9)).tracking(1.7).foregroundStyle(APEXColor.cyan)
                    Text(language.text("Cardio & recovery evidence")).font(APEXFont.display(26)).foregroundStyle(.white)
                }
                Spacer(); Image(systemName: "heart.text.square.fill").font(.system(size: 27)).foregroundStyle(APEXColor.cyan)
            }
            if metrics.isEmpty {
                Text(language.text("No supported Health data is available yet. Connect Apple Health in Settings to add VO₂ max and resting-heart-rate evidence. APEX will not invent missing recovery values."))
                    .font(APEXFont.body(13, weight: .medium)).foregroundStyle(.white.opacity(0.62)).lineSpacing(4)
                Button(language.text("Open Settings")) { session.navigationPath.append(.settings) }
                    .buttonStyle(.borderedProminent).tint(APEXColor.violet)
            } else {
                Chart(metrics) { item in
                    if let resting = item.restingHeartRate {
                        LineMark(x: .value("Date", item.date), y: .value("Resting heart rate", resting)).foregroundStyle(APEXColor.cyan).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", item.date), y: .value("Resting heart rate", resting)).foregroundStyle(APEXColor.cyan)
                    }
                }
                .chartXAxis(.hidden).chartYAxis { AxisMarks(position: .leading) }.foregroundStyle(.white.opacity(0.55)).frame(height: 150)
                HStack(spacing: 8) {
                    if let latest = metrics.last?.restingHeartRate { darkPill(language.format("Resting HR %.0f bpm", latest), APEXColor.cyan) }
                    if let latest = metrics.last?.vo2Max { darkPill(language.format("VO₂ max %.1f", latest), APEXColor.violet) }
                }
                Text(language.text("Values retain their original Health source. Missing days do not count as decline."))
                    .font(APEXFont.body(10, weight: .medium)).foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(22)
        .background(LinearGradient(colors: [Color(red: 0.025, green: 0.035, blue: 0.12), Color(red: 0.06, green: 0.04, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var needsCard: some View {
        GlassCard(radius: 32, padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                Text(language.text("What your body needs")).font(APEXFont.display(27))
                ForEach(Array(bodySignals.sorted(by: { $0.value < $1.value }).prefix(2))) { stat in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(language.text(stat.name.uppercased())).font(APEXFont.mono(9)).tracking(1.2).foregroundStyle(APEXColor.green)
                            Spacer()
                            Button(language.text("Plan it")) { navigate(for: stat) }.buttonStyle(.borderedProminent).tint(APEXColor.green)
                        }
                        Text(needHeadline(for: stat)).font(APEXFont.display(20))
                        Text(language.text(needExplanation(for: stat)))
                            .font(APEXFont.body(13, weight: .medium)).foregroundStyle(APEXColor.secondaryInk).lineSpacing(3)
                    }
                    .padding(16).background(stat.color.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(stat.color.opacity(0.16)))
                }
            }
        }
    }

    private var statsCard: some View {
        GlassCard(radius: 32, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text(language.text("Stats")).font(APEXFont.display(27)); Spacer(); periodPicker(dark: false) }
                ForEach(stats) { stat in AvatarStatRow(stat: stat, animate: animate) }
                if let upper = stats.first(where: { $0.key == "upper" }), let lower = stats.first(where: { $0.key == "lower" }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(language.text("Upper Body Strength")).font(APEXFont.mono(9)); Spacer(); Text("\(Int(upper.value.rounded()))").font(APEXFont.mono(10))
                            Text(language.text("Lower Body Strength")).font(APEXFont.mono(9)); Spacer(); Text("\(Int(lower.value.rounded()))").font(APEXFont.mono(10))
                        }
                        Text(language.text("These are separate signals so progress and imbalances remain immediately understandable."))
                            .font(APEXFont.body(10, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                    }
                }
            }
        }
    }

    private var assessmentCard: some View {
        GlassCard(radius: 32, padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                Text(language.text("APEX ASSESSMENT")).font(APEXFont.mono(10)).tracking(2).foregroundStyle(APEXColor.secondaryInk)
                Text(language.text(assessmentHeadline)).font(APEXFont.display(25))
                Text(assessment).font(APEXFont.body(14, weight: .medium)).foregroundStyle(APEXColor.secondaryInk).lineSpacing(4)
                assessmentBlock("WHAT IS WORKING", lines: workingLines, tint: APEXColor.green)
                assessmentBlock("HIGHEST-RETURN IMPROVEMENTS", lines: improvementLines, tint: APEXColor.amber)
                Text(language.text("Performance guidance generated from your APEX logs and trends. It is not a medical diagnosis."))
                    .font(APEXFont.body(10, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
            }
        }
    }

    private var jointCheckCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("WEEKLY LOAD-TOLERANCE CHECK")).font(APEXFont.mono(9)).tracking(1.7).foregroundStyle(APEXColor.cyan)
                    Text(language.text("How are your joints this week?")).font(APEXFont.display(25)).foregroundStyle(.white)
                }
                Spacer()
                Text(language.text(jointSaved ? "Saved" : "Due now")).font(APEXFont.mono(8)).foregroundStyle(APEXColor.ink)
                    .padding(.horizontal, 11).padding(.vertical, 8).background(APEXColor.amber, in: Capsule())
            }
            Text(language.text("Rate fatigue or discomfort, not normal muscle soreness. This is training guidance, not a diagnosis."))
                .font(APEXFont.body(12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            jointSlider("Arms", subtitle: "shoulders · elbows · wrists", value: $jointArms)
            jointSlider("Core", subtitle: "lower/middle back · hips", value: $jointCore)
            jointSlider("Legs", subtitle: "knees · ankles · feet", value: $jointLegs)
            Button(language.text("Save weekly check-in")) { saveJointCheck() }.buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.teal))
        }
        .padding(22).background(Color(red: 0.015, green: 0.035, blue: 0.08), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    @ViewBuilder private var evolutionCard: some View {
        if snapshots.count > 1 {
            GlassCard(radius: 32, padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    /* Retitled. It charts the overall index over time, and the
                       old heading never said so, which made a real feature read
                       as decoration. */
                    HStack(spacing: 8) {
                        Text(language.text("Your index over time")).font(APEXFont.display(25))
                        Button { showEvolutionInfo.toggle() } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(language.text("What this chart shows"))
                    }
                    if showEvolutionInfo {
                        Text(language.text("One point for every day APEX recorded a full picture of you. The line is your overall index, the same number shown at the top of this page, so you can see whether it is moving and not only where it stands today."))
                            .font(APEXFont.body(12))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Chart(Array(snapshots.suffix(trendDays))) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Overall", point.overall)).foregroundStyle(APEXColor.violet.gradient).interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Date", point.date), y: .value("Overall", point.overall)).foregroundStyle(APEXColor.violet.opacity(0.1).gradient)
                    }.chartYAxis(.hidden).frame(height: 155)
                }
            }
        }
    }

    /* The real receipts: rules that actually fired inside FitnessBrainEngine,
       with the same labels the web app shows. Falls back to plain activity
       summaries only when no rule has fired yet. */
    private var engineFacts: [AvatarEvidence] {
        let synergy = session.brainSynergies
            .sorted { $0.date > $1.date }
            .prefix(8)
            .enumerated()
            .map { index, event in
                AvatarEvidence(
                    id: "synergy-\(event.date)-\(event.kind.rawValue)-\(index)",
                    text: language.text(event.label),
                    date: event.date,
                    color: synergyColor(event.kind))
            }
        if !synergy.isEmpty { return Array(synergy) }
        return activitySummaryFacts
    }

    private func synergyColor(_ kind: FBSynergyKind) -> Color {
        switch kind {
        case .proteinStrength, .deficitStrength, .mealRhythm: return APEXColor.amber
        case .hydrationEndurance, .importFeed: return APEXColor.cyan
        case .mobilityAfterLegs, .deloadHonored: return APEXColor.teal
        case .recoverySignal: return APEXColor.green
        case .vo2Anchor: return APEXColor.violet
        }
    }

    private var activitySummaryFacts: [AvatarEvidence] {
        let recentDates = Set((0..<min(trendDays, 14)).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now)?.apexDateKey })
        var facts: [AvatarEvidence] = []
        for date in recentDates.sorted(by: >) {
            let meals = session.data.loggedMeals.filter { $0.localDate == date }
            let planned = session.data.mealLogs.filter { $0.date == date }
            let workout = session.data.workoutSessions.first { $0.date == date && $0.completed }
            let daily = session.data.dailyLogs.first { $0.date == date }
            if let workout {
                let setCount = session.data.workoutLogs.filter { $0.sessionID == workout.id && !$0.skipped }.count
                facts.append(.init(id: "workout-\(workout.id)", text: language.format("Training completed with %d recorded sets.", setCount), date: date, color: APEXColor.teal))
            }
            if !meals.isEmpty {
                let kcal = meals.reduce(0) { $0 + $1.totalKcal }
                facts.append(.init(id: "meal-\(date)", text: language.format("%d structured meals recorded · %.0f kcal.", meals.count, kcal), date: date, color: APEXColor.amber))
            } else if planned.isEmpty, daily != nil {
                facts.append(.init(id: "missing-\(date)", text: language.text("The day closed with no configured meal recorded. This can still be corrected from the calendar."), date: date, color: APEXColor.amber))
            }
            if let water = daily?.waterL, water > 0 {
                facts.append(.init(id: "water-\(date)", text: language.format("Hydration recorded at %.1f L.", water), date: date, color: APEXColor.cyan))
            }
            if facts.count >= 7 { break }
        }
        return Array(facts.prefix(7))
    }

    private var recentHealthMetrics: [HealthMetric] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -trendDays, to: .now) ?? .distantPast
        return session.data.healthMetrics.filter {
            guard let date = ISO8601DateFormatter.apexDateOnly.date(from: $0.date) else { return false }
            return date >= cutoff && ($0.restingHeartRate != nil || $0.vo2Max != nil)
        }.sorted { $0.date < $1.date }
    }

    private var assessmentHeadline: String {
        let overall = snapshot?.overall ?? 1
        if overall < 45 { return "Foundation phase. Make the basics repeatable" }
        if overall < 65 { return "Building phase. Turn good days into a system" }
        if overall < 80 { return "Performance phase. Refine the limiting signal" }
        return "High-performance phase. Protect consistency and durability"
    }

    private var assessment: String {
        guard let weakest, let strongest else { return language.text("Complete your first logs to give the Avatar reliable signals.") }
        let delta = stats.first?.delta
        var text = language.format("%@ currently leads at %d. %@ is the clearest limiter at %d.", language.text(strongest.name), Int(strongest.value.rounded()), language.text(weakest.name), Int(weakest.value.rounded()))
        if let delta { text += " " + language.format("Your Overall score changed %@ points across the selected comparison window.", signed(delta)) }
        text += " " + language.text("APEX will protect the strongest signal while directing the smallest useful dose toward the limiter.")
        return text
    }

    private var workingLines: [String] {
        var lines: [String] = []
        if let strongest { lines.append(language.format("%@ is your strongest current signal at %d.", language.text(strongest.name), Int(strongest.value.rounded()))) }
        let completed = session.data.workoutSessions.filter { $0.completed && isWithinDays($0.date, days: 14) }.count
        lines.append(language.format("%d planned sessions completed in the last 14 days.", completed))
        if let upper = snapshot?.strengthUpper, let lower = snapshot?.strengthLower {
            let leading = upper >= lower ? "Upper-body strength" : "Lower-body strength"
            lines.append(language.format("%@ has retained the stronger base at %d.", language.text(leading), Int(max(upper, lower).rounded())))
        }
        return lines
    }

    private var improvementLines: [String] {
        var lines: [String] = []
        if let weakest { lines.append(language.format("Give %@ two focused exposures this week, separated by enough recovery.", language.text(weakest.name))) }
        if let upper = snapshot?.strengthUpper, let lower = snapshot?.strengthLower, abs(upper - lower) >= 8 {
            let lagging = upper < lower ? "upper-body" : "lower-body"
            lines.append(language.format("Close the strength gap by protecting both weekly %@ exposures.", language.text(lagging)))
        }
        let loggedDays = Set(session.data.loggedMeals.filter { isWithinDays($0.localDate, days: 7) }.map(\.localDate)).count
        lines.append(language.format("Log at least five of the next seven days. You currently have meal evidence on %d.", loggedDays))
        return lines
    }

    private func bodyIndexTitle(_ score: Double) -> String {
        if score < 45 { return "Foundation under construction" }
        if score < 65 { return "Repeatable performance base" }
        if score < 80 { return "Performance system online" }
        return "High-performance system"
    }

    private func needHeadline(for stat: AvatarStat) -> String {
        language.format("%@ is your current opportunity (%d)", language.text(stat.name), Int(stat.value.rounded()))
    }

    private func needExplanation(for stat: AvatarStat) -> String {
        switch stat.key {
        case "health": return "Hydration, calories near target, protein and sleep evidence feed this signal. Log the day consistently before changing the plan."
        case "joint": return "Use the weekly load-tolerance check and keep demanding sessions pain-free. APEX uses the trend for load guidance, not diagnosis."
        case "flexibility": return "Two short mobility exposures this week are a higher-return choice than one exhausting stretch session."
        case "endurance": return "Add one controlled aerobic session that preserves the surrounding strength and recovery work."
        case "upper": return "Keep two clean upper-body exposures and progress only after the top of the rep range is repeatable."
        default: return "Protect both weekly lower-body exposures while keeping fatigue controlled and technique honest."
        }
    }

    private func navigate(for stat: AvatarStat) {
        if stat.key == "health" { session.navigationPath.append(.nutrition) }
        else if stat.key == "endurance" { session.navigationPath.append(.orbit) }
        else { session.navigationPath.append(.transition) }
    }

    private func isWithinDays(_ dateKey: String, days: Int) -> Bool {
        guard let date = ISO8601DateFormatter.apexDateOnly.date(from: dateKey),
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return false }
        return date >= cutoff
    }

    private func periodPicker(dark: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach([30, 90], id: \.self) { days in
                Button { trendDays = days } label: {
                    Text("\(days)D").font(APEXFont.mono(9))
                        .foregroundStyle(trendDays == days ? (dark ? APEXColor.ink : .white) : (dark ? .white.opacity(0.48) : APEXColor.secondaryInk))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(trendDays == days ? APEXColor.green : .clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }.padding(3).background(dark ? .white.opacity(0.08) : APEXColor.ink.opacity(0.05), in: Capsule())
    }

    private func darkMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text(title)).font(APEXFont.mono(7)).tracking(1).foregroundStyle(.white.opacity(0.45))
            Text(value).font(APEXFont.mono(16)).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func darkDataRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(language.text(title)).font(APEXFont.body(10, weight: .medium)).foregroundStyle(.white.opacity(0.46))
            Text(value).font(APEXFont.mono(15))
        }
    }

    private func darkPill(_ text: String, _ color: Color) -> some View {
        Text(text).font(APEXFont.body(10, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 8).background(color.opacity(0.18), in: Capsule())
    }

    private func evidenceRow(_ text: String, date: String?, color: Color) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Circle().fill(color.gradient).frame(width: 10, height: 10).padding(.top, 5)
            Text(text).font(APEXFont.body(13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            if let date { Text(shortDate(date)).font(APEXFont.mono(9)).foregroundStyle(APEXColor.secondaryInk) }
        }.padding(13).background(.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func assessmentBlock(_ title: String, lines: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.text(title)).font(APEXFont.mono(9)).tracking(1.3).foregroundStyle(tint)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 8) {
                    Text(title == "WHAT IS WORKING" ? "✓" : "\(index + 1).")
                    Text(line).frame(maxWidth: .infinity, alignment: .leading)
                }.font(APEXFont.body(12, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
            }
        }.padding(16).background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func jointSlider(_ title: String, subtitle: String, value: Binding<Double>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(language.text(title)).font(APEXFont.display(17)).foregroundStyle(.white)
                Text(language.text(subtitle)).font(APEXFont.body(9, weight: .medium)).foregroundStyle(.white.opacity(0.43))
                Slider(value: value, in: 0...10, step: 1).tint(APEXColor.cyan)
            }
            Text("\(Int(value.wrappedValue))").font(APEXFont.mono(18)).foregroundStyle(APEXColor.ink)
                .frame(width: 53, height: 53).background(APEXColor.green, in: Circle())
        }.padding(14).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func loadJointCheck() {
        guard let object = session.data.settings?.addons["avatar_joint_check"]?.objectValue else { return }
        jointArms = object["arms"]?.numberValue ?? 3
        jointCore = object["core"]?.numberValue ?? 3
        jointLegs = object["legs"]?.numberValue ?? 3
        jointSaved = object["date"]?.stringValue == Date().apexDateKey
    }

    private func saveJointCheck() {
        Task {
            await session.updateSettings {
                $0.addons["avatar_joint_check"] = .object([
                    "date": .string(Date().apexDateKey), "arms": .number(jointArms),
                    "core": .number(jointCore), "legs": .number(jointLegs),
                ])
            }
            jointSaved = true
        }
    }

    private func shortDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter.apexDateOnly.date(from: value) else { return value }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func signed(_ value: Double) -> String { String(format: "%@%.1f", value >= 0 ? "+" : "", value) }
}

private struct AvatarStat: Identifiable {
    let key: String
    let name: String
    let value: Double
    let previous: Double?
    let color: Color
    let icon: String
    var id: String { key }
    var delta: Double? { previous.map { value - $0 } }
}

private struct AvatarEvidence: Identifiable {
    let id: String
    let text: String
    let date: String?
    let color: Color
}

private struct MetabolicRhythm {
    let mealCount: Int
    let daysWithMeals: Int
    let timingVariation: Double?
    let score: Double?

    init(data: DashboardData, days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let configuredTimeZone = data.settings?.addons["time_zone"]?.stringValue.flatMap(TimeZone.init(identifier:)) ?? .current
        var calendar = Calendar.current
        calendar.timeZone = configuredTimeZone
        let meals = data.loggedMeals.filter {
            guard let date = ISO8601DateFormatter.apexDateOnly.date(from: $0.localDate) else { return false }
            return date >= cutoff
        }
        mealCount = meals.count
        daysWithMeals = Set(meals.map(\.localDate)).count
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamped = meals.compactMap { meal -> (String, Double)? in
            guard let date = fractional.date(from: meal.loggedAt) ?? ISO8601DateFormatter().date(from: meal.loggedAt) else { return nil }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (meal.mealSlot.lowercased(), Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
        }
        let grouped = Dictionary(grouping: timestamped, by: \.0).values.map { $0.map(\.1) }.filter { $0.count >= 2 }
        let deviations = grouped.flatMap { values -> [Double] in
            let angles = values.map { 2 * Double.pi * $0 / 1_440 }
            let meanAngle = atan2(angles.map(sin).reduce(0, +), angles.map(cos).reduce(0, +))
            let meanMinute = ((meanAngle < 0 ? meanAngle + 2 * Double.pi : meanAngle) / (2 * Double.pi)) * 1_440
            return values.map { minute in
                let direct = abs(minute - meanMinute)
                return min(direct, 1_440 - direct)
            }
        }
        if mealCount >= 3, !deviations.isEmpty {
            timingVariation = deviations.reduce(0, +) / Double(deviations.count)
            let coverage = min(1, Double(daysWithMeals) / Double(min(days, 14)))
            let consistency = max(0, 1 - (timingVariation ?? 180) / 240)
            score = min(100, max(0, coverage * 70 + consistency * 30))
        } else {
            timingVariation = nil
            score = nil
        }
    }
}

private struct AvatarStatRow: View {
    @State private var language = LanguageState.shared
    let stat: AvatarStat
    let animate: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(language.text(stat.name), systemImage: stat.icon).font(APEXFont.body(13, weight: .bold))
                Spacer()
                Text("\(Int(stat.value.rounded()))").font(APEXFont.mono(13)).foregroundStyle(stat.color)
                if let delta = stat.delta {
                    Text(String(format: "%@ %.1f", delta >= 0 ? "▲" : "▼", abs(delta)))
                        .font(APEXFont.mono(9)).foregroundStyle(delta >= 0 ? APEXColor.green : APEXColor.danger)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(APEXColor.ink.opacity(0.07))
                    Capsule().fill(stat.color.gradient)
                        .frame(width: animate ? proxy.size.width * min(max(stat.value / 100, 0.025), 1) : 0)
                        .shadow(color: stat.color.opacity(0.3), radius: 8)
                }
            }.frame(height: 10)
        }
    }
}

private struct AvatarRadarChart: View {
    @State private var language = LanguageState.shared
    let stats: [AvatarStat]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) * 0.68
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size / 2
            Canvas { context, _ in
                guard stats.count > 2 else { return }
                for ring in 1...4 {
                    let scale = CGFloat(ring) / 4
                    var path = Path()
                    for index in stats.indices {
                        let point = radarPoint(index: index, count: stats.count, radius: radius * scale, center: center)
                        index == stats.startIndex ? path.move(to: point) : path.addLine(to: point)
                    }
                    path.closeSubpath()
                    /* Grid in ink rather than pale cyan. A cyan line at 15% on
                       a near-white card is invisible, which left the shape
                       floating with nothing to measure it against. The outer
                       ring is drawn hardest because it is the 100 mark. */
                    context.stroke(
                        path,
                        with: .color(APEXColor.ink.opacity(ring == 4 ? 0.22 : 0.10)),
                        lineWidth: ring == 4 ? 1.4 : 1
                    )
                }
                for index in stats.indices {
                    var spoke = Path(); spoke.move(to: center)
                    spoke.addLine(to: radarPoint(index: index, count: stats.count, radius: radius, center: center))
                    context.stroke(spoke, with: .color(APEXColor.ink.opacity(0.12)), lineWidth: 1)
                }
                var data = Path()
                for index in stats.indices {
                    let point = radarPoint(index: index, count: stats.count, radius: radius * CGFloat(min(1, max(0.02, stats[index].value / 100))), center: center)
                    index == stats.startIndex ? data.move(to: point) : data.addLine(to: point)
                }
                data.closeSubpath()
                context.fill(
                    data,
                    with: .linearGradient(
                        Gradient(colors: [APEXColor.violet.opacity(0.42), APEXColor.cyan.opacity(0.32)]),
                        startPoint: CGPoint(x: center.x, y: center.y - radius),
                        endPoint: CGPoint(x: center.x, y: center.y + radius)
                    )
                )
                context.stroke(data, with: .color(APEXColor.violet), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                /* A dot on each vertex, so a value can be read off the shape
                   instead of guessed from where the outline bends. */
                for index in stats.indices {
                    let point = radarPoint(
                        index: index, count: stats.count,
                        radius: radius * CGFloat(min(1, max(0.02, stats[index].value / 100))),
                        center: center
                    )
                    let dot = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
                    context.fill(Circle().path(in: dot), with: .color(.white))
                    context.stroke(Circle().path(in: dot), with: .color(APEXColor.violet), lineWidth: 2)
                }
            }
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                let point = radarPoint(index: index, count: stats.count, radius: radius + 34, center: center)
                VStack(spacing: 2) {
                    Text(language.text(shortName(stat.name)))
                        .font(APEXFont.mono(8, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(APEXColor.secondaryInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    /* The number is the point of the chart, so it is the size
                       of something meant to be read at arm's length. */
                    Text("\(Int(stat.value.rounded()))")
                        .font(APEXFont.mono(14, weight: .bold))
                        .foregroundStyle(APEXColor.ink)
                }.frame(width: 84).position(point)
            }
        }
    }

    private func radarPoint(index: Int, count: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = -Double.pi / 2 + (Double(index) / Double(count)) * Double.pi * 2
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func shortName(_ name: String) -> String {
        switch name {
        case "Joint Health Balance": "JOINTS"
        case "Body Flexibility": "MOBILITY"
        case "Endurance & VO₂ max": "ENDURANCE"
        case "Upper Body Strength": "UPPER BODY"
        case "Lower Body Strength": "LOWER BODY"
        default: name.uppercased()
        }
    }
}

private struct StrengthPoint: Identifiable {
    let id = UUID()
    let date: String
    let value: Double
    let weight: Double?
    let reps: Int?
}

private struct StrengthHistoryCard: View {
    @State private var language = LanguageState.shared
    @State private var selectedExercise = ""
    let sessions: [WorkoutSession]
    let logs: [WorkoutLog]
    let days: Int

    private var names: [String] { Array(Set(logs.filter { !$0.skipped }.map(\.exerciseName))).sorted() }
    private var activeName: String { selectedExercise.isEmpty ? (names.first ?? "") : selectedExercise }
    private var points: [StrengthPoint] {
        let sessionDates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.date) })
        return logs.filter { !$0.skipped && $0.exerciseName == activeName }.compactMap { log in
            guard let date = sessionDates[log.sessionID] else { return nil }
            if let weight = log.weightKG, let reps = log.reps { return StrengthPoint(date: date, value: weight * (1 + Double(reps) / 30), weight: weight, reps: reps) }
            if let reps = log.reps { return StrengthPoint(date: date, value: Double(reps), weight: nil, reps: reps) }
            return nil
        }.sorted { $0.date < $1.date }
    }

    var body: some View {
        GlassCard(radius: 32, padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                Text(language.text("STRENGTH HISTORY")).font(APEXFont.mono(10)).tracking(2).foregroundStyle(APEXColor.violet)
                Text(language.text("What you can lift, over time")).font(APEXFont.display(25))
                Text(language.text("Built from the loads and reps you recorded, one line per exercise."))
                    .font(APEXFont.body(12, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                if names.isEmpty {
                    Text(language.text("Complete a workout with recorded reps or load to begin strength history."))
                        .font(APEXFont.body(13, weight: .medium)).foregroundStyle(APEXColor.secondaryInk).padding(.vertical, 20)
                } else {
                    Picker(language.text("Exercise"), selection: $selectedExercise) {
                        ForEach(names, id: \.self) { Text(language.text($0)).tag($0) }
                    }.pickerStyle(.menu).tint(APEXColor.ink)
                    HStack(spacing: 10) {
                        historyMetric("Best working load", points.compactMap(\.weight).max().map { "\($0.formatted()) kg" } ?? "—")
                        historyMetric("Estimated strength", points.map(\.value).max().map { "\($0.formatted(.number.precision(.fractionLength(1))))" } ?? "—")
                        historyMetric("Sessions", "\(Set(points.map(\.date)).count)")
                    }
                    /* A curve with weight under it rather than a hairline on
                       white. The gradient gives the line something to sit on,
                       the glow lifts it off the card, and the last point is
                       marked because the newest number is the one being looked
                       for. */
                    Chart(Array(points.suffix(days))) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Strength", point.value)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [APEXColor.violet.opacity(0.34), APEXColor.violet.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Strength", point.value)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [APEXColor.cyan, APEXColor.violet],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                        .shadow(color: APEXColor.violet.opacity(0.45), radius: 7, y: 3)

                        if point.date == points.suffix(days).last?.date {
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Strength", point.value)
                            )
                            .symbolSize(150)
                            .foregroundStyle(.white)
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Strength", point.value)
                            )
                            .symbolSize(60)
                            .foregroundStyle(APEXColor.violet)
                        }
                    }
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisValueLabel()
                                .font(APEXFont.mono(8))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                    .frame(height: 165)
                }
            }
        }
        .onAppear { if selectedExercise.isEmpty { selectedExercise = names.first ?? "" } }
    }

    private func historyMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(language.text(title)).font(APEXFont.body(8, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
            Text(value).font(APEXFont.mono(11)).lineLimit(1).minimumScaleFactor(0.72)
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct AvatarHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = LanguageState.shared
    let profile: Profile?
    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.10), Color(red: 0.11, green: 0.05, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(APEXColor.violet.opacity(0.35), lineWidth: 1).frame(width: pulse ? 245 : 215).opacity(pulse ? 0.15 : 0.7)
            Circle().fill(APEXColor.violet.opacity(0.16)).frame(width: 205, height: 205).blur(radius: 20)
            PortraitImage(name: profile?.persona.portraitName ?? "constantine")
                .scaledToFit().frame(height: 285).mask(RoundedRectangle(cornerRadius: 38, style: .continuous))
            VStack {
                Spacer()
                HStack {
                    /* The name only. The overall score has its own card
                       directly underneath, and printing it twice made the
                       second one look like a different number. */
                    Text(profile?.displayName ?? "APEX")
                        .font(APEXFont.display(24))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(); Image(systemName: "waveform.path.ecg").font(.system(size: 27, weight: .semibold))
                }.foregroundStyle(.white).padding(20).background(.black.opacity(0.26))
            }
        }
        .frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .shadow(color: APEXColor.violet.opacity(0.22), radius: 30, y: 14)
        /* Never settles, so Reduce Motion turns it off entirely rather than
           shortening it. */
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
