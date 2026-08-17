import SwiftUI

struct AddActivitySheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let date: Date

    @State private var selectedType: ActivityType?

    private var groups: [(String, [ActivityType])] {
        let order = ["therapy", "camera", "work", "life", "training", "device"]
        let grouped = Dictionary(grouping: session.data.activityTypes, by: \.category)
        return order.compactMap { category in
            guard let rows = grouped[category], !rows.isEmpty else { return nil }
            return (category, rows)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add activity block")
                            .font(APEXFont.display(30))
                        Text("Only add activity beyond the normal daily floor.")
                            .font(APEXFont.body(14, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }

                    ForEach(groups, id: \.0) { category, types in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(language.text(categoryTitle(category)).uppercased(with: language.language.locale))
                                .font(APEXFont.mono(10))
                                .tracking(1.5)
                                .foregroundStyle(APEXColor.secondaryInk)
                            ForEach(types) { type in
                                Button {
                                    selectedType = type
                                } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: systemIcon(type.icon))
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(APEXColor.amberDeep)
                                            .frame(width: 42, height: 42)
                                            .background(APEXColor.amber.opacity(0.12), in: Circle())
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(language.text(type.name))
                                                .font(APEXFont.body(15, weight: .bold))
                                                .foregroundStyle(APEXColor.ink)
                                            Text(language.text(type.notes))
                                                .font(APEXFont.body(11, weight: .medium))
                                                .foregroundStyle(APEXColor.secondaryInk)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(APEXColor.secondaryInk)
                                    }
                                    .padding(13)
                                    .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(APEXBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedType) { type in
                ActivityEntryForm(type: type, date: date) {
                    selectedType = nil
                    dismiss()
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func categoryTitle(_ category: String) -> String {
        switch category {
        case "therapy": "Work: hands-on therapy"
        case "camera": "Work: camera"
        case "work": "Work: general"
        case "life": "Errands & life"
        case "training": "Training"
        case "device": "Device import"
        default: category
        }
    }
}

private struct ActivityEntryForm: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let type: ActivityType
    let date: Date
    let onSaved: () -> Void

    @State private var quantity = 1.0
    @State private var durationMinutes: Int
    @State private var distanceKM = 5.0
    @State private var steps = 1_000.0
    @State private var watchKcal = 0.0

    init(type: ActivityType, date: Date, onSaved: @escaping () -> Void) {
        self.type = type
        self.date = date
        self.onSaved = onSaved
        _durationMinutes = State(initialValue: type.defaultDurationMinutes ?? 60)
    }

    private var preview: Double {
        guard let profile = session.profile else { return 0 }
        return EnergyEngine.blockCalories(
            type: type,
            quantity: type.inputStyle == .steps ? steps : quantity,
            durationMinutes: durationMinutes,
            distanceKM: distanceKM,
            watchKcal: watchKcal > 0 ? watchKcal : nil,
            weightKG: profile.weightKG
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                HStack(spacing: 14) {
                    Image(systemName: systemIcon(type.icon))
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(APEXColor.amber.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text(type.name))
                            .font(APEXFont.display(23))
                        Text(language.text(type.notes))
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(language.format("%d", Int(preview.rounded())))
                        .font(APEXFont.display(48))
                        .foregroundStyle(APEXColor.amberDeep)
                        .contentTransition(.numericText())
                    Text("kcal net")
                        .font(APEXFont.mono(12))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .animation(.snappy, value: preview)

                inputControls

                if type.supportsWatch || type.inputStyle == .watchKcal {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MY WATCH SAYS")
                            .font(APEXFont.mono(10))
                            .tracking(1.2)
                        TextField("kcal", value: $watchKcal, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text("APEX counts 80% because wrist estimates commonly run hot. If distance is also present, APEX uses the larger estimate, never both.")
                            .font(APEXFont.body(11, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                }

                if type.id == "incidental-steps" {
                    Label("If a walk or run is logged above, keep this field to incidental steps only.", systemImage: "exclamationmark.triangle")
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.amberDeep)
                }

                Button {
                    Task {
                        await session.addActivity(
                            type: type,
                            date: date,
                            quantity: type.inputStyle == .steps ? steps : quantity,
                            durationMinutes: [.count, .duration].contains(type.inputStyle) ? durationMinutes : nil,
                            distanceKM: type.inputStyle == .distance ? distanceKM : nil,
                            watchKcal: watchKcal > 0 ? watchKcal : nil
                        )
                        onSaved()
                    }
                } label: {
                    Label("Add to today", systemImage: "plus")
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.amber))
            }
            .padding(22)
        }
        .background(APEXBackground())
    }

    @ViewBuilder
    private var inputControls: some View {
        switch type.inputStyle {
        case .count:
            VStack(spacing: 18) {
                valueStepper(title: "COUNT", value: Int(quantity), decrement: { quantity = max(1, quantity - 1) }, increment: { quantity += 1 })
                durationPicker
            }
        case .duration:
            durationPicker
        case .distance:
            VStack(alignment: .leading, spacing: 9) {
                Text("DISTANCE")
                    .font(APEXFont.mono(10))
                    .tracking(1.2)
                HStack {
                    TextField("Distance", value: $distanceKM, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("km").font(APEXFont.mono(12))
                }
            }
        case .steps:
            VStack(alignment: .leading, spacing: 9) {
                Text("STEPS NOT ALREADY COVERED BY THE BLOCKS ABOVE.")
                    .font(APEXFont.mono(10))
                    .tracking(1.1)
                Stepper(value: $steps, in: 0...50_000, step: 500) {
                    Text(language.format("%d steps", Int(steps)))
                        .font(APEXFont.display(21))
                }
            }
        case .watchKcal:
            EmptyView()
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(language.text(type.inputStyle == .count ? "LENGTH EACH" : "DURATION"))
                .font(APEXFont.mono(10))
                .tracking(1.2)
            if type.inputStyle == .count && ["massage-session", "deep-tissue-massage"].contains(type.id) {
                Picker("Minutes", selection: $durationMinutes) {
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                    Text("90 min").tag(90)
                }
                .pickerStyle(.segmented)
            } else {
                valueStepper(
                    title: "",
                    value: durationMinutes,
                    suffix: "min",
                    decrement: { durationMinutes = max(5, durationMinutes - durationStep) },
                    increment: { durationMinutes = min(720, durationMinutes + durationStep) }
                )
            }
        }
    }

    private var durationStep: Int { durationMinutes >= 120 ? 30 : durationMinutes >= 60 ? 15 : 5 }

    private func valueStepper(
        title: String,
        value: Int,
        suffix: String = "",
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack {
            if !title.isEmpty {
                Text(language.text(title)).font(APEXFont.mono(10)).tracking(1.2)
            }
            Spacer()
            Button(action: decrement) { Image(systemName: "minus") }
                .buttonStyle(MiniStepperStyle())
            Text(language.format("%d %@", value, language.text(suffix)))
                .font(APEXFont.display(20))
                .frame(minWidth: 80)
            Button(action: increment) { Image(systemName: "plus") }
                .buttonStyle(MiniStepperStyle())
        }
    }
}

private struct MiniStepperStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 39)
            .background(APEXColor.amber, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
