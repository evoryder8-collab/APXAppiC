import SwiftUI

/// What the camera will be asked to reproduce, chosen before it opens.
struct ProgressCaptureIntent: Hashable, Sendable, Identifiable {
    let id = UUID()
    var pose: String = "front"
    var framing: ProgressPhotoEngine.FramingMode = .full
    var weightKG: String = ""
    var note: String = ""
}

/*
 * The briefing shown before the camera opens.
 *
 * It is a card, not a screen: four short rules, the two choices that decide
 * how the shot is framed, and the optional context worth capturing while the
 * moment is in front of you. Camera access begins only after confirming, so
 * the permission prompt arrives with a reason already on screen.
 */
struct ProgressCaptureBriefing: View {
    @State private var language = LanguageState.shared
    @State private var intent: ProgressCaptureIntent
    var onCancel: () -> Void
    var onConfirm: (ProgressCaptureIntent) -> Void

    init(
        initial: ProgressCaptureIntent = ProgressCaptureIntent(),
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (ProgressCaptureIntent) -> Void
    ) {
        _intent = State(initialValue: initial)
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    private let steps = [
        "Same room and similar light",
        "Camera around waist height",
        "Neutral stance, no forced flex",
        "Feet on the guide line",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("BEFORE THE CAMERA OPENS").uppercased())
                    .font(APEXFont.mono(9))
                    .tracking(1.5)
                    .foregroundStyle(APEXColor.violet)
                Text(language.text("Build a repeatable image"))
                    .font(APEXFont.display(21))
                    .foregroundStyle(APEXColor.ink)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(APEXFont.mono(11, weight: .bold))
                            .foregroundStyle(APEXColor.violet)
                            .frame(width: 26, height: 26)
                            .background(APEXColor.violet.opacity(0.13), in: Circle())
                        Text(language.text(step))
                            .font(APEXFont.body(12, weight: .semibold))
                            .foregroundStyle(APEXColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

            chips(
                options: [("FRONT", "front"), ("SIDE", "side"), ("BACK", "back")],
                selected: intent.pose
            ) { intent.pose = $0 }

            chips(
                options: [
                    ("FULL BODY", ProgressPhotoEngine.FramingMode.full.rawValue),
                    ("TORSO ONLY", ProgressPhotoEngine.FramingMode.torso.rawValue),
                    ("FREE", ProgressPhotoEngine.FramingMode.free.rawValue),
                ],
                selected: intent.framing.rawValue
            ) { raw in
                if let mode = ProgressPhotoEngine.FramingMode(rawValue: raw) { intent.framing = mode }
            }

            TextField(language.text("Weight (kg)"), text: $intent.weightKG)
                .keyboardType(.decimalPad)
                .font(APEXFont.mono(14))
                .padding(11)
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))

            TextField(language.text("Short note (optional)"), text: $intent.note)
                .font(APEXFont.body(13))
                .padding(11)
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))

            Text(language.text("Camera access begins only after you confirm below. Nothing is uploaded until you review and save."))
                .font(APEXFont.body(9))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Button(language.text("Cancel"), action: onCancel)
                    .font(APEXFont.body(13, weight: .bold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .frame(height: 46)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 15))
                Button { onConfirm(intent) } label: {
                    Text(language.text("Got it, open camera"))
                        .font(APEXFont.body(13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(height: 46)
                        .frame(maxWidth: .infinity)
                        .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 15))
                }
                .accessibilityIdentifier("progress-briefing-confirm")
            }
            .buttonStyle(.plain)
        }
    }

    private func chips(
        options: [(String, String)],
        selected: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.1) { label, value in
                Button { onSelect(value) } label: {
                    Text(language.text(label))
                        .font(APEXFont.mono(9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(selected == value ? .white : APEXColor.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            selected == value ? AnyShapeStyle(APEXColor.violet.gradient) : AnyShapeStyle(.white.opacity(0.8)),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
