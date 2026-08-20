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
    @State private var modelController = MuscleMapController()
    /* The figure needs a moment to weld 5 MB of mesh. Rather than show an
       empty frame where it will be, the app's own opening identity stays up
       and hands over once it is genuinely there. */
    @State private var figureReady = false

    var body: some View {
        ZStack {
            AuroraField(animated: !reduceMotion)
                .ignoresSafeArea()

            /* Figure at the top, words under it, the way in at the bottom
               where a thumb already rests. */
            VStack(spacing: 0) {
                Spacer(minLength: 6)
                figure
                brand
                Spacer(minLength: 16)
                actions
                signUpLink
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            PortalLanguagePicker()
                .padding(.trailing, 22)
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)
        }
        .overlay {
            /* Held over everything until the figure is welded, so the icon the
               user tapped on the home screen simply stays, and the app appears
               to open into itself rather than into a half-built screen. */
            if !figureReady {
                ZStack {
                    APEXColor.canvas
                    AuroraField(animated: !reduceMotion)
                    VStack(spacing: 18) {
                        APEXMark(size: 84)
                            .background { BreathingGlow(active: !reduceMotion) }
                        Text("APEX")  // brand name, never translated
                            .font(APEXFont.display(34))
                            .tracking(9)
                            .foregroundStyle(APEXColor.ink)
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .onAppear {
            /* One orchestrated entrance rather than five things each doing
               their own thing, which is what makes it read as designed. */
            withAnimation(.smooth(duration: 0.9)) { appeared = true }
        }
    }

    // MARK: - Figure

    /// The real anatomical figure, turning, with nothing highlighted.
    ///
    /// It is a 5 MB mesh in a web view and takes a moment to weld, so the rest
    /// of the screen is laid out and usable before it arrives and it fades in
    /// when it is ready. Nothing waits on it. The primitive figure used
    /// elsewhere loads instantly but reads as a mannequin, which is the wrong
    /// first impression for the one screen everybody sees.
    private var figure: some View {
        MuscleMapView(
            dayType: "welcome",
            xray: false,
            transparentBackground: true,
            controller: modelController,
            onReady: {
                withAnimation(.smooth(duration: 0.65)) { figureReady = true }
            }
        )
        .frame(height: 320)
        .background {
            ModelAura(accent: APEXColor.cyan, animated: !reduceMotion)
        }
        .allowsHitTesting(false)
        .opacity(appeared ? 1 : 0)
        .animation(.smooth(duration: 1.3).delay(0.2), value: appeared)
        .onAppear {
            /* Set before the web view attaches: the controller pushes both
               flags on attach, so assigning here beats calling a toggle that
               would immediately be overwritten. */
            modelController.spinning = !reduceMotion
            modelController.xray = false
        }
    }

    // MARK: - Brand

    private var brand: some View {
        VStack(spacing: 14) {
            APEXMark(size: 54)
                .shadow(color: APEXColor.violet.opacity(0.35), radius: 26, y: 10)
                .scaleEffect(appeared ? 1 : 0.86)
                .opacity(appeared ? 1 : 0)
                /* The halo goes in the background rather than beside the mark
                   in a stack: a 236pt circle as a sibling reserves 236pt of
                   layout and leaves a hole under the logo. As a background it
                   glows past the edges and costs no space at all. */
                .background {
                    BreathingGlow(active: appeared && !reduceMotion)
                        .scaleEffect(appeared ? 1 : 0.7)
                        .opacity(appeared ? 1 : 0)
                }
                .floating(index: 0, active: !reduceMotion)

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

            Text(language.text("Every session, meal and night of sleep quietly rewrites what tomorrow asks of you."))
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
                Text(language.text("Continue with eMail"))
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
