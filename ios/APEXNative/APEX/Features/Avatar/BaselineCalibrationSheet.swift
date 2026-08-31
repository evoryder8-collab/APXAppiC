import SwiftUI
import UIKit

struct BaselineCalibrationSheet: View {
    private enum Route { case home, questions, recentResult, health }
    private enum ResultRoute { case chooser, dexa, other }
    private enum SaveState { case idle, saving, saved, failed }
    private enum ResultField { case value, bodyFat, restingEnergy, source }

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    @State private var route: Route = .home
    @State private var resultRoute: ResultRoute = .chooser
    @State private var draft = BaselineCalibrationDraft.empty
    @State private var saveState: SaveState = .idle
    @State private var resultMetric = ManualCalibrationMetric.restingEnergy
    @State private var resultValue = ""
    @State private var dxaBodyFat = ""
    @State private var dxaRestingEnergy = ""
    @State private var resultSource = ""
    @State private var resultDate = Date.now
    @State private var savedResultSummaries: [String] = []
    @State private var healthStatus: Bool?
    @FocusState private var focusedField: ResultField?

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
            .background(background)
            .navigationTitle(language.text("Calibrate my baseline"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if route != .home {
                        Button(language.text("Back")) { navigateBack() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.text("Close")) { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(language.text("Done")) { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { restoreDraft() }
        .interactiveDismissDisabled(saveState == .saving)
    }

    private var background: some View {
        ZStack {
            Color.white
            LinearGradient(
                colors: [APEXColor.green.opacity(0.08), .clear, APEXColor.violet.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(language.text("A clearer starting point"))
                    .font(APEXFont.mono(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(APEXColor.violet)
                Text(language.text("Sharpen your map"))
                    .font(APEXFont.display(31))
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text("Add better evidence without turning fitness into a test you can fail."))
                    .font(APEXFont.body(14, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(19)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [APEXColor.green.opacity(0.12), APEXColor.violet.opacity(0.10), .white.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )

            authorityNotice

            calibrationRoute(
                title: "Sharpen with questions",
                detail: "12 clear questions · about 3 minutes",
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
                detail: "Lab & DEXA results · about 1 minute",
                icon: "doc.text.magnifyingglass",
                tint: APEXColor.violet,
                identifier: "calibration.route.result"
            ) {
                resetResultFlow()
                route = .recentResult
            }

            if !draft.answeredQuestionIDs.isEmpty {
                Label(
                    language.text("Your question progress is saved privately on this device."),
                    systemImage: "checkmark.circle.fill"
                )
                .font(APEXFont.body(12, weight: .semibold))
                .foregroundStyle(APEXColor.green)
                .fixedSize(horizontal: false, vertical: true)
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
        if draft.step > BaselineCalibrationQuestionBank.all.count {
            review
        } else {
            questionPage
        }
    }

    private var questionPage: some View {
        let question = currentQuestion
        return VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 9) {
                HStack {
                    Text(language.text(question.sectionTitle))
                    Spacer()
                    Text(language.text("Question"))
                    Text("\(draft.step) / \(BaselineCalibrationQuestionBank.all.count)")
                }
                .font(APEXFont.mono(10, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
                .textCase(.uppercase)

                ProgressView(
                    value: Double(draft.step),
                    total: Double(BaselineCalibrationQuestionBank.all.count)
                )
                .tint(APEXColor.green)
                .accessibilityLabel(language.text("Calibration progress"))
                .accessibilityValue("\(draft.step) / \(BaselineCalibrationQuestionBank.all.count)")
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(language.text(question.prompt))
                    .font(APEXFont.display(28))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("calibration.question.prompt")
                Text(language.text("Choose what has felt true recently. Never test through pain."))
                    .font(APEXFont.body(13, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(question.options, id: \.answer.rawValue) { option in
                    answerButton(
                        answer: option.answer,
                        title: option.title,
                        question: question,
                        muted: false
                    )
                }
                answerButton(
                    answer: .notTested,
                    title: "I'm not sure or haven't done this recently",
                    question: question,
                    muted: true
                )
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
                .frame(minHeight: 48)

                Button {
                    guard questionIsAnswered else { return }
                    draft.step = min(13, draft.step + 1)
                    persistDraft()
                } label: {
                    Text(language.text(
                        draft.step == BaselineCalibrationQuestionBank.all.count
                            ? "Review my baseline"
                            : "Continue"
                    ))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(APEXColor.green)
                .frame(minHeight: 48)
                .disabled(!questionIsAnswered)
                .accessibilityHint(
                    questionIsAnswered
                        ? ""
                        : language.text("Choose one answer before continuing.")
                )
                .accessibilityIdentifier("calibration.next")
            }
        }
    }

    private var review: some View {
        let evaluation = calibrationEvaluation
        return VStack(alignment: .leading, spacing: 16) {
            Text(language.text("Calibration complete"))
                .font(APEXFont.mono(10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(APEXColor.green)
            Text(language.text("Your sharper starting map"))
                .font(APEXFont.display(29))
                .fixedSize(horizontal: false, vertical: true)
            Text(language.text("These remain broad bands, not laboratory measurements. Overall Fitness stays Building your baseline until enough independent evidence exists."))
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if case .accepted(let result) = evaluation {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        bandTile("Stamina", result.bands.cardiorespiratory)
                        bandTile("Upper body", result.bands.upperStrength)
                    }
                    HStack(spacing: 10) {
                        bandTile("Lower body", result.bands.lowerStrength)
                        bandTile("Mobility", result.bands.mobility)
                    }
                }

                if result.evidence.isEmpty {
                    Text(language.text("Not enough recent answers to change a band yet. Your existing baseline stays safe."))
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.amberDeep)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(language.text("Keep my existing baseline")) { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(APEXColor.green)
                        .frame(maxWidth: .infinity, minHeight: 48)
                } else if saveState == .saved {
                    savedEvidencePanel
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
                    .disabled(saveState == .saving)
                    .accessibilityIdentifier("calibration.save")
                }

                if saveState == .failed {
                    Text(language.text("Your baseline could not be saved yet. Your answers remain on this device."))
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(language.text("Back to questions")) {
                saveState = .idle
                draft.step = BaselineCalibrationQuestionBank.all.count
                persistDraft()
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var recentResult: some View {
        switch resultRoute {
        case .chooser: resultChooser
        case .dexa: dexaResult
        case .other: otherResult
        }
    }

    private var resultChooser: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language.text("Evidence, not guesswork"))
                .font(APEXFont.mono(10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(APEXColor.violet)
            Text(language.text("What are you adding?"))
                .font(APEXFont.display(30))
                .fixedSize(horizontal: false, vertical: true)
            Text(language.text("Choose the report you have. APEX will only ask for values that belong to it."))
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            calibrationRoute(
                title: "DEXA body composition report",
                detail: "Save body fat and any resting-energy estimate printed on the same report.",
                icon: "figure.stand",
                tint: APEXColor.violet,
                identifier: "calibration.result.dexa"
            ) {
                if resultSource.isEmpty { resultSource = language.text("DEXA report") }
                resultRoute = .dexa
            }
            calibrationRoute(
                title: "Other health or fitness result",
                detail: "Add VO₂ max, resting heart rate, waist or a metabolic test.",
                icon: "plus",
                tint: APEXColor.cyan,
                identifier: "calibration.result.other"
            ) { resultRoute = .other }
        }
    }

    private var dexaResult: some View {
        VStack(alignment: .leading, spacing: 16) {
            resultHeader(
                eyebrow: "DEXA REPORT",
                title: "Add your DEXA results",
                detail: "Enter either value or both. Leave a field blank when it is not printed on your report."
            )

            if saveState == .saved {
                savedResultPanel
            } else {
                Text(language.text("DEXA measures body composition. Some reports also print an estimated BMR or RMR; APEX stores that number as report-supplied, not as a direct metabolic measurement."))
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .background(APEXColor.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                resultField(
                    label: "Body fat (optional)",
                    text: $dxaBodyFat,
                    placeholder: "18.4",
                    unit: "%",
                    focus: .bodyFat,
                    identifier: "calibration.result.dexa-body-fat"
                )
                resultField(
                    label: "Resting metabolism printed on the report (optional)",
                    text: $dxaRestingEnergy,
                    placeholder: "1683",
                    unit: "kcal/day",
                    focus: .restingEnergy,
                    identifier: "calibration.result.dexa-resting-energy"
                )
                sourceAndDate

                Button {
                    focusedField = nil
                    Task { await saveDEXAResult() }
                } label: {
                    Text(language.text(saveState == .saving ? "Saving…" : "Save DEXA results"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(APEXColor.violet)
                .frame(minHeight: 50)
                .disabled(!dexaIsReady || saveState == .saving)
                .accessibilityIdentifier("calibration.result.save-dexa")

                if saveState == .failed {
                    Text(language.text("Enter at least one valid value and name the report or clinic."))
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var otherResult: some View {
        VStack(alignment: .leading, spacing: 16) {
            resultHeader(
                eyebrow: "RECENT RESULT",
                title: "Add another result",
                detail: "Manual entries stay low-confidence until a supported source confirms them."
            )

            if saveState == .saved {
                savedResultPanel
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(language.text("Result type")).font(APEXFont.body(12, weight: .bold))
                    Picker(language.text("Result type"), selection: $resultMetric) {
                        ForEach(ManualCalibrationMetric.allCases) { metric in
                            Text(language.text(metric.title)).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .padding(.horizontal, 13)
                    .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }

                resultField(
                    label: "Value",
                    text: $resultValue,
                    placeholder: resultMetric.placeholder,
                    unit: resultMetric.unitLabel,
                    focus: .value,
                    identifier: "calibration.result.value"
                )
                sourceAndDate

                Button {
                    focusedField = nil
                    Task { await saveOtherResult() }
                } label: {
                    Text(language.text(saveState == .saving ? "Saving…" : "Save result"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(APEXColor.violet)
                .frame(minHeight: 50)
                .disabled(parsedResultValue == nil || resultSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saveState == .saving)

                if saveState == .failed {
                    Text(language.text("Check the value and source, then try again."))
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.danger)
                }
            }
        }
    }

    private var sourceAndDate: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(language.text("Report or clinic"))
                    .font(APEXFont.body(12, weight: .bold))
                TextField(language.text("For example, DEXA report or laboratory test"), text: $resultSource)
                    .textInputAutocapitalization(.sentences)
                    .focused($focusedField, equals: .source)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .accessibilityIdentifier("calibration.result.source")
            }
            DatePicker(
                language.text("Measured on"),
                selection: $resultDate,
                in: ...Date.now,
                displayedComponents: .date
            )
            .font(APEXFont.body(13, weight: .bold))
        }
    }

    private var savedResultPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(APEXColor.green, in: Circle())
            Text(language.text("Saved to your evidence"))
                .font(APEXFont.display(23))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(savedResultSummaries.enumerated()), id: \.offset) { index, summary in
                Text(summary)
                    .font(APEXFont.body(13, weight: .bold))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("calibration.result.saved-item-\(index)")
            }
            Text(language.text("You can close this screen. These values are now part of your private evidence history."))
                .font(APEXFont.body(12, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(language.text("Add another")) { resetResultFlow() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 46)
                Button(language.text("Done")) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(APEXColor.green)
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
        }
        .padding(18)
        .background(APEXColor.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calibration.result.saved")
    }

    private var savedEvidencePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(language.text("Saved to your evidence"), systemImage: "checkmark.seal.fill")
                .font(APEXFont.body(15, weight: .bold))
                .foregroundStyle(APEXColor.green)
            Button(language.text("Done")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(APEXColor.green)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .padding(17)
        .background(APEXColor.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var health: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(language.text("Apple Health"))
                .font(APEXFont.display(29))
            Text(language.text("You choose what APEX can read. Denial or missing data never lowers your baseline, and manual calibration always remains available."))
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

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
                    .frame(width: 48, height: 48)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text(title))
                        .font(APEXFont.body(15, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
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
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func answerButton(
        answer: BaselineCalibrationAnswer,
        title: String,
        question: BaselineCalibrationQuestion,
        muted: Bool
    ) -> some View {
        let selected = questionIsAnswered && selectedAnswer == answer
        return Button {
            draft.setAnswer(answer, for: question)
            saveState = .idle
            persistDraft()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                Text(language.text(title))
                    .font(APEXFont.body(14, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : (muted ? APEXColor.secondaryInk : APEXColor.ink))
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                selected ? AnyShapeStyle(APEXColor.green) : AnyShapeStyle(.white.opacity(muted ? 0.58 : 0.84)),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(muted && !selected ? APEXColor.secondaryInk.opacity(0.22) : .white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("calibration.answer.\(answer.rawValue)")
    }

    private func bandTile(_ title: String, _ band: OnboardingBaselineBand) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text(title))
                .font(APEXFont.body(12, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
            Text(language.text(band.title))
                .font(APEXFont.body(14, weight: .bold))
                .foregroundStyle(band == .buildingBaseline ? APEXColor.secondaryInk : APEXColor.green)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func resultHeader(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(eyebrow))
                .font(APEXFont.mono(10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(APEXColor.violet)
            Text(language.text(title))
                .font(APEXFont.display(29))
                .fixedSize(horizontal: false, vertical: true)
            Text(language.text(detail))
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resultField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        unit: String,
        focus: ResultField,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(label))
                .font(APEXFont.body(12, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: focus)
                    .accessibilityIdentifier(identifier)
                Text(language.text(unit))
                    .font(APEXFont.mono(11, weight: .bold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }

    private var currentQuestion: BaselineCalibrationQuestion {
        BaselineCalibrationQuestionBank.all[max(0, min(11, draft.step - 1))]
    }

    private var selectedAnswer: BaselineCalibrationAnswer {
        let values = draft.answers.values(for: currentQuestion.domain)
        return BaselineCalibrationAnswer(rawValue: values[currentQuestion.answerIndex]) ?? .notTested
    }

    private var questionIsAnswered: Bool {
        draft.isAnswered(currentQuestion.id)
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

    private func optionalNumber(_ text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return .some(value)
    }

    private var dexaIsReady: Bool {
        guard let bodyFat = optionalNumber(dxaBodyFat),
              let restingEnergy = optionalNumber(dxaRestingEnergy) else { return false }
        return (bodyFat != nil || restingEnergy != nil)
            && !resultSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func navigateBack() {
        focusedField = nil
        if route == .recentResult, resultRoute != .chooser, saveState != .saved {
            resultRoute = .chooser
        } else {
            route = .home
        }
    }

    private func resetResultFlow() {
        saveState = .idle
        resultRoute = .chooser
        resultValue = ""
        dxaBodyFat = ""
        dxaRestingEnergy = ""
        resultSource = ""
        resultDate = .now
        savedResultSummaries = []
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
            UIAccessibility.post(notification: .announcement, argument: language.text("Saved to your evidence"))
        } catch {
            persistDraft()
            saveState = .failed
        }
    }

    @MainActor
    private func saveDEXAResult() async {
        guard let bodyFat = optionalNumber(dxaBodyFat),
              let restingEnergy = optionalNumber(dxaRestingEnergy) else {
            saveState = .failed
            return
        }
        saveState = .saving
        do {
            _ = try await session.saveManualDEXACalibrationResult(
                bodyFatPercentage: bodyFat,
                restingMetabolicRate: restingEnergy,
                declaredSource: resultSource,
                measuredAt: resultDate
            )
            savedResultSummaries = [
                bodyFat.map { "\(language.text("Body fat")) · \($0.formatted(.number.precision(.fractionLength(0...1))))%" },
                restingEnergy.map { "\(language.text("Resting energy (BMR/RMR)")) · \($0.formatted(.number.precision(.fractionLength(0)))) \(language.text("kcal/day"))" },
            ].compactMap { $0 }
            saveState = .saved
            UIAccessibility.post(notification: .announcement, argument: language.text("DEXA results saved"))
        } catch {
            saveState = .failed
        }
    }

    @MainActor
    private func saveOtherResult() async {
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
            savedResultSummaries = [
                "\(language.text(resultMetric.title)) · \(value.formatted(.number.precision(.fractionLength(0...1)))) \(language.text(resultMetric.unitLabel))"
            ]
            saveState = .saved
            UIAccessibility.post(notification: .announcement, argument: language.text("Result saved"))
        } catch {
            saveState = .failed
        }
    }
}

private enum ManualCalibrationMetric: String, CaseIterable, Identifiable {
    case restingEnergy, vo2Max, restingHeartRate, waist
    var id: String { rawValue }

    var title: String {
        switch self {
        case .restingEnergy: "Resting energy (BMR/RMR)"
        case .vo2Max: "VO₂ max"
        case .restingHeartRate: "Resting heart rate"
        case .waist: "Waist circumference"
        }
    }

    var metric: FitnessEvidenceMetric {
        switch self {
        case .restingEnergy: .restingMetabolicRate
        case .vo2Max: .vo2Max
        case .restingHeartRate: .restingHeartRate
        case .waist: .waistCircumference
        }
    }

    var unit: String {
        switch self {
        case .restingEnergy: "kcal_per_day"
        case .vo2Max: "ml_per_kg_min"
        case .restingHeartRate: "bpm"
        case .waist: "cm"
        }
    }

    var unitLabel: String {
        switch self {
        case .restingEnergy: "kcal/day"
        case .vo2Max: "ml/kg/min"
        case .restingHeartRate: "bpm"
        case .waist: "cm"
        }
    }

    var placeholder: String {
        switch self {
        case .restingEnergy: "1683"
        case .vo2Max: "42.5"
        case .restingHeartRate: "58"
        case .waist: "82"
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
