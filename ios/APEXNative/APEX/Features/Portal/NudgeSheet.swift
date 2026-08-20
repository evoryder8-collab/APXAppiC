import SwiftUI

/// What the bell opens: the day's reminders with the reasoning attached.
///
/// A notification has room for one line, which is enough to prompt but not
/// enough to be useful. This is where the number comes with its explanation,
/// so a reminder to eat more protein does not read as an instruction to drink
/// the entire shortfall at once.
struct NudgeSheet: View {
    let nudges: NudgeCenter
    var onClose: () -> Void

    @State private var language = LanguageState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            APEXPopoverHeader(
                title: language.text("Reminders"),
                subtitle: language.text("Today only"),
                onClose: onClose
            )

            if nudges.pending.isEmpty {
                Text(language.text("Nothing to flag today."))
                    .font(APEXFont.body(13))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 11) {
                        ForEach(nudges.pending) { nudge in
                            NudgeCard(nudge: nudge, isRead: nudges.isRead(nudge))
                        }
                    }
                }
                .frame(height: min(CGFloat(nudges.pending.count) * 168, 420))
            }
        }
        .padding(17)
        .onAppear { nudges.markAllRead() }
    }
}

private struct NudgeCard: View {
    let nudge: DailyNudges.Nudge
    let isRead: Bool

    @State private var language = LanguageState.shared

    private var icon: String {
        switch nudge.kind {
        case .proteinShort: "fork.knife"
        case .creatineMissed: "pills.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(APEXColor.amber)
                Text(NudgeCopy.title(nudge, language))
                    .font(APEXFont.body(14, weight: .bold))
                Spacer(minLength: 0)
                if !isRead {
                    Circle().fill(APEXColor.amber).frame(width: 7, height: 7)
                }
            }
            Text(NudgeCopy.detail(nudge, language))
                .font(APEXFont.body(12))
                .foregroundStyle(APEXColor.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 15))
    }
}
