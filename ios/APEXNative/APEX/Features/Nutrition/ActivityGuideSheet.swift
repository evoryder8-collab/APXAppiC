import SwiftUI

struct ActivityGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    private let levels: [(String, String, String)] = [
        ("SEDENTARY", "Under 5k steps · under 2h on feet", "Editing day, car everywhere, no workout."),
        ("LIGHTLY ACTIVE", "5–7.5k steps or 2–3h on feet", "Desk day plus one short home workout."),
        ("MODERATELY ACTIVE", "7.5–10k steps or 3–5h on feet", "Desk day plus a full 45–60 minute session."),
        ("VERY ACTIVE", "10–14k steps or 5–8h on feet", "Full shoot day or four to six massages."),
        ("EXTRA ACTIVE", "14k+ steps and 8h+ physical work", "Championship filming marathon or double-session day.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(language.text("Activity guide"))
                            .font(APEXFont.display(31))
                        Text(language.text("Quick Mode's brain"))
                            .font(APEXFont.mono(11))
                            .tracking(1.4)
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    Spacer()
                    Button(language.text("Done")) { dismiss() }
                }

                Text(language.text("The labels are weekly averages. Use steps and hours on your feet when you need a fast choice, or log real blocks for a computed day."))
                    .font(APEXFont.body(15, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)

                ForEach(levels, id: \.0) { level in
                    GlassCard(radius: 24, padding: 17) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text(level.0))
                                .font(APEXFont.mono(11))
                                .tracking(1.2)
                                .foregroundStyle(APEXColor.amberDeep)
                            Text(language.text(level.1))
                                .font(APEXFont.display(17))
                            Text(language.text(level.2))
                                .font(APEXFont.body(13, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(language.text("EXAMPLE DAYS"))
                        .font(APEXFont.mono(10))
                        .tracking(1.4)
                    personaRow(icon: "video", title: "Videographer", copy: "Four hours gimbal + rig carry + travel")
                    personaRow(icon: "hand.raised.fingers.spread", title: "Massage therapist", copy: "Three 60-minute sessions + normal errands")
                    personaRow(icon: "desktopcomputer", title: "Office worker", copy: "Desk floor + gym session + incidental steps")
                }
            }
            .padding(22)
        }
        .background(APEXBackground())
    }

    private func personaRow(icon: String, title: String, copy: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(APEXColor.violet.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text(title)).font(APEXFont.body(14, weight: .bold))
                Text(language.text(copy)).font(APEXFont.body(12, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
            }
        }
    }
}
