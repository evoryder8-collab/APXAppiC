import SwiftUI
import AuthenticationServices
import CryptoKit

/// The first screen of the commercial app: what someone sees the moment they
/// open it from the App Store, before any account exists.
///
/// Three ways in and nothing else. A first screen that explains the product at
/// length is a first screen nobody reads, so the atmosphere does the work and
/// the trial does the explaining.
struct WelcomeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = LanguageState.shared
    @State private var currentNonce: String?
    @State private var appeared = false

    var body: some View {
        ZStack {
            AuroraField(animated: !reduceMotion)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 54)
                    brand
                    Spacer(minLength: 46)
                    actions
                    signUpLink
                    Spacer(minLength: 26)
                    bespokeLink
                }
                .padding(.horizontal, 26)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            PortalLanguagePicker()
                .padding(.trailing, 22)
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            /* One orchestrated entrance rather than five things each doing
               their own thing, which is what makes it read as designed. */
            withAnimation(.smooth(duration: 0.9)) { appeared = true }
        }
    }

    // MARK: - Brand

    private var brand: some View {
        VStack(spacing: 17) {
            APEXMark(size: 78)
                .shadow(color: APEXColor.violet.opacity(0.35), radius: 26, y: 10)
                .scaleEffect(appeared ? 1 : 0.86)
                .opacity(appeared ? 1 : 0)
                /* The halo goes in the background rather than beside the mark
                   in a stack: a 236pt circle as a sibling reserves 236pt of
                   layout and leaves a hole under the logo. As a background it
                   glows past the edges and costs no space at all. */
                .background {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [APEXColor.violet.opacity(0.34), .clear],
                                center: .center, startRadius: 2, endRadius: 118
                            )
                        )
                        .frame(width: 236, height: 236)
                        .blur(radius: 12)
                        .scaleEffect(appeared ? 1 : 0.7)
                        .opacity(appeared ? 1 : 0)
                }

            Text("APEX")  // brand name, never translated
                .font(APEXFont.display(42))
                .tracking(11)
                .overlay {
                    /* A single slow sweep of light across the wordmark. It runs
                       once on entry: a shimmer that loops forever reads as a
                       loading state, not as craft. */
                    ShimmerSweep(active: appeared && !reduceMotion)
                }
                .mask(Text("APEX").font(APEXFont.display(42)).tracking(11))
                .rise(appeared, delay: 0.10)

            Text(language.text("Training, food and recovery that adapt to the week you actually had."))
                .font(APEXFont.body(15))
                .foregroundStyle(APEXColor.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .rise(appeared, delay: 0.18)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonce()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .rise(appeared, delay: 0.26)

            Button {
                session.route = .emailAuth(signUp: false)
            } label: {
                Text(language.text("Continue with email"))
                    .font(APEXFont.body(16, weight: .semibold))
                    .foregroundStyle(APEXColor.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.ultraThinMaterial.opacity(0.97), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.95), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 7)
            }
            .buttonStyle(PressShrink())
            .rise(appeared, delay: 0.33)
        }
    }

    private var signUpLink: some View {
        Button {
            session.route = .emailAuth(signUp: true)
        } label: {
            HStack(spacing: 5) {
                Text(language.text("New here?"))
                    .foregroundStyle(APEXColor.secondaryInk)
                Text(language.text("Sign Up"))
                    .fontWeight(.bold)
                    .foregroundStyle(APEXColor.violet)
            }
            .font(APEXFont.body(14))
        }
        .buttonStyle(PressShrink())
        .padding(.top, 24)
        .rise(appeared, delay: 0.40)
    }

    /* The bespoke accounts keep their portrait entrance. It is not the front
       door of a public app, but it is not worth losing. */
    private var bespokeLink: some View {
        Button {
            session.route = .persona
        } label: {
            Text(language.text("Bespoke account"))
                .font(APEXFont.mono(10))
                .tracking(1.3)
                .foregroundStyle(APEXColor.secondaryInk)
        }
        .buttonStyle(PressShrink())
        .padding(.bottom, 20)
        .rise(appeared, delay: 0.48)
    }

    // MARK: - Apple

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            /* A cancelled sheet is not a failure worth an alert. */
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            session.alertMessage = error.localizedDescription
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                session.alertMessage = language.text("Apple did not return a usable sign-in. Please try again.")
                return
            }
            Task { await session.signInWithApple(idToken: token, nonce: nonce) }
        }
    }

    // MARK: - Nonce

    /* Apple signs a hash of this value into the token, and Supabase compares it
       against the raw copy, which is what stops a token being replayed. */
    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess else { continue }
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
