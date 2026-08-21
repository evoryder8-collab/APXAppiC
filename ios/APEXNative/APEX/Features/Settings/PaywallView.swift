import SwiftUI

/// The two tiers, shown when the trial ends and whenever someone asks.
///
/// Prices are stated in full, including what the yearly plan actually saves and
/// what a fourth client costs a coach. A tier sheet that hides the second
/// number until checkout is the reason people distrust these screens.
struct PaywallView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var entitlements = EntitlementStore.shared
    @State private var code = ""
    @State private var codeMessage: String?
    @State private var redeeming = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which tier the person is looking at. Nothing is chosen for them: a
    /// preselected plan on a paywall is a decision made on someone's behalf.
    @State private var selected: Entitlement.Tier?
    var onClose: (() -> Void)?

    /* On the jewel ground the app's ink colours vanish, so the sheet carries
       its own two levels of white. */
    private let primaryInk = Color.white
    private let secondaryInk = Color.white.opacity(0.62)

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headline

                tierCard(
                    tier: .premium,
                    audience: language.text("For one person"),
                    features: [
                        "Adaptive plans built from your own training history",
                        "The follow-along player, with pacing and rest built in",
                        "Food, water, supplements and recovery in one day view",
                        "Predefined meal lists you can reuse"
                    ]
                )

                tierCard(
                    tier: .coach,
                    audience: language.text("For trainers"),
                    features: [
                        "Everything in Premium, for yourself",
                        "A client roster with their targets and history",
                        "Write and assign plans to the people you train",
                        "Predefined meal lists you can hand to clients"
                    ]
                )

                betaCode

                Text(language.text("Purchasing opens with the App Store listing. Until then, a beta code unlocks everything."))
                    .font(APEXFont.body(11))
                    .foregroundStyle(secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .background { JewelBackdrop(animated: !reduceMotion) }
        .foregroundStyle(primaryInk)
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var headline: some View {
        VStack(spacing: 7) {
            /* The stone the diamond in the top bar opens into. Large, dim and
               behind the wordmark rather than beside it, so it reads as the
               room the sheet is in rather than as an icon repeated. */
            Image(systemName: "diamond.fill")
                .font(.system(size: 54, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white.opacity(0.95), APEXColor.cyan.opacity(0.55), APEXColor.violet.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: APEXColor.cyan.opacity(0.5), radius: 22)
                .padding(.bottom, 4)
                .accessibilityHidden(true)

            Text(language.text("APEX"))
                .font(APEXFont.display(30))
                .tracking(6)
            if let days = entitlements.trialDaysRemaining {
                Text(language.format("%d days left in your trial", days))
                    .font(APEXFont.body(14, weight: .semibold))
                    .foregroundStyle(APEXColor.amber)
            } else {
                Text(language.text("Your trial has ended"))
                    .font(APEXFont.body(14, weight: .semibold))
                    .foregroundStyle(APEXColor.amber)
            }
        }
        .padding(.top, 6)
    }

    private func tierCard(
        tier: Entitlement.Tier,
        audience: String,
        features: [String]
    ) -> some View {
        let price = Entitlement.price(tier)
        let isSelected = selected == tier
        return FacetPanel(
            radius: 26,
            padding: 19,
            /* Lifted by choice once one is made, and by recommendation until
               then, so the sheet always has exactly one focal point. */
            lifted: isSelected || (selected == nil && tier == .premium),
            selected: isSelected
        ) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Text(language.text(tier == .premium ? "Premium" : "Coach"))
                        .font(APEXFont.display(23))
                    Spacer(minLength: 8)
                    Text(audience.uppercased(with: language.language.locale))
                        .font(APEXFont.mono(9))
                        .tracking(1.2)
                        .foregroundStyle(secondaryInk)
                }

                VStack(alignment: .leading, spacing: 5) {
                    priceRow(
                        amount: price.monthlyRappen,
                        period: language.text("per month"),
                        emphasised: price.yearlyRappen == nil
                    )
                    if let yearly = price.yearlyRappen {
                        HStack(spacing: 8) {
                            priceRow(amount: yearly, period: language.text("per year"), emphasised: true)
                            if let saving = price.yearlySavingPercent {
                                Text(language.format("Save %d%%", saving))
                                    .font(APEXFont.mono(9))
                                    .tracking(0.8)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(APEXColor.amber.opacity(0.18), in: Capsule())
                                    .foregroundStyle(APEXColor.amber)
                            }
                        }
                    }
                    if tier == .coach {
                        Text(language.format(
                            "%d clients included, then CHF %@ each per month",
                            Entitlement.coachIncludedSeats,
                            Self.francs(Entitlement.coachExtraSeatRappen)
                        ))
                        .font(APEXFont.body(11))
                        .foregroundStyle(secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(APEXColor.amber)
                                .padding(.top, 3)
                            Text(language.text(feature))
                                .font(APEXFont.body(12))
                                .foregroundStyle(secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        /* Each card drifts on its own phase, so the pair breathes instead of
           moving as one block, which reads as a bug rather than as life. */
        .floating(index: tier == .premium ? 0 : 2, active: !reduceMotion)
        .scaleEffect(isSelected ? 1.015 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            /* Tapping the chosen one again clears it, so the choice is never a
               trap. */
            selected = isSelected ? nil : tier
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func priceRow(amount: Int, period: String, emphasised: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(language.format("CHF %@", Self.francs(amount)))
                .font(APEXFont.display(emphasised ? 21 : 17))
            Text(period)
                .font(APEXFont.body(11))
                .foregroundStyle(secondaryInk)
        }
    }

    private var betaCode: some View {
        FacetPanel(radius: 22, padding: 17) {
            VStack(alignment: .leading, spacing: 11) {
                Text(language.text("Have a beta code?"))
                    .font(APEXFont.body(14, weight: .bold))
                HStack(spacing: 9) {
                    TextField(language.text("Code"), text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(APEXFont.mono(13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    Button(language.text("Redeem")) {
                        Task { await submitCode() }
                    }
                    .font(APEXFont.body(13, weight: .bold))
                    .disabled(code.isEmpty || redeeming)
                }
                /* Each outcome says what actually happened. "Not recognised"
                   for a code that was already claimed sends someone hunting for
                   a typo that is not there. */
                if let message = codeMessage {
                    Text(message)
                        .font(APEXFont.body(11))
                        .foregroundStyle(APEXColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func submitCode() async {
        redeeming = true
        defer { redeeming = false }
        switch await entitlements.redeemBeta(code: code, service: .shared) {
        case .unlocked:
            entitlements.resolve(profile: session.profile)
            onClose?()
        case .alreadyRedeemed:
            codeMessage = language.text("This account has already used a beta code.")
        case .notSignedIn:
            codeMessage = language.text("Sign in first, then enter your code.")
        case .unavailable:
            codeMessage = language.text("Could not reach APEX. Try again when you are online.")
        case .notRecognised:
            codeMessage = language.text("That code was not recognised.")
        }
    }

    /// Swiss francs, written the way a Swiss price tag writes them.
    private static func francs(_ rappen: Int) -> String {
        rappen % 100 == 0
            ? "\(rappen / 100).–"
            : String(format: "%d.%02d", rappen / 100, rappen % 100)
    }
}
