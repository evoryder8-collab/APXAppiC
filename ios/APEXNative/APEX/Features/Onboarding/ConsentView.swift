import SwiftUI

/// The permissions, explained before they are asked for.
///
/// iOS gives one chance at each of these, and a prompt that arrives with no
/// context gets declined. Each one says what it buys and what happens if it is
/// refused, and every one of them can be refused without breaking the app.
struct ConsentView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var health = HealthKitManager.shared
    @State private var nudges = NudgeCenter.shared
    @State private var healthAsked = false
    @State private var notificationsAsked = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AuroraField(animated: !reduceMotion)
                .ignoresSafeArea()
            VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language.text("Two permissions, both optional"))
                            .font(APEXFont.display(27))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(language.text("You can say no to either and everything still works. You can change both later in Settings."))
                            .font(APEXFont.body(13))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    consentCard(
                        icon: "heart.text.square.fill",
                        title: language.text("Apple Health"),
                        body: language.text("Reads the steps, workouts and sleep you already record, so your targets follow the week you actually had. Without it, you enter activity by hand."),
                        buttonTitle: healthAsked ? language.text("Asked") : language.text("Allow Health access"),
                        done: healthAsked
                    ) {
                        healthAsked = true
                        Task { _ = await health.requestAccessAndImport() }
                    }

                    consentCard(
                        icon: "bell.badge.fill",
                        title: language.text("Reminders"),
                        body: language.text("One quiet reminder in the evening, only on days you are short on protein or have not taken your creatine. Without it, the same reminders wait for you inside the app."),
                        buttonTitle: notificationsAsked ? language.text("Asked") : language.text("Allow reminders"),
                        done: notificationsAsked
                    ) {
                        notificationsAsked = true
                        Task { await nudges.requestPermission() }
                    }
                }
                .padding(22)
            }

            Button {
                Task { await session.finishOnboarding() }
            } label: {
                HStack {
                    Text(language.text("Start my 7 days"))
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(APEXPrimaryButtonStyle())
            .accessibilityIdentifier("consent-finish")
            .padding(22)
            }
        }
    }

    private func consentCard(
        icon: String,
        title: String,
        body: String,
        buttonTitle: String,
        done: Bool,
        action: @escaping () -> Void
    ) -> some View {
        GlassCard(radius: 26, padding: 19) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(APEXColor.violet)
                    Text(title).font(APEXFont.body(17, weight: .bold))
                }
                Text(body)
                    .font(APEXFont.body(13))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    Text(buttonTitle)
                        .font(APEXFont.body(14, weight: .bold))
                        .foregroundStyle(done ? APEXColor.secondaryInk : APEXColor.violet)
                }
                .buttonStyle(.plain)
                .disabled(done)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
