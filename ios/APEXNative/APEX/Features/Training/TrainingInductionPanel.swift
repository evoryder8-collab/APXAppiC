import SwiftUI

/*
 * Build your own starting plan from a few answers.
 *
 * A port of src/components/workout/TrainingInductionPanel.tsx. Installing the
 * result narrows every calendar to the generated days, so this asks before it
 * does that and says plainly that the original programme is kept.
 */
struct TrainingInductionPanel: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared

    let slug: String

    @State private var showBuilder = false
    @State private var showBriefing = false
    @State private var confirmReplace = false
    @State private var builderStep = 0
    @State private var pendingHighFrequencyDays: Int?
    @State private var draft = TrainingInduction.Input(startDate: Date().apexDateKey)
    @State private var briefing: TrainingInduction.PlanBriefing?

    private var current: [String: JSONValue]? {
        session.data.settings?.addons["training_induction"]?.objectValue
    }

    private var assessment: TrainingInduction.Assessment { TrainingInduction.assess(draft) }

    private var hasActiveGeneratedPlan: Bool {
        TrainingInduction.hasCompleteGeneratedPlan(in: session.data, slug: slug)
    }

    /// Installing over an established programme hides it, so that case is
    /// confirmed rather than performed silently.
    private var replacingExistingPlan: Bool {
        !TrainingInduction.activeProgramDays(in: session.data).isEmpty && current == nil
    }

    var body: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("BUILD YOUR OWN PLAN"))
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(APEXColor.violet)
                Text(language.text(slug == "main" ? "Your personal main phase" : "Your personal training plan"))
                    .font(APEXFont.display(21))
                Text(language.text(hasActiveGeneratedPlan ? "Your generated plan is active. Rebuild it any time, or restore your original programme from Settings."
                    : "Answer a few questions and APEX writes a starting programme around your equipment, your recovery and the days you can train."))
                    .font(APEXFont.body(12, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)

                if hasActiveGeneratedPlan, let current {
                    HStack(spacing: 7) {
                        chip(
                            TrainingInduction.venueDisplayName(
                                for: current["venue"]?.stringValue ?? "home"
                            ),
                            APEXColor.violet
                        )
                        chip(
                            language.format("%d sessions", Int(current["sessions_per_week"]?.numberValue ?? 3)),
                            APEXColor.teal
                        )
                        chip(
                            cautionLabel(current["caution"]?.stringValue ?? "standard"),
                            current["caution"]?.stringValue == "standard" ? APEXColor.green : APEXColor.amberDeep
                        )
                    }
                }

                Button {
                    openBuilder()
                } label: {
                    Text(language.text(hasActiveGeneratedPlan ? "Rebuild my plan" : "Build my plan"))
                        .font(APEXFont.body(14, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(hasActiveGeneratedPlan ? "induction-rebuild" : "induction-open")
                .disabled(session.isBusy)

                if current != nil {
                    Button {
                        openCurrentBriefing()
                    } label: {
                        Text(language.text("Plan guide"))
                            .font(APEXFont.body(12, weight: .bold))
                            .foregroundStyle(APEXColor.violet)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("induction-briefing-open")

                    Button {
                        Task { await session.restoreOriginalProgramme() }
                    } label: {
                        Text(language.text("Restore my original programme"))
                            .font(APEXFont.body(12, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("induction-restore")
                    .disabled(session.isBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showBuilder) {
            builder
        }
        .fullScreenCover(isPresented: $showBriefing) {
            if let briefing {
                PlanBriefingDeck(briefing: briefing) {
                    showBriefing = false
                }
            }
        }
        .alert(
            language.text("This installs a generated beginner plan and shows it instead of your current programme. Your existing programme is kept and returns from Settings, Restore my original programme. Continue?"),
            isPresented: $confirmReplace
        ) {
            Button(language.text("Install the plan"), role: .destructive) { install() }
                .disabled(session.isBusy)
            Button(language.text("Cancel"), role: .cancel) {}
        }
    }

    private func openBuilder() {
        draft = TrainingInduction.input(
            from: current,
            fallbackStartDate: Date().apexDateKey
        )
        builderStep = 0
        pendingHighFrequencyDays = nil
        showBuilder = true
    }

    private func makeBriefing(for input: TrainingInduction.Input) -> TrainingInduction.PlanBriefing {
        let profile = session.profile
        let induction = session.data.settings?.addons["training_induction"]?.objectValue
        let claimedIDs = Set(
            ["transition_day_ids", "main_day_ids"].flatMap { key in
                induction?[key]?.arrayValue?
                    .compactMap(\.stringValue)
                    .compactMap(UUID.init(uuidString:)) ?? []
            }
        )
        let minutes = session.data.programDays
            .filter { claimedIDs.contains($0.id) }
            .map(\.estimatedMinutes)
            .filter { $0 > 0 }
        let plannedMinutes = minutes.isEmpty
            ? 45
            : Int((Double(minutes.reduce(0, +)) / Double(minutes.count)).rounded())
        let preferences = session.hydrationPreferences
        return TrainingInduction.planBriefing(
            input: input,
            caution: TrainingInduction.assess(input).caution,
            sex: profile?.sex ?? "unspecified",
            weightKG: profile?.weightKG ?? .nan,
            plannedExerciseMinutes: plannedMinutes,
            hydrationMode: preferences?.effectiveTargetMode ?? .automatic,
            customHydrationTargetML: preferences?.targetML,
            displayUnit: preferences?.displayUnit ?? "liters"
        )
    }

    private func openCurrentBriefing() {
        let input = TrainingInduction.input(
            from: current,
            fallbackStartDate: Date().apexDateKey
        )
        briefing = makeBriefing(for: input)
        showBriefing = true
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(language.text(text))
            .font(APEXFont.mono(9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func cautionLabel(_ caution: String) -> String {
        switch caution {
        case "clearance": return "Needs clearance"
        case "cautious": return "Cautious start"
        default: return "Standard start"
        }
    }

    private var builder: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    APEXColor.violet.opacity(0.10),
                    APEXColor.teal.opacity(0.08),
                    Color(uiColor: .systemBackground),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                builderHeader
                builderProgress
                ScrollView {
                    builderStepContent
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                builderFooter
            }
        }
        .overlay {
            if let days = pendingHighFrequencyDays {
                highFrequencyAdvisory(days: days)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.snappy(duration: 0.28), value: builderStep)
        .animation(.snappy(duration: 0.24), value: pendingHighFrequencyDays)
        .interactiveDismissDisabled(pendingHighFrequencyDays != nil)
    }

    private var builderHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(language.text("APEX PLAN INTELLIGENCE"))
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(APEXColor.violet)
                Text(language.text("Build your training week"))
                    .font(APEXFont.display(24))
                Text(language.format("Step %d of 5", builderStep + 1))
                    .font(APEXFont.body(12, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            Spacer()
            Button {
                showBuilder = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("Close plan builder"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var builderProgress: some View {
        HStack(spacing: 7) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(index <= builderStep ? APEXColor.violet : APEXColor.violet.opacity(0.14))
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var builderStepContent: some View {
        switch builderStep {
        case 0: goalStep
        case 1: venueAndFrequencyStep
        case 2: equipmentStep
        case 3: durationStep
        default: recoveryAndReviewStep
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(
                eyebrow: "YOUR DIRECTION",
                title: "What should this plan move toward?",
                body: "Choose the outcome that matters most now. You can rebuild the plan when that priority changes."
            )
            ForEach(goalOptions) { option in
                selectionCard(
                    option: option,
                    selected: draft.goal == option.id,
                    accessibilityID: option.accessibilityID ?? "induction-return-goal-\(option.id)"
                ) {
                    draft.goal = option.id
                }
            }
        }
    }

    private var venueAndFrequencyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(
                eyebrow: "TRAINING ENVIRONMENT",
                title: "Where will the work happen?",
                body: "APEX keeps every prescribed movement inside the setup you actually have."
            )
            ForEach(venueOptions) { option in
                selectionCard(
                    option: option,
                    selected: draft.venue == option.id,
                    accessibilityID: option.accessibilityID ?? "induction-return-venue-\(option.id)"
                ) {
                    draft.venue = option.id
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("TRAINING RHYTHM"))
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(APEXColor.teal)
                Text(language.text("Training days per week"))
                    .font(APEXFont.display(21))
                Text(language.text("These are training days, not an unexplained score. Six and seven stay available with a recovery-aware structure."))
                    .font(APEXFont.body(12, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(2...7, id: \.self) { days in
                    frequencyCard(days)
                }
            }
        }
    }

    private var equipmentStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(
                eyebrow: "YOUR EQUIPMENT",
                title: draft.venue == "gym" ? "What do you prefer to use?" : "What can APEX build around?",
                body: draft.venue == "gym"
                    ? "Your gym floor is assumed. Select personal tools you reliably have so the plan can prefer them."
                    : "No equipment is required. Select only what is genuinely available."
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                ForEach(TrainingInduction.equipmentCatalog) { option in
                    equipmentCard(option)
                }
            }

            if draft.equipment.isEmpty {
                Label(
                    language.text("A bodyweight plan will be built. Nothing is being assumed."),
                    systemImage: "figure.strengthtraining.functional"
                )
                .font(APEXFont.body(12, weight: .semibold))
                .foregroundStyle(APEXColor.secondaryInk)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var durationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(
                eyebrow: "PLAN HORIZON",
                title: "How long should your plan be?",
                body: "Choose the period you can commit to. APEX stores a real end date, so the plan cannot repeat forever."
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(TrainingInduction.supportedPlanWeeks, id: \.self) { weeks in
                    durationCard(weeks)
                }
            }
        }
    }

    private var recoveryAndReviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(
                eyebrow: "RECOVERY INPUTS",
                title: "Give the plan an honest starting point",
                body: "These answers lower initial stress when needed. They do not rate your potential."
            )

            Text(language.text("Time since consistent training"))
                .font(APEXFont.body(13, weight: .bold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(inactivityOptions) { option in
                    compactChoice(option, selected: draft.inactivity == option.id) {
                        draft.inactivity = option.id
                    }
                }
            }

            VStack(spacing: 10) {
                recoveryToggle(
                    title: "Recent operation",
                    subtitle: "Loaded work waits for clinician clearance",
                    isOn: $draft.recentOperation
                )
                recoveryToggle(
                    title: "Chronic lower-back pain",
                    subtitle: "Start conservatively and keep ranges pain-free",
                    isOn: $draft.chronicLowerBackPain
                )
            }

            Text(language.text("Current joint discomfort"))
                .font(APEXFont.body(13, weight: .bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(["knee", "shoulder", "elbow", "hip", "ankle", "wrist"], id: \.self) { area in
                    painChoice(area)
                }
            }

            planLogicCard
        }
    }

    private var builderFooter: some View {
        HStack(spacing: 12) {
            if builderStep > 0 {
                Button {
                    builderStep -= 1
                } label: {
                    Text(language.text("Back"))
                        .font(APEXFont.body(14, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
            }

            Button {
                if builderStep < 4 {
                    builderStep += 1
                } else {
                    showBuilder = false
                    if replacingExistingPlan { confirmReplace = true } else { install() }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(language.text(builderStep < 4 ? "Continue" : "Install my plan"))
                    Image(systemName: builderStep < 4 ? "arrow.right" : "sparkles")
                }
                .font(APEXFont.body(14, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(builderStep < 4 ? "induction-next" : "induction-install")
            .disabled(session.isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private func sectionHeading(eyebrow: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(language.text(eyebrow))
                .font(APEXFont.mono(9, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(APEXColor.violet)
            Text(language.text(title))
                .font(APEXFont.display(23))
            Text(language.text(body))
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectionCard(
        option: PlanBuilderOption,
        selected: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: option.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? .white : option.color)
                    .frame(width: 42, height: 42)
                    .background(selected ? option.color : option.color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text(option.title))
                        .font(APEXFont.body(15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(language.text(option.subtitle))
                        .font(APEXFont.body(11, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? option.color : APEXColor.secondaryInk.opacity(0.35))
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 21))
            .overlay {
                RoundedRectangle(cornerRadius: 21)
                    .stroke(selected ? option.color.opacity(0.65) : Color.white.opacity(0.35), lineWidth: selected ? 1.5 : 1)
            }
            .shadow(color: selected ? option.color.opacity(0.14) : .clear, radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue(selected ? "1" : "0")
    }

    private func frequencyCard(_ days: Int) -> some View {
        let selected = draft.sessionsPerWeek == days
        let elevated = days >= 6
        return Button {
            if elevated { pendingHighFrequencyDays = days }
            else { draft.sessionsPerWeek = days }
        } label: {
            VStack(spacing: 3) {
                Text("\(days)")
                    .font(APEXFont.display(25))
                Text(language.text("DAYS / WEEK"))
                    .font(APEXFont.mono(7, weight: .bold))
                    .tracking(0.7)
                if elevated {
                    Text(language.text("RECOVERY PLAN"))
                        .font(APEXFont.mono(6, weight: .bold))
                        .foregroundStyle(APEXColor.amberDeep)
                }
            }
            .foregroundStyle(selected ? APEXColor.violet : .primary)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(selected ? APEXColor.violet.opacity(0.13) : Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(selected ? APEXColor.violet : Color.primary.opacity(0.07), lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.format("%d training days per week", days))
        .accessibilityIdentifier("induction-return-sessions-\(days)")
        .accessibilityValue(selected ? "1" : "0")
    }

    private func durationCard(_ weeks: Int) -> some View {
        let selected = draft.planWeeks == weeks
        let primary = weeks == 26 ? "6" : "\(weeks)"
        let unit = weeks == 26 ? "MONTHS" : "WEEKS"
        return Button {
            draft.planWeeks = weeks
        } label: {
            VStack(spacing: 5) {
                Text(primary)
                    .font(APEXFont.display(31))
                Text(language.text(unit))
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.1)
                Text(language.text(weeks == 12 ? "Balanced foundation" : weeks == 26 ? "Foundation plus main phase" : "Focused foundation"))
                    .font(APEXFont.body(10, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(selected ? APEXColor.violet : .primary)
            .frame(maxWidth: .infinity, minHeight: 126)
            .background(selected ? APEXColor.violet.opacity(0.13) : Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 21))
            .overlay {
                RoundedRectangle(cornerRadius: 21)
                    .stroke(selected ? APEXColor.violet : Color.primary.opacity(0.07), lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weeks == 26 ? language.text("6 months") : language.format("%d weeks", weeks))
        .accessibilityIdentifier("induction-return-duration-\(weeks)")
        .accessibilityValue(selected ? "1" : "0")
    }

    private func equipmentCard(_ option: TrainingInduction.EquipmentOption) -> some View {
        let selected = draft.equipment.contains(option.id)
        let featured = option.id == "weighted_vest" || option.id == "weighted_backpack"
        return Button {
            if selected { draft.equipment.removeAll { $0 == option.id } }
            else { draft.equipment.append(option.id) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: equipmentIcon(option.id))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selected ? .white : APEXColor.teal)
                        .frame(width: 36, height: 36)
                        .background(selected ? APEXColor.teal : APEXColor.teal.opacity(0.12), in: Circle())
                    Spacer()
                    if featured {
                        Text(language.text("HOME LOAD"))
                            .font(APEXFont.mono(6, weight: .bold))
                            .foregroundStyle(APEXColor.violet)
                    }
                }
                Text(language.text(option.label))
                    .font(APEXFont.body(12, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(selected ? APEXColor.teal.opacity(0.11) : Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 19))
            .overlay {
                RoundedRectangle(cornerRadius: 19)
                    .stroke(selected ? APEXColor.teal : Color.primary.opacity(0.07), lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("induction-return-equipment-\(option.id)")
        .accessibilityValue(selected ? "1" : "0")
    }

    private func compactChoice(_ option: PlanBuilderOption, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? APEXColor.violet : APEXColor.secondaryInk.opacity(0.4))
                Text(language.text(option.title))
                    .font(APEXFont.body(11, weight: .bold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(selected ? APEXColor.violet.opacity(0.11) : Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func recoveryToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text(title))
                    .font(APEXFont.body(13, weight: .bold))
                Text(language.text(subtitle))
                    .font(APEXFont.body(10, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(APEXColor.violet)
        }
        .padding(14)
        .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 18))
    }

    private func painChoice(_ area: String) -> some View {
        let selected = draft.painAreas.contains(area)
        return Button {
            if selected { draft.painAreas.removeAll { $0 == area } }
            else { draft.painAreas.append(area) }
        } label: {
            Text(language.text(area.capitalized))
                .font(APEXFont.body(10, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(selected ? APEXColor.violet : .primary)
                .background(selected ? APEXColor.violet.opacity(0.12) : Color.white.opacity(0.54), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("induction-return-pain-\(area)")
        .accessibilityValue(selected ? "1" : "0")
    }

    private var planLogicCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text("YOUR PLAN LOGIC"))
                        .font(APEXFont.mono(8, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(APEXColor.violet)
                    Text(language.text(cautionLabel(assessment.caution)))
                        .font(APEXFont.display(20))
                }
                Spacer()
                Text(language.format("%d days / week", assessment.sessionsPerWeek))
                    .font(APEXFont.mono(9, weight: .bold))
                    .foregroundStyle(APEXColor.teal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(APEXColor.teal.opacity(0.11), in: Capsule())
            }

            if assessment.sessionsPerWeek != draft.sessionsPerWeek {
                Text(language.format("You selected %d days. Your recovery answers currently set the starting plan to %d.", draft.sessionsPerWeek, assessment.sessionsPerWeek))
                    .font(APEXFont.body(11, weight: .semibold))
                    .foregroundStyle(APEXColor.amberDeep)
            }
            Label(
                draft.planWeeks == 26
                    ? language.text("6-month plan")
                    : language.format("%d-week plan", draft.planWeeks),
                systemImage: "calendar.badge.clock"
            )
            .font(APEXFont.body(11, weight: .semibold))
            .foregroundStyle(APEXColor.secondaryInk)
            ForEach(assessment.reasons, id: \.self) { reason in
                Label(language.text(reason), systemImage: "shield.lefthalf.filled")
                    .font(APEXFont.body(11, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            if let advisory = TrainingInduction.highFrequencyAdvisory(for: assessment.sessionsPerWeek) {
                ForEach(advisory.adaptations, id: \.self) { adaptation in
                    Label(language.text(adaptation), systemImage: "checkmark.circle.fill")
                        .font(APEXFont.body(11, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
            }
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [APEXColor.violet.opacity(0.12), APEXColor.teal.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 23)
        )
        .overlay { RoundedRectangle(cornerRadius: 23).stroke(Color.white.opacity(0.5)) }
    }

    @ViewBuilder
    private func highFrequencyAdvisory(days: Int) -> some View {
        if let advisory = TrainingInduction.highFrequencyAdvisory(for: days) {
            ZStack {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "waveform.path.ecg.rectangle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(APEXColor.amberDeep.gradient, in: Circle())
                        Text(language.text(advisory.title))
                            .font(APEXFont.display(25))
                        Text(language.text(advisory.summary))
                            .font(APEXFont.body(13, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)

                        advisoryGroup("HOW APEX ADAPTS", items: advisory.adaptations, icon: "arrow.triangle.2.circlepath")
                        advisoryGroup("RECOVERY ANCHORS", items: advisory.recoveryTips, icon: "heart.text.square.fill")

                        Text(language.text(advisory.disclaimer))
                            .font(APEXFont.body(10, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .padding(12)
                            .background(APEXColor.amberDeep.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))

                        Button {
                            draft.sessionsPerWeek = days
                            pendingHighFrequencyDays = nil
                        } label: {
                            Text(language.format("Use %d training days", days))
                                .font(APEXFont.body(14, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .foregroundStyle(.white)
                                .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("induction-high-frequency-confirm")

                        Button {
                            pendingHighFrequencyDays = nil
                        } label: {
                            Text(language.text("Choose fewer days"))
                                .font(APEXFont.body(13, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("induction-high-frequency-cancel")
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
                    .overlay { RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.62)) }
                    .shadow(color: .black.opacity(0.18), radius: 30, y: 16)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func advisoryGroup(_ title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(language.text(title))
                .font(APEXFont.mono(8, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(APEXColor.violet)
            ForEach(items, id: \.self) { item in
                Label(language.text(item), systemImage: icon)
                    .font(APEXFont.body(11, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
        }
    }

    private func equipmentIcon(_ id: String) -> String {
        switch id {
        case "weighted_vest": "figure.walk.motion"
        case "weighted_backpack": "backpack.fill"
        case "resistance_bands": "arrow.left.and.right"
        case "pullup_bar": "figure.strengthtraining.traditional"
        case "cardio_machine": "figure.run"
        case "mat": "rectangle.fill"
        default: "dumbbell.fill"
        }
    }

    private var goalOptions: [PlanBuilderOption] {
        [
            PlanBuilderOption(id: "general", title: "General fitness", subtitle: "Build a balanced, repeatable training rhythm", icon: "sparkles", color: APEXColor.violet, accessibilityID: "induction-return-goal-general"),
            PlanBuilderOption(id: "muscle", title: "Build muscle", subtitle: "Prioritize progressive resistance work", icon: "figure.strengthtraining.traditional", color: APEXColor.teal, accessibilityID: "induction-return-goal-muscle"),
            PlanBuilderOption(id: "fat_loss", title: "Lose fat", subtitle: "Pair resistance work with sustainable activity", icon: "flame.fill", color: APEXColor.amberDeep, accessibilityID: "induction-return-goal-fat_loss"),
            PlanBuilderOption(id: "strength", title: "Get stronger", subtitle: "Keep load progression prominent and measurable", icon: "bolt.fill", color: APEXColor.green, accessibilityID: "induction-return-goal-strength"),
            PlanBuilderOption(id: "endurance", title: "Build endurance", subtitle: "Give aerobic capacity a clear place in the week", icon: "waveform.path.ecg", color: .pink, accessibilityID: "induction-return-goal-endurance"),
        ]
    }

    private var venueOptions: [PlanBuilderOption] {
        [
            PlanBuilderOption(id: "home", title: "Home", subtitle: "Bodyweight and only the equipment you select", icon: "house.fill", color: APEXColor.violet, accessibilityID: "induction-return-venue-home"),
            PlanBuilderOption(id: "gym", title: "Gym", subtitle: "Machines, cables and free weights available", icon: "building.2.fill", color: APEXColor.teal, accessibilityID: "induction-return-venue-gym"),
            PlanBuilderOption(id: "outdoors", title: "Outdoors", subtitle: "Open-air training with portable equipment", icon: "mountain.2.fill", color: APEXColor.green, accessibilityID: "induction-return-venue-outdoors"),
        ]
    }

    private var inactivityOptions: [PlanBuilderOption] {
        [
            PlanBuilderOption(id: "under_three_months", title: "Under three months", subtitle: "", icon: "", color: APEXColor.violet),
            PlanBuilderOption(id: "three_to_six_months", title: "Three to six months", subtitle: "", icon: "", color: APEXColor.violet),
            PlanBuilderOption(id: "six_to_twelve_months", title: "Six to twelve months", subtitle: "", icon: "", color: APEXColor.violet),
            PlanBuilderOption(id: "over_one_year", title: "Over a year", subtitle: "", icon: "", color: APEXColor.violet),
        ]
    }

    private func install() {
        let submitted = draft
        Task {
            await session.installInductionPlan(submitted)
            guard TrainingInduction.hasCompleteGeneratedPlan(in: session.data, slug: slug) else { return }
            briefing = makeBriefing(for: submitted)
            showBriefing = true
        }
    }
}

private struct PlanBriefingDeck: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var language = LanguageState.shared
    @State private var page = 0
    @State private var firstSlideNudge: CGFloat = 0

    let briefing: TrainingInduction.PlanBriefing
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    APEXColor.violet.opacity(0.14),
                    APEXColor.teal.opacity(0.10),
                    Color(uiColor: .systemBackground),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ForEach(Array(briefing.slides.enumerated()), id: \.element.kind) { index, slide in
                        ScrollView {
                            slideCard(slide)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                        }
                        .scrollIndicators(.hidden)
                        .tag(index)
                        .offset(x: index == 0 ? firstSlideNudge : 0)
                        .accessibilityIdentifier("plan-briefing-slide-\(slide.kind.rawValue)")
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(briefing.slides.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? APEXColor.violet : APEXColor.violet.opacity(0.20))
                            .frame(width: index == page ? 30 : 7, height: 7)
                            .animation(.snappy(duration: 0.2), value: page)
                    }
                }
                .accessibilityLabel(language.format("Slide %d of %d", page + 1, briefing.slides.count))
                .padding(.top, 4)

                Button(action: onClose) {
                    HStack(spacing: 8) {
                        Text(language.text("Open my plan"))
                        Image(systemName: "arrow.right")
                    }
                    .font(APEXFont.body(15, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .accessibilityIdentifier("plan-briefing-done")
            }
        }
        .accessibilityIdentifier("plan-briefing")
        .task {
            guard !accessibilityReduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.easeInOut(duration: 0.28)) { firstSlideNudge = -14 }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut(duration: 0.32)) { firstSlideNudge = 0 }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("APEX PLAN INTELLIGENCE")
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(APEXColor.violet)
                Text(language.text("Your plan briefing"))
                    .font(APEXFont.display(25))
                Text(language.text("Swipe for the full guide"))
                    .font(APEXFont.body(11, weight: .semibold))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("Close plan briefing"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 2)
    }

    private func slideCard(_ slide: TrainingInduction.PlanBriefingSlide) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(slide.assetName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 225)
                .accessibilityHidden(true)
                .shadow(color: APEXColor.violet.opacity(0.14), radius: 24, y: 14)

            Text(language.text(slide.eyebrow))
                .font(APEXFont.mono(9, weight: .bold))
                .tracking(1.7)
                .foregroundStyle(APEXColor.violet)
            Text(language.text(slide.title))
                .font(APEXFont.display(27))
                .fixedSize(horizontal: false, vertical: true)
            Text(language.text(slide.body))
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 9) {
                ForEach(slide.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(APEXColor.violet)
                            .padding(.top, 3)
                        Text(language.text(bullet))
                            .font(APEXFont.body(11, weight: .semibold))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(APEXColor.violet.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
                }
            }

            Text(language.text("Evidence") + " · " + slide.evidence)
                .font(APEXFont.mono(8, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(APEXColor.secondaryInk.opacity(0.72))
                .textCase(.uppercase)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: APEXColor.violet.opacity(0.10), radius: 30, y: 16)
    }
}

private struct PlanBuilderOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var accessibilityID: String? = nil
}
