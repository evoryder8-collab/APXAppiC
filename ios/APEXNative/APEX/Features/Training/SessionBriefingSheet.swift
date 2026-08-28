import SwiftUI

/// What the "i" on the figure opens: today's session, explained.
struct SessionBriefingSheet: View {
    let briefing: SessionBriefing.Briefing
    var knowledge: SessionBriefing.Knowledge = .empty
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

                if !knowledge.lessonKeys.isEmpty {
                    section(
                        label: language.text("What this session trains"),
                        body: knowledge.lessonKeys
                            .map(language.text)
                            .joined(separator: "\n\n")
                    )
                    .accessibilityIdentifier("session-briefing-knowledge")
                }

                if let contextNoteKey = knowledge.contextNoteKey {
                    section(
                        label: language.text("For this session"),
                        body: language.text(contextNoteKey)
                    )
                    .accessibilityIdentifier("session-briefing-context")
                }

                if !knowledge.cautionKeys.isEmpty {
                    section(
                        label: language.text("Worth knowing"),
                        body: knowledge.cautionKeys
                            .map(language.text)
                            .joined(separator: "\n\n")
                    )
                    .accessibilityIdentifier("session-briefing-cautions")
                }

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

/// A slow swell of light behind the figure.
///
/// Deliberately dim and slow: it should register as depth rather than as
/// something happening. Anything faster competes with the model for attention,
/// which is the opposite of the point.
struct ModelAura: View {
    var accent: Color = APEXColor.violet
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let swell = animated ? 1 + 0.09 * sin(elapsed / 5.2 * .pi * 2) : 1
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.20), accent.opacity(0.06), .clear],
                        center: .center, startRadius: 4, endRadius: 190
                    )
                )
                .frame(width: 380, height: 380)
                .scaleEffect(swell)
                .blur(radius: 26)
        }
        .allowsHitTesting(false)
    }
}

/// A gleam that crosses the tooltip glyph every few seconds.
struct TooltipGleam: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            /* Most of the cycle is spent off-glyph, so it catches the eye
               occasionally instead of shimmering constantly. */
            let cycle = elapsed.truncatingRemainder(dividingBy: 4.5) / 4.5
            let travel = cycle * 2.4 - 0.7
            LinearGradient(
                colors: [.clear, .white.opacity(0.9), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(width: 18)
            .rotationEffect(.degrees(22))
            .offset(x: travel * 34)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}
