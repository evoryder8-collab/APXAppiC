import SwiftUI

/// What a new account is asked before anything is generated for it.
///
/// Nine short steps, one per screen, because a single long form is where people
/// give up. Only what changes the plan is asked: nothing here is collected
/// because it would be nice to have.
struct InductionView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = LanguageState.shared
    @State private var step = 0
    @State private var input: TrainingInduction.Input = {
        var value = TrainingInduction.Input(startDate: Date().apexDateKey)
        value.goal = ""
        return value
    }()
    @State private var termsAccepted = false
    @State private var privacyAccepted = false
    @State private var baselineSex = ""
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var birthDayText = ""
    @State private var birthMonthText = ""
    @State private var birthYearText = ""
    @State private var legalDocument: OnboardingLegalDocument?
    @State private var showDeclineExplanation = false
    @FocusState private var baselineField: BaselineField?
    @State private var pendingHighFrequencyDays: Int?
    /* Drives the per-question entrance. Keyed on the step so each question
       assembles itself rather than the whole screen blinking. */
    @State private var shown = false

    private let stepCount = 9

    var body: some View {
        ZStack {
            AuroraField(animated: !reduceMotion)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                progress
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        InductionIllustration(step: step)
                            .rise(shown, delay: 0)
                        Text(title)
                            .font(APEXFont.display(26))
                            .fixedSize(horizontal: false, vertical: true)
                            .rise(shown, delay: 0.02)
                        if let subtitle {
                            Text(subtitle)
                                .font(APEXFont.body(13))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .rise(shown, delay: 0.08)
                        }
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                footer
            }
        }
        .onAppear { shown = true }
        .onChange(of: step) { _, _ in
            /* Off, then on again, so the incoming question runs the same
               staggered entrance the first one did. */
            shown = false
            withAnimation(.smooth(duration: 0.5)) { shown = true }
        }
        .sheet(item: $legalDocument) { document in
            OnboardingLegalDocumentView(document: document)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button(language.text("Previous")) { moveBaselineFocus(by: -1) }
                    .disabled(baselineField == .weight)
                    .accessibilityIdentifier("induction-baseline-keyboard-previous")
                Spacer()
                Button(language.text(baselineField == .birthYear ? "Done" : "Next")) {
                    moveBaselineFocus(by: 1)
                }
                .accessibilityIdentifier("induction-baseline-keyboard-next")
            }
        }
        .alert(
            language.text(
                pendingHighFrequencyDays
                    .flatMap(TrainingInduction.highFrequencyAdvisory(for:))?.title
                    ?? ""
            ),
            isPresented: Binding(
                get: { pendingHighFrequencyDays != nil },
                set: { if !$0 { pendingHighFrequencyDays = nil } }
            )
        ) {
            Button(language.text("Continue")) { pendingHighFrequencyDays = nil }
        } message: {
            if let advisory = pendingHighFrequencyDays.flatMap(TrainingInduction.highFrequencyAdvisory(for:)) {
                Text(
                    ([advisory.summary] + advisory.adaptations + advisory.recoveryTips + [advisory.disclaimer])
                        .map(language.text)
                        .joined(separator: "\n\n")
                )
            }
        }
    }

    // MARK: - Chrome

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(
                        index <= step
                            ? AnyShapeStyle(LinearGradient(
                                colors: [APEXColor.violet, APEXColor.cyan],
                                startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(0.55))
                    )
                    .frame(height: 4)
                    .animation(.smooth(duration: 0.45), value: step)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if step > 0 {
                    Button(language.text(.back)) {
                        withAnimation(.snappy) { step -= 1 }
                    }
                    .font(APEXFont.body(15, weight: .semibold))
                    .buttonStyle(.plain)
                    .disabled(session.isBusy)
                }
                Spacer()
                Button {
                    if step == 0 {
                        input.dataConsent = TrainingInduction.DataConsent(
                            termsVersion: TrainingInduction.currentTermsVersion,
                            privacyVersion: TrainingInduction.currentPrivacyVersion,
                            acceptedAt: Date().ISO8601Format()
                        )
                        withAnimation(.snappy) { step += 1 }
                    } else if step == 1, let bodyBaseline {
                        input.bodyBaseline = bodyBaseline
                        baselineField = nil
                        withAnimation(.snappy) { step += 1 }
                    } else if step == stepCount - 1 {
                        Task { await session.completeInduction(input) }
                    } else {
                        withAnimation(.snappy) { step += 1 }
                    }
                } label: {
                    HStack {
                        Text(language.text(step == stepCount - 1 ? "Build my plan" : "Continue"))
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(APEXPrimaryButtonStyle())
                .frame(maxWidth: 220)
                .disabled(session.isBusy || !canContinue)
                .accessibilityIdentifier("induction-next")
            }

            if TrainingInduction.canSkipRemaining(step: step, input: input) {
                Button(language.text("Skip Questionnaire"), action: skip)
                    .font(APEXFont.body(14, weight: .semibold))
                    .frame(minWidth: 88, minHeight: 44)
                    .buttonStyle(.plain)
                    .disabled(session.isBusy)
                    .accessibilityIdentifier("induction-skip")
            }
        }
        .padding(22)
    }

    private func skip() {
        Task { await session.skipRemainingInduction(input) }
    }

    private var canContinue: Bool {
        switch step {
        case 0: termsAccepted && privacyAccepted
        case 1: bodyBaseline?.isValid == true
        case 2: ["general", "muscle", "fat_loss", "strength", "endurance"].contains(input.goal)
        default: true
        }
    }

    // MARK: - Questions

    private var title: String {
        switch step {
        case 0: language.text("Your data. Your decision.")
        case 1: language.text("Build your starting point")
        case 2: language.text("What are you training for?")
        case 3: language.text("When did you last train regularly?")
        case 4: language.text("Where will you train?")
        case 5: language.text("What do you have to train with?")
        case 6: language.text("How many days a week?")
        case 7: language.text("How long should your plan be?")
        default: language.text("Anything we should work around?")
        }
    }

    private var subtitle: String? {
        switch step {
        case 0: language.text("APEX needs clear permission before it processes body, nutrition or training data.")
        case 1: language.text("These measured facts calculate your starting calories and macros. You can change them later.")
        case 3: language.text("A long gap is not a problem. It only changes where we start.")
        case 6: language.text("Pick what you will actually do on a busy week, not your best one.")
        case 7: language.text("Choose a realistic horizon. APEX gives the plan a real end date instead of repeating it forever.")
        case 8: language.text("This decides what gets left out. Nothing here is shared with anyone.")
        default: nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            dataConsent
        case 1:
            bodyDetails
        case 2:
            choices(
                [("general", "General fitness"), ("muscle", "Build muscle"),
                 ("fat_loss", "Lose fat"), ("strength", "Get stronger"),
                 ("endurance", "Build endurance")],
                selection: $input.goal
            )
        case 3:
            choices(
                [("under_three_months", "I train now, or stopped recently"),
                 ("three_to_six_months", "Three to six months ago"),
                 ("six_to_twelve_months", "Six to twelve months ago"),
                 ("over_one_year", "Over a year ago")],
                selection: $input.inactivity
            )
        case 4:
            choices(
                [("gym", "A gym"), ("home", "At home"), ("outdoors", "Outdoors")],
                selection: $input.venue
            )
        case 5:
            equipment
        case 6:
            sessions
        case 7:
            duration
        default:
            health
        }
    }

    private func choices(
        _ options: [(String, String)],
        selection: Binding<String>
    ) -> some View {
        VStack(spacing: 9) {
            ForEach(Array(options.enumerated()), id: \.element.0) { position, option in
                selectRow(
                    label: language.text(option.1),
                    selected: selection.wrappedValue == option.0,
                    index: position
                ) {
                    selection.wrappedValue = option.0
                }
                .accessibilityIdentifier("induction-choice-\(option.0)")
            }
        }
    }

    private var dataConsent: some View {
        VStack(spacing: 12) {
            GlassCard(radius: 24, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(language.text("Swiss-first privacy"), systemImage: "lock.shield.fill")
                        .font(APEXFont.body(17, weight: .bold))
                        .foregroundStyle(APEXColor.violet)
                    Text(language.text("APEX uses the account, body, nutrition and training data you provide to calculate, save and sync your experience. Health data is treated as sensitive data. APEX does not sell it."))
                        .font(APEXFont.body(13))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    consentRow(
                        title: language.text("I accept the Terms of Use"),
                        isAccepted: $termsAccepted,
                        identifier: "induction-terms-consent"
                    )
                    consentRow(
                        title: language.text("I explicitly consent to the processing of my health and fitness data described in the Privacy Policy"),
                        isAccepted: $privacyAccepted,
                        identifier: "induction-privacy-consent"
                    )

                    HStack(spacing: 18) {
                        Button(language.text("Read Terms")) { legalDocument = .terms }
                        Button(language.text("Read Privacy Policy")) { legalDocument = .privacy }
                    }
                    .font(APEXFont.body(13, weight: .bold))
                    .foregroundStyle(APEXColor.violet)
                }
            }

            Text(language.text("Without both permissions APEX cannot create a personalised fitness profile. Optional Apple Health and notification access are requested separately later."))
                .font(APEXFont.body(12))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button(language.text("I don't accept")) { showDeclineExplanation = true }
                .font(APEXFont.body(13, weight: .semibold))
                .frame(minHeight: 44)
                .buttonStyle(.plain)
                .alert(language.text("APEX cannot personalise without permission"), isPresented: $showDeclineExplanation) {
                    Button(language.text("Review consent"), role: .cancel) {}
                } message: {
                    Text(language.text("You can leave setup without sharing these details. A personalised plan, calories and macros require the measurements and goal you choose to provide."))
                }
        }
    }

    private func consentRow(
        title: String,
        isAccepted: Binding<Bool>,
        identifier: String
    ) -> some View {
        Button {
            isAccepted.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isAccepted.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isAccepted.wrappedValue ? APEXColor.green : APEXColor.secondaryInk)
                Text(title)
                    .font(APEXFont.body(14, weight: .semibold))
                    .foregroundStyle(APEXColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var bodyDetails: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(language.text("Metabolic equation"))
                .font(APEXFont.body(13, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
            HStack(spacing: 10) {
                baselineSexChoice(value: "female", label: language.text("Female"))
                baselineSexChoice(value: "male", label: language.text("Male"))
            }

            baselineInput(
                label: language.text("Current weight"),
                placeholder: "70.0",
                unit: "kg",
                text: $weightText,
                field: .weight,
                keyboard: .decimalPad
            )
            baselineInput(
                label: language.text("Height"),
                placeholder: "175",
                unit: "cm",
                text: $heightText,
                field: .height,
                keyboard: .decimalPad
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(language.text("Date of birth"))
                    .font(APEXFont.body(13, weight: .bold))
                    .foregroundStyle(APEXColor.secondaryInk)
                HStack(spacing: 9) {
                    datePartField(language.text("DD"), text: $birthDayText, field: .birthDay, width: 70)
                    datePartField(language.text("MM"), text: $birthMonthText, field: .birthMonth, width: 70)
                    datePartField(language.text("YYYY"), text: $birthYearText, field: .birthYear, width: 104)
                    Spacer(minLength: 0)
                }
            }
            .padding(15)
            .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18))

            if hasStartedBodyEntry && bodyBaseline == nil {
                Label(language.text("Enter a valid weight, height and date of birth."), systemImage: "info.circle")
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.amberDeep)
            }

            Text(language.text("APEX derives age from your birthdate so it stays accurate. These facts initialise nutrition; they never become public profile text."))
                .font(APEXFont.body(12))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func baselineSexChoice(value: String, label: String) -> some View {
        Button {
            baselineSex = value
        } label: {
            HStack {
                Text(label).font(APEXFont.body(15, weight: .bold))
                Spacer()
                Image(systemName: baselineSex == value ? "checkmark.circle.fill" : "circle")
            }
            .foregroundStyle(baselineSex == value ? APEXColor.violet : APEXColor.ink)
            .padding(15)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("induction-baseline-sex-\(value)")
    }

    private func baselineInput(
        label: String,
        placeholder: String,
        unit: String,
        text: Binding<String>,
        field: BaselineField,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(APEXFont.body(14, weight: .bold))
            Spacer(minLength: 8)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(APEXFont.mono(17, weight: .bold))
                .frame(width: 84)
                .focused($baselineField, equals: field)
                .accessibilityIdentifier("induction-baseline-\(field.rawValue)")
            Text(unit)
                .font(APEXFont.mono(13, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
        }
        .padding(15)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18))
    }

    private func datePartField(
        _ placeholder: String,
        text: Binding<String>,
        field: BaselineField,
        width: CGFloat
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(APEXFont.mono(16, weight: .bold))
            .padding(.vertical, 11)
            .frame(width: width)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 13))
            .focused($baselineField, equals: field)
            .accessibilityIdentifier("induction-baseline-\(field.rawValue)")
    }

    private var hasStartedBodyEntry: Bool {
        !baselineSex.isEmpty || !weightText.isEmpty || !heightText.isEmpty ||
            !birthDayText.isEmpty || !birthMonthText.isEmpty || !birthYearText.isEmpty
    }

    private func moveBaselineFocus(by offset: Int) {
        guard let current = baselineField,
              let index = BaselineField.allCases.firstIndex(of: current)
        else {
            baselineField = nil
            return
        }
        let destination = index + offset
        guard BaselineField.allCases.indices.contains(destination) else {
            baselineField = nil
            return
        }
        baselineField = BaselineField.allCases[destination]
    }

    private var bodyBaseline: TrainingInduction.BodyBaseline? {
        guard let weight = Double(weightText.replacingOccurrences(of: ",", with: ".")),
              let height = Double(heightText.replacingOccurrences(of: ",", with: ".")),
              let day = Int(birthDayText),
              let month = Int(birthMonthText),
              let year = Int(birthYearText)
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(calendar: calendar, year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day
        else { return nil }

        let baseline = TrainingInduction.BodyBaseline(
            sex: baselineSex,
            weightKG: weight,
            heightCM: height,
            birthdate: String(format: "%04d-%02d-%02d", year, month, day)
        )
        return baseline.isValid ? baseline : nil
    }

    private var equipment: some View {
        VStack(spacing: 9) {
            ForEach(Array(TrainingInduction.equipmentCatalog.enumerated()), id: \.element.id) { position, option in
                selectRow(
                    label: language.text(option.label),
                    selected: input.equipment.contains(option.id),
                    index: position
                ) {
                    if let index = input.equipment.firstIndex(of: option.id) {
                        input.equipment.remove(at: index)
                    } else {
                        input.equipment.append(option.id)
                    }
                }
            }
        }
    }

    private var sessions: some View {
        VStack(spacing: 9) {
            ForEach(Array((2...7).enumerated()), id: \.element) { position, count in
                selectRow(
                    label: language.format("%d days a week", count),
                    selected: input.sessionsPerWeek == count,
                    index: position
                ) {
                    input.sessionsPerWeek = count
                    if TrainingInduction.highFrequencyAdvisory(for: count) != nil {
                        pendingHighFrequencyDays = count
                    }
                }
            }
        }
    }

    private var duration: some View {
        VStack(spacing: 9) {
            ForEach(Array(TrainingInduction.supportedPlanWeeks.enumerated()), id: \.element) { position, weeks in
                selectRow(
                    label: weeks == 26 ? language.text("6 months") : language.format("%d weeks", weeks),
                    selected: input.planWeeks == weeks,
                    index: position
                ) {
                    input.planWeeks = weeks
                }
                .accessibilityIdentifier("induction-duration-\(weeks)")
            }
        }
    }

    private var health: some View {
        VStack(spacing: 9) {
            toggleRow(
                label: language.text("I have had an operation in the last six months"),
                isOn: $input.recentOperation
            )
            toggleRow(
                label: language.text("I have ongoing lower-back pain"),
                isOn: $input.chronicLowerBackPain
            )
            Text(language.text("Any joints currently sore?"))
                .font(APEXFont.body(13, weight: .semibold))
                .padding(.top, 6)
            ForEach(Array(["knee", "shoulder", "elbow", "hip", "ankle", "wrist"].enumerated()), id: \.element) { position, area in
                selectRow(
                    label: language.text(area.capitalized),
                    selected: input.painAreas.contains(area),
                    index: position + 2
                ) {
                    if let index = input.painAreas.firstIndex(of: area) {
                        input.painAreas.remove(at: index)
                    } else {
                        input.painAreas.append(area)
                    }
                }
            }
            selectRow(
                label: language.text("None"),
                selected: !input.hasHealthConcerns,
                index: 8
            ) {
                input.clearHealthConcerns()
            }
            .accessibilityIdentifier("induction-health-none")
        }
    }

    // MARK: - Rows

    private func selectRow(
        label: String,
        selected: Bool,
        index: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            /* A small haptic on every answer. It is the cheapest thing that
               makes a form feel like a device rather than a web page. */
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            HStack {
                Text(label)
                    .font(APEXFont.body(15, weight: selected ? .bold : .regular))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(selected ? APEXColor.violet : APEXColor.secondaryInk.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? AnyShapeStyle(APEXColor.violet.opacity(0.14))
                                   : AnyShapeStyle(.ultraThinMaterial.opacity(0.95)))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        selected ? APEXColor.violet.opacity(0.55) : .white.opacity(0.85),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
            .shadow(
                color: selected ? APEXColor.violet.opacity(0.22) : .black.opacity(0.05),
                radius: selected ? 16 : 9,
                y: selected ? 7 : 4
            )
            .scaleEffect(selected ? 1.015 : 1)
        }
        .buttonStyle(PressShrink())
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: selected)
        .rise(shown, delay: 0.14 + Double(index) * 0.035)
        /* Each card drifts on its own phase, so the list breathes instead of
           sitting flat on the glass. */
        .floating(index: index, active: !reduceMotion)
    }

    private func toggleRow(label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(APEXFont.body(15))
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(APEXColor.violet)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }
}

private enum BaselineField: String, Hashable, CaseIterable {
    case weight, height, birthDay, birthMonth, birthYear
}

private enum OnboardingLegalDocument: String, Identifiable {
    case terms, privacy
    var id: String { rawValue }
}

private struct OnboardingLegalDocumentView: View {
    let document: OnboardingLegalDocument
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(
                        language.text(document == .terms ? "Terms of Use" : "Privacy Policy"),
                        systemImage: document == .terms ? "doc.text.fill" : "lock.shield.fill"
                    )
                    .font(APEXFont.display(27))
                    .foregroundStyle(APEXColor.ink)

                    Text(language.text("Effective 27 August 2026 · Beta edition"))
                        .font(APEXFont.mono(11))
                        .foregroundStyle(APEXColor.secondaryInk)

                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        GlassCard(radius: 22, padding: 17) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(language.text(section.title))
                                    .font(APEXFont.body(16, weight: .bold))
                                Text(language.text(section.body))
                                    .font(APEXFont.body(13))
                                    .foregroundStyle(APEXColor.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if document == .privacy,
                       let url = URL(string: "https://www.edoeb.admin.ch/en/duty-to-provide-information") {
                        Link(destination: url) {
                            Label(language.text("Swiss FDPIC transparency guidance"), systemImage: "arrow.up.right.square")
                                .font(APEXFont.body(13, weight: .bold))
                        }
                    }
                }
                .padding(22)
            }
            .background(AuroraField(animated: false).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.text("Done")) { dismiss() }
                        .font(APEXFont.body(15, weight: .bold))
                }
            }
        }
    }

    private var sections: [(title: String, body: String)] {
        switch document {
        case .terms:
            [
                ("What APEX is", "APEX is a fitness and nutrition planning tool. It is not medical diagnosis or emergency care, and it does not replace advice from a qualified clinician."),
                ("Safe use", "Use honest inputs, follow exercise setup and stop rules, and stop immediately for sharp, escalating or unusual symptoms. Contact emergency services when symptoms may be urgent."),
                ("Your account", "Keep sign-in details secure. You are responsible for entries and edits made through your account. Beta features may change as reliability and safety improve."),
                ("Availability and law", "APEX aims to preserve and sync your records but cannot promise uninterrupted beta availability. Swiss law applies, without limiting mandatory consumer rights where you live."),
            ]
        case .privacy:
            [
                ("What is collected", "Account identifiers plus the body, nutrition, hydration, activity and training facts you choose to enter. Apple Health is accessed only after its separate system permission."),
                ("Why it is used", "To calculate your targets, generate and adapt plans, show progress, sync your account and protect the service. Data is not sold or used for third-party advertising."),
                ("Who helps operate APEX", "Contracted infrastructure providers may process only the data needed for authentication, storage, sync and purchases. Processing outside Switzerland must use applicable safeguards."),
                ("Your control", "You can correct entries, revoke Apple Health access, export records and request account deletion. Withdrawing consent stops future optional processing but cannot undo processing already required to deliver your request."),
                ("Privacy by default", "Only data needed for the feature is requested. Optional permissions remain off until you choose them, and health or fitness data is never made a public profile by default."),
            ]
        }
    }
}

/// A native vector illustration keeps every question immediately legible,
/// scales cleanly for Dynamic Type, and avoids the synthetic-photo look that
/// does not belong in the product's editorial language.
private struct InductionIllustration: View {
    let step: Int

    private var symbols: (primary: String, secondary: String) {
        switch step {
        case 0: ("lock.shield.fill", "hand.raised.fill")
        case 1: ("figure.stand", "heart.text.square.fill")
        case 2: ("scope", "figure.run")
        case 3: ("clock.arrow.circlepath", "figure.walk")
        case 4: ("house.fill", "location.fill")
        case 5: ("dumbbell.fill", "checkmark.seal.fill")
        case 6: ("calendar", "figure.strengthtraining.traditional")
        case 7: ("calendar.badge.clock", "flag.checkered")
        default: ("figure.arms.open", "cross.case.fill")
        }
    }

    private var accent: Color {
        switch step {
        case 0, 2, 7: APEXColor.violet
        case 1, 3, 6: APEXColor.cyan
        case 4: APEXColor.green
        case 5: APEXColor.amberDeep
        default: .red
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)

            Circle()
                .fill(accent.opacity(0.16))
                .frame(width: 164, height: 164)
                .offset(x: -88, y: 35)
                .blur(radius: 2)

            Circle()
                .fill(APEXColor.teal.opacity(0.15))
                .frame(width: 136, height: 136)
                .offset(x: 112, y: -43)
                .blur(radius: 3)

            HStack(spacing: 26) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.76))
                        .frame(width: 92, height: 92)
                        .shadow(color: accent.opacity(0.18), radius: 20, y: 9)
                    Image(systemName: symbols.primary)
                        .font(.system(size: 42, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)

                    if step == 8 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 9, height: 9)
                            .shadow(color: .red.opacity(0.65), radius: 7)
                            .offset(x: 20, y: -4)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 9, height: 9)
                            .shadow(color: .red.opacity(0.65), radius: 7)
                            .offset(x: -11, y: 29)
                    }
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.68))
                        .frame(width: 72, height: 72)
                    Image(systemName: symbols.secondary)
                        .font(.system(size: 29, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(APEXColor.violet)
                }
                .rotationEffect(.degrees(-6))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 136, maxHeight: 136)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.82), lineWidth: 1)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
