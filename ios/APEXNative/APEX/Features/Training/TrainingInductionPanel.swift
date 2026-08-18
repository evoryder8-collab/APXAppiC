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
    @State private var confirmReplace = false
    @State private var draft = TrainingInduction.Input(startDate: Date().apexDateKey)

    private var current: [String: JSONValue]? {
        session.data.settings?.addons["training_induction"]?.objectValue
    }

    private var assessment: TrainingInduction.Assessment { TrainingInduction.assess(draft) }

    /// Installing over an established programme hides it, so that case is
    /// confirmed rather than performed silently.
    private var replacingExistingPlan: Bool {
        !session.data.programDays.isEmpty && current == nil
    }

    var body: some View {
        GlassCard(radius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("BUILD YOUR OWN PLAN"))
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(APEXColor.violet)
                Text(language.text(slug == "main" ? "Your personal main phase" : "Your 12-week foundation"))
                    .font(APEXFont.display(21))
                Text(language.text(current == nil
                    ? "Answer a few questions and APEX writes a starting programme around your equipment, your recovery and the days you can train."
                    : "Your generated plan is active. Rebuild it any time, or restore your original programme from Settings."))
                    .font(APEXFont.body(12, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)

                if let current {
                    HStack(spacing: 7) {
                        chip(current["venue"]?.stringValue == "gym" ? "Gym" : "Home", APEXColor.violet)
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
                    showBuilder = true
                } label: {
                    Text(language.text(current == nil ? "Build my plan" : "Rebuild my plan"))
                        .font(APEXFont.body(14, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("induction-open")

                if current != nil {
                    Button {
                        Task { await session.restoreOriginalProgramme() }
                    } label: {
                        Text(language.text("Restore my original programme"))
                            .font(APEXFont.body(12, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("induction-restore")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showBuilder) {
            builder
        }
        .alert(
            language.text("This installs a generated beginner plan and shows it instead of your current programme. Your existing programme is kept and returns from Settings, Restore my original programme. Continue?"),
            isPresented: $confirmReplace
        ) {
            Button(language.text("Install the plan"), role: .destructive) { install() }
            Button(language.text("Cancel"), role: .cancel) {}
        }
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
        NavigationStack {
            Form {
                Section(language.text("Where you train")) {
                    Picker(language.text("Venue"), selection: $draft.venue) {
                        Text(language.text("Home")).tag("home")
                        Text(language.text("Gym")).tag("gym")
                    }
                    .pickerStyle(.segmented)
                    Picker(language.text("Sessions per week"), selection: $draft.sessionsPerWeek) {
                        ForEach([2, 3, 4], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if draft.venue == "home" {
                    Section(language.text("What you have")) {
                        ForEach(TrainingInduction.equipmentCatalog) { option in
                            Toggle(language.text(option.label), isOn: Binding(
                                get: { draft.equipment.contains(option.id) },
                                set: { on in
                                    if on { draft.equipment.append(option.id) }
                                    else { draft.equipment.removeAll { $0 == option.id } }
                                }
                            ))
                            .font(APEXFont.body(13, weight: .semibold))
                        }
                    }
                }

                Section(language.text("How your body is")) {
                    Picker(language.text("Time since consistent training"), selection: $draft.inactivity) {
                        Text(language.text("Under three months")).tag("under_three_months")
                        Text(language.text("Three to six months")).tag("three_to_six_months")
                        Text(language.text("Six to twelve months")).tag("six_to_twelve_months")
                        Text(language.text("Over a year")).tag("over_one_year")
                    }
                    Toggle(language.text("Recent operation"), isOn: $draft.recentOperation)
                    Toggle(language.text("Chronic lower-back pain"), isOn: $draft.chronicLowerBackPain)
                }

                Section(language.text("What APEX will do")) {
                    Text(language.text(cautionLabel(assessment.caution)))
                        .font(APEXFont.body(14, weight: .bold))
                    ForEach(assessment.reasons, id: \.self) { reason in
                        Text(language.text(reason))
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    Text(language.format("%d sessions a week", assessment.sessionsPerWeek))
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
            }
            .navigationTitle(language.text("Build my plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Cancel")) { showBuilder = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Install")) {
                        showBuilder = false
                        if replacingExistingPlan { confirmReplace = true } else { install() }
                    }
                    .fontWeight(.bold)
                    .accessibilityIdentifier("induction-install")
                }
            }
        }
    }

    private func install() {
        var input = draft
        input.startDate = Date().apexDateKey
        Task { await session.installInductionPlan(input) }
    }
}
