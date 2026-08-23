import SwiftUI

struct ExerciseFactValues: Equatable {
    var reps: Int?
    var signedLoadKG: Double?
    var rir: Int?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var contacts: Int?
    var rounds: Int?
    var workSeconds: Int?
    var recoverySeconds: Int?
}

/// One fact editor used by manual, guided and tracked sessions. The descriptor
/// decides what exists; the screens only bridge their draft into these values.
struct ExerciseFactFieldsView: View {
    let descriptor: ExerciseLoggingDescriptor
    @Binding var values: ExerciseFactValues
    @State private var language = LanguageState.shared

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        if !descriptor.isSupported {
            Text(language.text("Grouped rounds will arrive with supersets. This sequence cannot be logged as an ordinary set."))
                .font(APEXFont.body(11, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if descriptor.kind == .carry {
                    Picker(language.text("Carry target"), selection: carryDose) {
                        Text(language.text("Distance")).tag(CarryDose.distance)
                        Text(language.text("Time")).tag(CarryDose.time)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("exercise-fact-carry-dose")
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(editableFields, id: \.self) { field in
                        fieldEditor(field)
                    }
                }
                if descriptor.fields.contains(.signedLoad) {
                    Text(language.text("Negative load means supported; zero means bodyweight; positive means added load."))
                        .font(APEXFont.body(9, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                if descriptor.fields.contains(.completion) {
                    Text(language.text("Saving records this movement as completed. Time is optional."))
                        .font(APEXFont.body(10, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    @ViewBuilder
    private func fieldEditor(_ field: ExerciseLoggingField) -> some View {
        switch field {
        case .reps:
            integerField("REPS", identifier: "exercise-fact-reps", value: $values.reps)
        case .signedLoad:
            NumericFactField(
                label: language.text("LOAD KG (+/−)"),
                value: $values.signedLoadKG,
                identifier: "exercise-fact-signed-load",
                allowsNegative: true
            )
        case .rir:
            integerField("RIR", identifier: "exercise-fact-rir", value: $values.rir, maximum: 5)
        case .duration:
            integerField("TIME SEC", identifier: "exercise-fact-duration", value: $values.durationSeconds)
        case .distance:
            NumericFactField(
                label: language.text("DISTANCE M"),
                value: $values.distanceMeters,
                identifier: "exercise-fact-distance"
            )
        case .contacts:
            integerField("CONTACTS", identifier: "exercise-fact-contacts", value: $values.contacts)
        case .rounds:
            integerField("ROUNDS", identifier: "exercise-fact-rounds", value: $values.rounds)
        case .work:
            integerField("WORK SEC", identifier: "exercise-fact-work", value: $values.workSeconds)
        case .recovery:
            integerField("RECOVERY SEC", identifier: "exercise-fact-recovery", value: $values.recoverySeconds)
        case .completion:
            EmptyView()
        }
    }

    private enum CarryDose: String, Hashable {
        case distance
        case time
    }

    private var carryDose: Binding<CarryDose> {
        Binding(
            get: {
                values.durationSeconds != nil && values.distanceMeters == nil ? .time : .distance
            },
            set: { selection in
                switch selection {
                case .distance:
                    values.durationSeconds = nil
                case .time:
                    values.distanceMeters = nil
                }
            }
        )
    }

    private var editableFields: [ExerciseLoggingField] {
        descriptor.fields.filter { field in
            guard field != .completion else { return false }
            guard descriptor.kind == .carry else { return true }
            switch field {
            case .duration: return carryDose.wrappedValue == .time
            case .distance: return carryDose.wrappedValue == .distance
            default: return true
            }
        }
    }

    private func integerField(
        _ label: String,
        identifier: String,
        value: Binding<Int?>,
        maximum: Int? = nil
    ) -> some View {
        NumericFactField(
            label: language.text(label),
            value: Binding(
                get: { value.wrappedValue.map(Double.init) },
                set: { next in
                    let rounded = next.map { Int($0.rounded()) }
                    value.wrappedValue = maximum.map { limit in rounded.map { min(limit, max(0, $0)) } }
                        ?? rounded.map { max(0, $0) }
                }
            ),
            identifier: identifier,
            integer: true
        )
    }
}

private struct NumericFactField: View {
    let label: String
    @Binding var value: Double?
    let identifier: String
    var integer = false
    var allowsNegative = false

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(APEXFont.mono(8, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            TextField("0", text: $text)
                .accessibilityIdentifier(identifier)
                .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                .focused($focused)
                .font(APEXFont.mono(13, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 7)
                .frame(height: 36)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: text) { _, next in
                    if next.isEmpty { value = nil; return }
                    guard let parsed = Double(next.replacingOccurrences(of: ",", with: ".")),
                          allowsNegative || parsed >= 0
                    else { return }
                    value = integer ? parsed.rounded() : parsed
                }
        }
        .onAppear { text = display(value) }
        .onChange(of: value) { _, next in
            if !focused { text = display(next) }
        }
    }

    private func display(_ number: Double?) -> String {
        guard let number else { return "" }
        return number == number.rounded() ? String(Int(number)) : String(format: "%.1f", number)
    }
}
