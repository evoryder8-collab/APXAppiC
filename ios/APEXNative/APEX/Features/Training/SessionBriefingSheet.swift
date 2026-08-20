import SwiftUI

/// What the "i" on the figure opens: today's session, explained.
struct SessionBriefingSheet: View {
    let briefing: SessionBriefing.Briefing
    var accent: Color = APEXColor.violet
    var onClose: () -> Void

    @State private var language = LanguageState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                APEXPopoverHeader(
                    title: language.text(briefing.title),
                    subtitle: language.text(briefing.intent.label),
                    onClose: onClose
                )

                muscleBlock(
                    label: language.text("Worked today"),
                    muscles: briefing.primary,
                    strong: true
                )

                if !briefing.secondary.isEmpty {
                    muscleBlock(
                        label: language.text("Also involved"),
                        muscles: briefing.secondary,
                        strong: false
                    )
                }

                section(
                    label: language.text("Why this shape"),
                    body: language.text(briefing.rationale)
                )

                section(
                    label: language.text("What matters most today"),
                    body: language.text(briefing.focus),
                    highlighted: true
                )
            }
            .padding(18)
        }
    }

    private func muscleBlock(label: String, muscles: [String], strong: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased(with: language.language.locale))
                .font(APEXFont.mono(9))
                .tracking(1.2)
                .foregroundStyle(APEXColor.secondaryInk)
            /* Wraps rather than scrolls sideways: a leg day names seven muscles
               and a hidden one is a muscle the reader does not know is working. */
            FlowLayout(spacing: 7) {
                ForEach(muscles, id: \.self) { muscle in
                    Text(language.text(muscle))
                        .font(APEXFont.body(12, weight: strong ? .bold : .regular))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            strong ? AnyShapeStyle(accent.opacity(0.16))
                                   : AnyShapeStyle(Color.white.opacity(0.6)),
                            in: Capsule()
                        )
                        .foregroundStyle(strong ? accent : APEXColor.secondaryInk)
                }
            }
        }
    }

    private func section(label: String, body: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased(with: language.language.locale))
                .font(APEXFont.mono(9))
                .tracking(1.2)
                .foregroundStyle(APEXColor.secondaryInk)
            Text(body)
                .font(APEXFont.body(13))
                .foregroundStyle(highlighted ? APEXColor.ink : APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(highlighted ? 13 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 15).fill(accent.opacity(0.10))
            }
        }
    }
}
