import SwiftUI

struct BaselineCalibrationSheet: View {
    private enum Route {
        case home, questions, recentResult, health
    }

    private enum SaveState {
        case idle, saving, saved, failed
    }

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State private var route: Route = .home
    @State private var draft = BaselineCalibrationDraft.empty
    @State private var saveState: SaveState = .idle
    @State private var resultMetric = ManualCalibrationMetric.bodyFat
    @State private var resultValue = ""
    @State private var resultSource = ""
    @State private var resultDate = Date.now
    @State private var healthStatus: Bool?
    @FocusState private var focusedField: ResultField?

    private enum ResultField { case value, source }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch route {
                    case .home: home
                    case .questions: questions
                    case .recentResult: recentResult
                    case .health: health
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .background(
                LinearGradient(
                    colors: [Color.white, APEXColor.green.opacity(0.06), APEXColor.violet.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle(language.text("Calibrate my baseline"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if route != .home {
                        Button(language.text("Back")) {
                            focusedField = nil
                            route = .home
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.text("Close")) { dismiss() }
                }
            }
        }
        .onAppear { restoreDraft() }
        .interactiveDismissDisabled(saveState == .saving)
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(language.text("Sharpen your map"))
                    .font(APEXFont.display(30))
                Text(language.text("Add better evidence without turning fitness into a test you can fail."))
                    .font(APEXFont.body(14, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .lineSpacing(3)
            }

            authorityNotice

            calibrationRoute(
                title: "Sharpen with questions",
                detail: "Twelve observable prompts in four short sections.",
                icon: "slider.horizontal.3",
                tint: APEXColor.green,
                identifier: "calibration.route.questions"
            ) {
                if draft.step == 0 { draft.step = 1 }
                persistDraft()
                route = .questions
            }

            calibrationRoute(
                title: "Connect what you track",
                detail: "Import the Apple Health categories you choose.",
                icon: "heart.text.square.fill",
                tint: APEXColor.cyan,
                identifier: "calibration.route.health"
            ) { route = .health }

            calibrationRoute(
                title: "Add a recent result",
                detail: "Keep a DEXA, metabolic, VO₂, heart-rate or waist result with its source.",
                icon: "doc.text.magnifyingglass",
                tint: APEXColor.violet,
                identifier: "calibration.route.result"
            ) { route = .recentResult }

            if draft.step > 1 {
                Label(
                    language.text("Your question progress is saved privately on this device."),
                    systemImage: "checkmark.circle.fill"
                )
                .font(APEXFont.body(12, weight: .semibold))
                .foregroundStyle(APEXColor.green)
            }
        }
    }

    private var authorityNotice: some View {
        let isBespoke = session.profile?.profileKind == .bespoke
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(APEXColor.green)
            Text(language.text(
                isBespoke
                    ? "Your bespoke plan stays protected. Calibration only refines your evidence."
                    : "Calibration refines your evidence. It never rewrites your training or nutrition plan."
            ))
            .font(APEXFont.body(12, weight: .semibold))
            .foregroundStyle(APEXColor.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(APEXColor.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var questions: some View {
        if draft.step >= 5 {
            review
        } else {
            let domain = currentDomain
            VStack(alignment: .leading, spacing: 16) {
                ProgressView(value: Double(draft.step), total: 4)
                    .tint(APEXColor.green)
                    .accessibilityLabel(language.text("Calibration progress"))
                    .accessibilityValue("\(draft.step) / 4")

                Text(language.text(domain.title))
                    .font(APEXFont.display(29))
                Text(language.text("Answer from recent, pain-free experience. Do not test a movement now. Choose Not tested if pain or uncertainty is involved."))
                    .font(APEXFont.body(13, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .lineSpacing(3)
                Text(language.text("Read each line left to right: Foundation, Developing, Capable, Strong signal."))
                    .font(APEXFont.body(11, weight: .semibold))
                    .foregroundStyle(APEXColor.green)

                ForEach(Array(domain.questions.enumerated()), id: \.offset) { index, question in
                    questionCard(domain: domain.domain, index: index, question: question)
                }

                HStack(spacing: 12) {
                    Button(language.text("Back")) {
                        if draft.step > 1 {
                            draft.step -= 1
                            persistDraft()
                        } else {
                            route = .home
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)

                    Button {
                        draft.step += 1
                        persistDraft()
                    } label: {
                        Text(language.text(draft.step == 4 ? "Review my baseline" : "Continue"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(APEXColor.green)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("calibration.next")
                }
            }
        }
    }

    private var review: some View {
        let evaluation = calibrationEvaluation
        return VStack(alignment: .leading, spacing: 16) {
            Text(language.text("Your sharper starting map"))
                .font(APEXFont.display(29))
            Text(language.text("These remain broad bands, not laboratory measurements. Overall Fitness stays Building your baseline until enough independent evidence exists."))
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineSpacing(3)

            if case .accepted(let result) = evaluation {
                bandRow("Stamina", result.bands.cardiorespiratory)
                bandRow("Upper body", result.bands.upperStrength)
                bandRow("Lower body", result.bands.lowerStrength)
                bandRow("Mobility", result.bands.mobility)

                if result.evidence.isEmpty {
                    Text(language.text("Answer at least two prompts in a section to sharpen that band."))
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.amberDeep)
                }

                if saveState == .saved {
                    Label(language.text("Saved to your evidence"), systemImage: "checkmark.seal.fill")
                        .font(APEXFont.body(14, weight: .bold))
                        .foregroundStyle(APEXColor.green)
                    Button(language.text("Done")) { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(APEXColor.green)
                        .frame(maxWidth: .infinity, minHeight: 48)
                } else {
                    Button {
                        Task { await saveQuestionnaire() }
                    } label: {
                        Text(language.text(saveState == .saving ? "Saving…" : "Save baseline"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(APEXColor.green)
                    .frame(minHeight: 48)
                    .disabled(result.evidence.isEmpty || saveState == .saving)
                    .accessibilityIdentifier("calibration.save")
                }

                if saveState == .failed {
                    Text(language.text("Your baseline could not be saved yet. Your answers remain on this device."))
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.danger)
                }
            }

            Button(language.text("Back to questions")) {
                saveState = .idle
                draft.step = 4
                persistDraft()
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        }
    }

    private var recentResult: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language.text("Add a recent result"))
                .font(APEXFont.display(29))
            Text(language.text("APEX keeps a value you enter as unverified until a supported source confirms it."))
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 8) {
                Text(language.text("Result type")).font(APEXFont.body(12, weight: .bold))
                Picker(language.text("Result type"), selection: $resultMetric) {
                    ForEach(ManualCalibrationMetric.allCases) { metric in
                        Text(language.text(metric.title)).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 12)
                .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(language.text("Value")).font(APEXFont.body(12, weight: .bold))
                HStack {
                    TextField(resultMetric.placeholder, text: $resultValue)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .value)
                        .accessibilityIdentifier("calibration.result.value")
                    Text(resultMetric.unitLabel)
                        .font(APEXFont.mono(11, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(language.text("Where did this result come from?"))
                    .font(APEXFont.body(12, weight: .bold))
                TextField(language.text("For example, DEXA report or laboratory test"), text: $resultSource)
                    .textInputAutocapitalization(.sentences)
                    .focused($focusedField, equals: .source)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("calibration.result.source")
            }

            DatePicker(
                language.text("Measured on"),
                selection: $resultDate,
                in: ...Date.now,
                displayedComponents: .date
            )
            .font(APEXFont.body(13, weight: .bold))

            if saveState == .saved {
                Label(language.text("Result saved"), systemImage: "checkmark.seal.fill")
                    .font(APEXFont.body(14, weight: .bold))
                    .foregroundStyle(APEXColor.green)
            }

            Button {
                focusedField = nil
                Task { await saveRecentResult() }
            } label: {
                Text(language.text(saveState == .saving ? "Saving…" : "Save result"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(APEXColor.violet)
            .frame(minHeight: 48)
            .disabled(parsedResultValue == nil || resultSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saveState == .saving)

            if saveState == .failed {
                Text(language.text("Check the value and source, then try again."))
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.danger)
            }
        }
    }

    private var health: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language.text("Apple Health"))
                .font(APEXFont.display(29))
            Text(language.text("You choose what APEX can read. Denial or missing data never lowers your baseline, and manual calibration always remains available."))
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineSpacing(3)

            if let healthStatus {
                Label(
                    language.text(
                        healthStatus
                            ? "Apple Health synced the categories you allowed."
                            : "No new permitted data was available. You can keep calibrating manually."
                    ),
                    systemImage: healthStatus ? "checkmark.circle.fill" : "info.circle.fill"
                )
                .font(APEXFont.body(13, weight: .semibold))
                .foregroundStyle(healthStatus ? APEXColor.green : APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    saveState = .saving
                    healthStatus = await session.connectHealthForBaselineCalibration()
                    saveState = .idle
                }
            } label: {
                Label(language.text("Connect Apple Health"), systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(APEXColor.cyan)
            .frame(minHeight: 48)
            .disabled(saveState == .saving || !HealthKitManager.shared.isAvailable)
            .accessibilityIdentifier("calibration.connect-health")
        }
    }

    private func calibrationRoute(
        title: String,
        detail: String,
        icon: String,
        tint: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text(title)).font(APEXFont.body(15, weight: .bold))
                    Text(language.text(detail))
                        .font(APEXFont.body(11, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").foregroundStyle(APEXColor.secondaryInk)
            }
            .foregroundStyle(APEXColor.ink)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func questionCard(
        domain: OnboardingMovementDomain,
        index: Int,
        question: String
    ) -> some View {
        let selected = answer(domain: domain, index: index)
        return VStack(alignment: .leading, spacing: 10) {
            Text(language.text(question))
                .font(APEXFont.body(13, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Menu {
                ForEach(BaselineCalibrationAnswer.allCases, id: \.rawValue) { answer in
                    Button(language.text(answer.title)) {
                        setAnswer(answer.rawValue, domain: domain, index: index)
                    }
                }
            } label: {
                HStack {
                    Text(language.text(selected.title))
                        .font(APEXFont.body(13, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(APEXColor.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
        .padding(15)
        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calibration.question.\(domain.rawValue).\(index)")
    }

    private func bandRow(_ title: String, _ band: OnboardingBaselineBand) -> some View {
        HStack(spacing: 12) {
            Text(language.text(title)).font(APEXFont.body(14, weight: .bold))
            Spacer()
            Text(language.text(band.title))
                .font(APEXFont.mono(10, weight: .bold))
                .foregroundStyle(band == .buildingBaseline ? APEXColor.secondaryInk : APEXColor.green)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(APEXColor.green.opacity(0.08), in: Capsule())
        }
        .padding(14)
        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var currentDomain: CalibrationDomainContent {
        CalibrationDomainContent.all[max(0, min(3, draft.step - 1))]
    }

    private var calibrationEvaluation: BaselineCalibrationResult {
        let now = Date().ISO8601Format()
        return BaselineCalibrationAssessment.evaluate(
            userID: session.profile?.userID.uuidString ?? "",
            measuredAt: now,
            importedAt: now,
            answers: draft.answers
        )
    }

    private var parsedResultValue: Double? {
        Double(resultValue.replacingOccurrences(of: ",", with: "."))
    }

    private func answer(domain: OnboardingMovementDomain, index: Int) -> BaselineCalibrationAnswer {
        let values = draft.answers.values(for: domain)
        guard values.indices.contains(index) else { return .notTested }
        return BaselineCalibrationAnswer(rawValue: values[index]) ?? .notTested
    }

    private func setAnswer(_ value: String, domain: OnboardingMovementDomain, index: Int) {
        switch domain {
        case .cardiorespiratory: draft.answers.cardiorespiratory[index] = value
        case .upperStrength: draft.answers.upperStrength[index] = value
        case .lowerStrength: draft.answers.lowerStrength[index] = value
        case .mobility: draft.answers.mobility[index] = value
        }
        saveState = .idle
        persistDraft()
    }

    private func restoreDraft() {
        guard let userID = session.profile?.userID else { return }
        draft = BaselineCalibrationDraftStore.load(userID: userID) ?? .empty
    }

    private func persistDraft() {
        guard let userID = session.profile?.userID else { return }
        BaselineCalibrationDraftStore.save(draft, userID: userID)
    }

    @MainActor
    private func saveQuestionnaire() async {
        saveState = .saving
        do {
            _ = try await session.saveBaselineCalibration(draft.answers)
            if let userID = session.profile?.userID {
                BaselineCalibrationDraftStore.clear(userID: userID)
            }
            saveState = .saved
        } catch {
            persistDraft()
            saveState = .failed
        }
    }

    @MainActor
    private func saveRecentResult() async {
        guard let value = parsedResultValue else { return }
        saveState = .saving
        do {
            try await session.saveManualCalibrationResult(
                metric: resultMetric.metric,
                value: value,
                unit: resultMetric.unit,
                declaredSource: resultSource,
                measuredAt: resultDate
            )
            resultValue = ""
            saveState = .saved
        } catch {
            saveState = .failed
        }
    }
}

private struct CalibrationDomainContent {
    let domain: OnboardingMovementDomain
    let title: String
    let questions: [String]

    static let all: [CalibrationDomainContent] = [
        CalibrationDomainContent(domain: .cardiorespiratory, title: "Stamina", questions: [
            "Sustained effort: a few minutes · brisk 20 minutes · steady cardio 20 minutes · trained intervals",
            "Stairs: frequent pause · one flight comfortable · several flights controlled · repeated climbs trained",
            "Conditioning week: none · one easy session · two steady sessions · three or more purposeful sessions",
        ]),
        CalibrationDomainContent(domain: .upperStrength, title: "Upper body", questions: [
            "Pressing: body weight difficult · raised push-ups · floor push-ups · challenging presses",
            "Pulling: little recent work · light supported rows · controlled rows · pull-ups or challenging pulls",
            "Upper-body training: none · occasional · weekly progressive work · multiple challenging sessions",
        ]),
        CalibrationDomainContent(domain: .lowerStrength, title: "Lower body", questions: [
            "Chair and stairs: tiring · comfortable · repeated with control · high work capacity",
            "Squat and lunge: restricted · chair-depth control · deep controlled reps · challenging full-range work",
            "Lower-body training: none · occasional · weekly progressive work · multiple challenging sessions",
        ]),
        CalibrationDomainContent(domain: .mobility, title: "Mobility", questions: [
            "Hips and posterior chain: daily restriction · functional reach · deep hinge or squat · advanced range practice",
            "Ankles: heels lift early · daily range comfortable · knee-over-toe range controlled · deep loaded range trained",
            "Shoulders: overhead reach restricted · daily reach comfortable · full overhead control · advanced range trained",
        ]),
    ]
}

private enum ManualCalibrationMetric: String, CaseIterable, Identifiable {
    case bodyFat, restingEnergy, vo2Max, restingHeartRate, waist
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bodyFat: "Body fat"
        case .restingEnergy: "Resting energy (BMR/RMR)"
        case .vo2Max: "VO₂ max"
        case .restingHeartRate: "Resting heart rate"
        case .waist: "Waist circumference"
        }
    }

    var metric: FitnessEvidenceMetric {
        switch self {
        case .bodyFat: .bodyFatPercentage
        case .restingEnergy: .restingMetabolicRate
        case .vo2Max: .vo2Max
        case .restingHeartRate: .restingHeartRate
        case .waist: .waistCircumference
        }
    }

    var unit: String {
        switch self {
        case .bodyFat: "percent"
        case .restingEnergy: "kcal_per_day"
        case .vo2Max: "ml_per_kg_min"
        case .restingHeartRate: "bpm"
        case .waist: "cm"
        }
    }

    var unitLabel: String {
        switch self {
        case .bodyFat: "%"
        case .restingEnergy: "kcal/day"
        case .vo2Max: "ml/kg/min"
        case .restingHeartRate: "bpm"
        case .waist: "cm"
        }
    }

    var placeholder: String {
        switch self {
        case .bodyFat: "18"
        case .restingEnergy: "1683"
        case .vo2Max: "42.5"
        case .restingHeartRate: "58"
        case .waist: "82"
        }
    }
}

private extension BaselineCalibrationAnswer {
    var title: String {
        switch self {
        case .notTested: "Not tested"
        case .foundation: "Foundation"
        case .developing: "Developing"
        case .capable: "Capable"
        case .strong: "Strong signal"
        }
    }
}

private extension OnboardingBaselineBand {
    var title: String {
        switch self {
        case .buildingBaseline: "Building your baseline"
        case .foundation: "Foundation"
        case .developing: "Developing"
        case .capable: "Capable"
        case .strong: "Strong signal"
        }
    }
}
