import SwiftUI

/// What a new account is asked before anything is generated for it.
///
/// Six questions, one per screen, because a single long form is where people
/// give up. Only what changes the plan is asked: nothing here is collected
/// because it would be nice to have.
struct InductionView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = LanguageState.shared
    @State private var step = 0
    @State private var input = TrainingInduction.Input(startDate: Date().apexDateKey)
    /* Drives the per-question entrance. Keyed on the step so each question
       assembles itself rather than the whole screen blinking. */
    @State private var shown = false

    private let stepCount = 6

    var body: some View {
        ZStack {
            AuroraField(animated: !reduceMotion)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                progress
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
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
        HStack(spacing: 12) {
            if step > 0 {
                Button(language.text(.back)) {
                    withAnimation(.snappy) { step -= 1 }
                }
                .font(APEXFont.body(15, weight: .semibold))
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                if step == stepCount - 1 {
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
        }
        .padding(22)
    }

    // MARK: - Questions

    private var title: String {
        switch step {
        case 0: language.text("What are you training for?")
        case 1: language.text("When did you last train regularly?")
        case 2: language.text("Where will you train?")
        case 3: language.text("What do you have to train with?")
        case 4: language.text("How many days a week?")
        default: language.text("Anything we should work around?")
        }
    }

    private var subtitle: String? {
        switch step {
        case 1: language.text("A long gap is not a problem. It only changes where we start.")
        case 4: language.text("Pick what you will actually do on a busy week, not your best one.")
        case 5: language.text("This decides what gets left out. Nothing here is shared with anyone.")
        default: nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            choices(
                [("general", "General fitness"), ("muscle", "Build muscle"),
                 ("fat_loss", "Lose fat"), ("strength", "Get stronger"),
                 ("endurance", "Build endurance")],
                selection: $input.goal
            )
        case 1:
            choices(
                [("under_three_months", "I train now, or stopped recently"),
                 ("three_to_six_months", "Three to six months ago"),
                 ("six_to_twelve_months", "Six to twelve months ago"),
                 ("over_one_year", "Over a year ago")],
                selection: $input.inactivity
            )
        case 2:
            choices(
                [("gym", "A gym"), ("home", "At home"), ("outdoors", "Outdoors")],
                selection: $input.venue
            )
        case 3:
            equipment
        case 4:
            sessions
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
            }
        }
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
            ForEach(Array((2...5).enumerated()), id: \.element) { position, count in
                selectRow(
                    label: language.format("%d days a week", count),
                    selected: input.sessionsPerWeek == count,
                    index: position
                ) {
                    input.sessionsPerWeek = count
                }
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
