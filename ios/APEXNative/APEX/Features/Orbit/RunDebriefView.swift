import MapKit
import SwiftUI

struct RunDebriefView: View {
    @Environment(AppSession.self) private var session
    let run: OrbitRunRecord
    let onDone: () -> Void

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var perceivedEffort = 5
    @State private var legs = "normal"
    @State private var discomfort = "none"
    @State private var note = ""
    @State private var isSaving = false
    @State private var showsRoutePoster = false
    @State private var nutritionApplied: Bool
    @State private var isApplyingNutrition = false
    @State private var language = LanguageState.shared

    init(run: OrbitRunRecord, onDone: @escaping () -> Void) {
        self.run = run
        self.onDone = onDone
        _perceivedEffort = State(initialValue: Int(run.checkIn["perceived_effort"]?.numberValue ?? 5))
        _legs = State(initialValue: run.checkIn["legs"]?.stringValue ?? "normal")
        _discomfort = State(initialValue: run.checkIn["discomfort"]?.stringValue ?? "none")
        _note = State(initialValue: run.checkIn["note"]?.stringValue ?? "")
        _nutritionApplied = State(initialValue: run.nutritionAdjustmentAppliedAt != nil)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        run.samples.compactMap { sample in
            guard case .object(let object) = sample,
                  case .number(let latitude)? = object["lat"],
                  case .number(let longitude)? = object["lng"]
            else { return nil }
            return .init(latitude: latitude, longitude: longitude)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ZStack(alignment: .bottomLeading) {
                        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                            if coordinates.count > 1 {
                                MapPolyline(coordinates: coordinates)
                                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                                MapPolyline(coordinates: coordinates)
                                    .stroke(APEXColor.cyan.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                            }
                        }
                        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(language.text("APEX PERFORMANCE DEBRIEF"))
                                .font(APEXFont.mono(9))
                                .tracking(1.4)
                            Text(language.text(missionTitle))
                                .font(APEXFont.display(25))
                        }
                        .foregroundStyle(.white)
                        .padding(17)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.62))
                    }
                    .frame(height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 35).stroke(.white.opacity(0.82)))

                    GlassCard(radius: 30, padding: 20) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 15) {
                            metric("DISTANCE", distanceLabel)
                            metric("MOVING", durationLabel(movingSeconds))
                            metric("AVG PACE", paceLabel(averagePace))
                            metric("ELAPSED", durationLabel(elapsedSeconds))
                            metric("BEST KM", paceLabel(bestPace))
                            metric("ELEVATION", elevationLabel)
                        }
                    }

                    GlassCard(radius: 30, padding: 20) {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                Image(systemName: missionSymbol)
                                    .foregroundStyle(APEXColor.cyan)
                                Text(language.text("What this run built"))
                                    .font(APEXFont.display(22))
                            }
                            Text(language.text(missionAssessment))
                                .font(APEXFont.body(14, weight: .bold))
                            ForEach(analysisFacts, id: \.self) { fact in
                                Label(language.text(fact), systemImage: "sparkle")
                                    .font(APEXFont.body(12, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                        }
                    }

                    if splits.isEmpty == false {
                        VStack(alignment: .leading, spacing: 11) {
                            Text(language.text("Kilometre splits"))
                                .font(APEXFont.display(24))
                            ForEach(splits, id: \.index) { split in
                                HStack {
                                    Text(split.distanceM >= 900 ? language.format("KM %d", split.index) : language.text("FINAL"))
                                        .font(APEXFont.mono(9))
                                        .foregroundStyle(APEXColor.cyan)
                                        .frame(width: 52, alignment: .leading)
                                    Text(paceLabel(split.paceSecondsPerKM))
                                        .font(APEXFont.display(18))
                                    Spacer()
                                    if let elevation = split.elevationDeltaM {
                                        Text(language.format("%@%d m", elevation >= 0 ? "+" : "", Int(elevation)))
                                            .font(APEXFont.mono(9))
                                            .foregroundStyle(APEXColor.secondaryInk)
                                    }
                                }
                                .padding(14)
                                .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 19))
                            }
                        }
                    }

                    if let routeDNA {
                        GlassCard(radius: 30, padding: 20) {
                            VStack(alignment: .leading, spacing: 11) {
                                HStack {
                                    Text(language.text("Route DNA"))
                                        .font(APEXFont.display(23))
                                    Spacer()
                                    Text(language.format("%d completions", routeDNA.completions).uppercased(with: language.language.locale))
                                        .font(APEXFont.mono(8))
                                        .foregroundStyle(APEXColor.cyan)
                                }
                                Text(language.text(routeDNA.interpretation))
                                    .font(APEXFont.body(13, weight: .bold))
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                                    metric("TYPICAL", language.format("%.2f km", routeDNA.typicalDistanceM / 1_000))
                                    metric("TIME", durationLabel(routeDNA.typicalDurationSeconds))
                                    metric("PACE", paceLabel(routeDNA.typicalPaceSecondsPerKM))
                                }
                                Text(language.text(routeDNA.recentTrend))
                                    .font(APEXFont.body(11, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                        }
                    }

                    GlassCard(radius: 30, padding: 20) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text(language.text("NUTRITION · FOOD MEMORY"))
                                .font(APEXFont.mono(9))
                                .tracking(1.2)
                                .foregroundStyle(APEXColor.amberDeep)
                            Text(language.text(nutritionHeadline))
                                .font(APEXFont.display(21))
                            if let suggestion = foodSuggestion {
                                Text(language.format(
                                    "+%d KCAL · P %d · C %d · F %d",
                                    Int(suggestion.nutrients.kcal.rounded()),
                                    Int(suggestion.nutrients.proteinG.rounded()),
                                    Int(suggestion.nutrients.carbsG.rounded()),
                                    Int(suggestion.nutrients.fatG.rounded())
                                ))
                                    .font(APEXFont.mono(9))
                                    .foregroundStyle(APEXColor.amberDeep)
                            }
                            Text(language.text(nutritionExplanation))
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                            if nutritionAdjustment.kcal > 0 {
                                Button {
                                    guard let operation = session.accountOperationLease() else { return }
                                    Task { await applyNutrition(operation: operation) }
                                } label: {
                                    if isApplyingNutrition { ProgressView().tint(.white) }
                                    else {
                                        Label(
                                            language.text(nutritionApplied ? "Adjustment applied" : "Review and apply exact adjustment"),
                                            systemImage: nutritionApplied ? "checkmark.circle.fill" : "plus.circle.fill"
                                        )
                                    }
                                }
                                .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.amberDeep))
                                .disabled(nutritionApplied || isApplyingNutrition)
                            }
                        }
                    }

                    GlassCard(radius: 30, padding: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(language.text("APEX RESPONSE"))
                                .font(APEXFont.mono(9))
                                .tracking(1.2)
                                .foregroundStyle(APEXColor.green)
                            Label(language.text("Training and Avatar remain coordinated"), systemImage: "point.3.connected.trianglepath.dotted")
                                .font(APEXFont.display(20))
                            Text(language.text(trainingAdjustment.explanation))
                                .font(APEXFont.body(12, weight: .bold))
                            Text(language.format(
                                "Avatar · %d endurance minutes · pacing discipline %d%%",
                                avatarContribution.enduranceMinutes,
                                Int((avatarContribution.pacingDisciplineSignal * 100).rounded())
                            ))
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                            Text(language.text(avatarContribution.explanation))
                                .font(APEXFont.body(10, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                            Text(language.text("PROPOSED AND REVERSIBLE · NEVER SILENT"))
                                .font(APEXFont.mono(8))
                                .foregroundStyle(APEXColor.green)
                        }
                    }

                    GlassCard(radius: 30, padding: 20) {
                        HStack(spacing: 15) {
                            ZStack {
                                Circle()
                                    .fill(APEXColor.cyan.opacity(0.13))
                                Image(systemName: "sparkles.rectangle.stack.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(APEXColor.cyan)
                            }
                            .frame(width: 52, height: 52)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(language.text("Create route poster"))
                                    .font(APEXFont.display(20))
                                Text(language.text("Map, constellation, elevation or minimal. Your exact start and finish stay hidden by default."))
                                    .font(APEXFont.body(10, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            Spacer(minLength: 4)
                            Button { showsRoutePoster = true } label: {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(APEXColor.cyan)
                        }
                    }

                    GlassCard(radius: 30, padding: 20) {
                        VStack(alignment: .leading, spacing: 17) {
                            Text(language.text("How did it feel?"))
                                .font(APEXFont.display(24))
                            HStack {
                                Text(language.text("PERCEIVED EFFORT"))
                                    .font(APEXFont.mono(9))
                                Spacer()
                                Text("\(perceivedEffort) / 10")
                                    .font(APEXFont.display(18))
                            }
                            Slider(value: Binding(
                                get: { Double(perceivedEffort) },
                                set: { perceivedEffort = Int($0.rounded()) }
                            ), in: 1...10, step: 1)
                            .tint(APEXColor.cyan)

                            Picker("Legs", selection: $legs) {
                                Text(language.text("Fresh")).tag("fresh")
                                Text(language.text("Normal")).tag("normal")
                                Text(language.text("Heavy")).tag("heavy")
                                Text(language.text("Very heavy")).tag("very_heavy")
                            }
                            .pickerStyle(.segmented)

                            Picker("Discomfort", selection: $discomfort) {
                                Text(language.text("None")).tag("none")
                                Text(language.text("Noticeable")).tag("noticeable")
                                Text(language.text("Changed movement")).tag("changed_movement")
                            }
                            .pickerStyle(.menu)

                            TextField(language.text("Optional private note"), text: $note, axis: .vertical)
                                .lineLimit(2...5)
                                .padding(13)
                                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18))

                            if discomfort == "changed_movement" {
                                Text(language.text("Orbit records what you report and can reduce training load. It does not diagnose an injury. Consider professional advice if symptoms persist or concern you."))
                                    .font(APEXFont.body(10, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }

                            Button {
                                guard let operation = session.accountOperationLease() else { return }
                                Task { await saveAndFinish(operation: operation) }
                            } label: {
                                if isSaving { ProgressView().tint(.white) }
                                else { Label(language.text("Save debrief"), systemImage: "checkmark") }
                            }
                            .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.cyan))
                            .disabled(isSaving)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .background(APEXBackground())
            .navigationTitle(language.text("Run complete"))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .onAppear { fitRoute() }
            .sheet(isPresented: $showsRoutePoster) {
                OrbitRoutePosterSheet(run: run)
            }
        }
    }

    private var missionTitle: String {
        run.mission.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var missionSymbol: String {
        ["recovery", "easy", "aerobic_base", "run_walk"].contains(run.mission) ? "leaf.fill" : "bolt.fill"
    }

    private var distanceM: Double { run.metrics["distance_m"]?.numberValue ?? 0 }
    private var movingSeconds: Double { run.metrics["moving_s"]?.numberValue ?? 0 }
    private var elapsedSeconds: Double { run.metrics["elapsed_s"]?.numberValue ?? 0 }
    private var averagePace: Double? { run.metrics["avg_pace_sec_km"]?.numberValue }
    private var bestPace: Double? { run.metrics["best_pace_sec_km"]?.numberValue }

    private var reflectedRun: OrbitRunRecord {
        OrbitRunRecord(
            id: run.id, userID: run.userID, clientIdempotencyKey: run.clientIdempotencyKey,
            localDate: run.localDate, startedAt: run.startedAt, endedAt: run.endedAt,
            mission: run.mission, routeID: run.routeID, campaignSessionID: run.campaignSessionID,
            shoeID: run.shoeID, samples: run.samples, pauses: run.pauses,
            manualLapsM: run.manualLapsM, metrics: run.metrics,
            checkIn: [
                "perceived_effort": .number(Double(perceivedEffort)),
                "legs": .string(legs),
                "discomfort": .string(discomfort),
                "note": .string(note)
            ],
            nutritionAdjustmentAppliedAt: nutritionApplied ? (run.nutritionAdjustmentAppliedAt ?? Date().ISO8601Format()) : nil,
            status: run.status, createdAt: run.createdAt, updatedAt: run.updatedAt
        )
    }

    private var nutritionAdjustment: OrbitNutritionAdjustment {
        OrbitIntegrations.nutritionAdjustment(run: run, weightKG: session.profile?.weightKG ?? 0)
    }

    private var foodSuggestion: OrbitFoodMemorySuggestion? {
        OrbitIntegrations.foodMemorySuggestion(
            adjustment: nutritionAdjustment,
            foods: session.data.foods,
            preferences: session.data.foodPreferences
        )
    }

    private var nutritionHeadline: String {
        if let suggestion = foodSuggestion {
            return language.format("%d %@ %@", Int(suggestion.amount.rounded()), language.text(suggestion.unit), suggestion.food.name)
        }
        guard nutritionAdjustment.kcal > 0 else { return language.text("Normal meals cover this run") }
        return language.format(
            "+%d kcal · %d g carbs · %d g protein",
            nutritionAdjustment.kcal,
            nutritionAdjustment.carbsG,
            nutritionAdjustment.proteinG
        )
    }

    private var nutritionExplanation: String {
        language.text(nutritionAdjustment.explanation) + (foodSuggestion == nil ? "" : " " + language.text("Orbit selected a familiar high-carbohydrate food from your private Food Memory. Nothing changes until you confirm it."))
    }

    private var trainingAdjustment: OrbitTrainingAdjustment {
        OrbitIntegrations.trainingAdjustment(
            run: reflectedRun,
            sessions: session.data.workoutSessions,
            programDays: session.data.programDays
        )
    }

    private var avatarContribution: OrbitAvatarContribution {
        OrbitIntegrations.avatarContribution(run: reflectedRun)
    }

    private var distanceLabel: String { language.format("%.2f km", distanceM / 1_000) }
    private var elevationLabel: String {
        guard let value = run.metrics["elevation_gain_m"]?.numberValue else { return "Unavailable" }
        return language.format("%d m", Int(value.rounded()))
    }

    private var splits: [OrbitSplit] {
        guard case .array(let values)? = run.metrics["splits"] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value,
                  let index = object["index"]?.numberValue,
                  let distance = object["distance_m"]?.numberValue,
                  let duration = object["duration_s"]?.numberValue,
                  let pace = object["pace_sec_km"]?.numberValue
            else { return nil }
            return OrbitSplit(
                index: Int(index),
                distanceM: distance,
                durationSeconds: duration,
                paceSecondsPerKM: pace,
                elevationDeltaM: object["elevation_delta_m"]?.numberValue
            )
        }
    }

    private var paceVariationPercent: Double? {
        let paces = splits.filter { $0.distanceM >= 900 }.map(\.paceSecondsPerKM)
        guard paces.count >= 2 else { return nil }
        let average = paces.reduce(0, +) / Double(paces.count)
        guard average > 0 else { return nil }
        let variance = paces.reduce(0) { $0 + pow($1 - average, 2) } / Double(paces.count)
        return sqrt(variance) / average * 100
    }

    private var splitClassification: String? {
        let paces = splits.filter { $0.distanceM >= 900 }.map(\.paceSecondsPerKM)
        guard paces.count >= 4 else { return nil }
        let count = paces.count / 2
        let first = paces.prefix(count).reduce(0, +) / Double(count)
        let second = paces.suffix(count).reduce(0, +) / Double(count)
        let change = (second - first) / first
        if change <= -0.02 { return "negative" }
        if change >= 0.02 { return "positive" }
        return "even"
    }

    private var missionAssessment: String {
        guard distanceM >= 500, movingSeconds >= 300 else {
            return language.text("Not enough recorded movement for a reliable mission assessment.")
        }
        let easy = ["recovery", "easy", "aerobic_base", "run_walk"].contains(run.mission)
        if easy && perceivedEffort >= 7 {
            return language.text("This run was harder than the selected mission. Orbit will protect the next demanding session.")
        }
        if run.mission == "recovery" && perceivedEffort <= 4 {
            return language.text("The run stayed appropriately controlled for recovery.")
        }
        if let paceVariationPercent, paceVariationPercent <= 6 {
            return language.text("Pacing remained controlled and matched the selected mission well.")
        }
        return language.text("The useful work was completed, with pacing details to refine next time.")
    }

    private var analysisFacts: [String] {
        var facts = runAnalysis.facts
        if let paceVariationPercent {
            facts.append(language.format("Kilometre pace variation was %.1f%%.", paceVariationPercent))
        }
        if let load = runAnalysis.trainingLoad {
            facts.append(language.format("Training load was approximately %d AU from minutes × reported effort.", Int(load)))
        }
        if let recovery = runAnalysis.recoveryCost {
            facts.append(language.format("Recovery cost computes as %@.", language.text(recovery)))
        }
        if let confidence = run.metrics["gps_confidence"]?.stringValue {
            facts.append(language.format("GPS confidence was %@.", language.text(confidence)))
        }
        if let calories = run.metrics["calories_kcal"]?.numberValue {
            facts.append(language.format("Distance-based energy estimate: about %d kcal.", Int(calories)))
        }
        return facts.isEmpty ? [language.text("Orbit recorded the available facts without inventing missing heart-rate or cadence data.")] : facts.map(language.text)
    }

    private var runAnalysis: OrbitRunAnalysis {
        OrbitAnalysisEngine.analyze(run: reflectedRun)
    }

    private var routeDNA: OrbitRouteDNA? {
        guard let routeID = run.routeID,
              let route = session.data.orbitRoutes.first(where: { $0.id == routeID })
        else { return nil }
        return OrbitAnalysisEngine.routeDNA(route: route, runs: session.data.orbitRuns)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.text(title))
                .font(APEXFont.mono(8))
                .foregroundStyle(APEXColor.secondaryInk)
            Text(value)
                .font(APEXFont.display(17))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func durationLabel(_ seconds: Double) -> String {
        let value = Int(seconds.rounded())
        if value >= 3_600 { return String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func paceLabel(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "–:––" }
        return language.format("%d:%02d /km", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func fitRoute() {
        guard let first = coordinates.first else { return }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.006, (latitudes.max() ?? first.latitude) - (latitudes.min() ?? first.latitude)) * 1.4,
            longitudeDelta: max(0.006, (longitudes.max() ?? first.longitude) - (longitudes.min() ?? first.longitude)) * 1.4
        )
        mapPosition = .region(.init(center: first, span: span))
    }

    @MainActor
    private func saveAndFinish(operation: AccountOperationLease) async {
        guard session.accountOperationIsCurrent(operation) else { return }
        isSaving = true
        defer {
            if session.accountOperationIsCurrent(operation) {
                isSaving = false
            }
        }
        do {
            _ = try await session.updateOrbitRunCheckIn(
                run,
                perceivedEffort: perceivedEffort,
                legs: legs,
                discomfort: discomfort,
                note: note,
                operation: operation
            )
            guard session.accountOperationIsCurrent(operation) else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone()
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applyNutrition(operation: AccountOperationLease) async {
        guard nutritionApplied == false else { return }
        guard session.accountOperationIsCurrent(operation) else { return }
        isApplyingNutrition = true
        defer {
            if session.accountOperationIsCurrent(operation) {
                isApplyingNutrition = false
            }
        }
        do {
            let updated = try await session.applyOrbitNutritionAdjustment(
                to: run,
                foodSuggestion: foodSuggestion,
                operation: operation
            )
            guard session.accountOperationIsCurrent(operation) else { return }
            nutritionApplied = updated.nutritionAdjustmentAppliedAt != nil
            if nutritionApplied { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            session.alertMessage = error.localizedDescription
        }
    }
}
