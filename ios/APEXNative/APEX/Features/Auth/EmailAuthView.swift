import SwiftUI

/// Sign in, or create an account, with an email address.
///
/// One screen for both, because they are the same two fields and a different
/// verb. The bespoke accounts sign in here with the credentials they already
/// have; nothing about them is special at this point.
struct EmailAuthView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp: Bool
    @FocusState private var focus: Field?

    init(signUp: Bool) {
        _isSignUp = State(initialValue: signUp)
    }

    private enum Field { case email, password }

    /// Six is Supabase's floor. Saying so before the request fails is kinder
    /// than a server error after the fact.
    private var passwordTooShort: Bool { isSignUp && !password.isEmpty && password.count < 6 }

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= (isSignUp ? 6 : 1) && !session.isBusy
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Button {
                        session.route = .welcome
                    } label: {
                        Label(language.text(.back), systemImage: "chevron.left")
                            .font(APEXFont.body(14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                VStack(spacing: 7) {
                    Text(language.text(isSignUp ? "Create your account" : "Welcome back"))
                        .font(APEXFont.display(30))
                        .multilineTextAlignment(.center)
                    Text(language.text(isSignUp
                        ? "TestFlight access is included for every account through 31 December 2027."
                        : "Sign in with the email and password you already use."))
                        .font(APEXFont.body(14))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GlassCard(radius: 28, padding: 20) {
                    VStack(spacing: 15) {
                        field(title: language.text(.email), icon: "envelope", text: $email, secure: false)
                            .onChange(of: email) { _, _ in clearConfirmationNotice() }
                            .focused($focus, equals: .email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        field(title: language.text(.password), icon: "lock", text: $password, secure: true)
                            .focused($focus, equals: .password)
                            .textContentType(isSignUp ? .newPassword : .password)

                        /* The account exists but nobody is signed in yet. Said here,
                   because a button that appears to do nothing is how someone
                   decides the app is broken and signs up twice. */
                if let address = session.awaitingConfirmationFor {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("Check your email"))
                            .font(APEXFont.body(14, weight: .bold))
                        Text(language.format(
                            "We sent a confirmation link to %@. Open it, then sign in here.",
                            address
                        ))
                        .font(APEXFont.body(12))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(APEXColor.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }

                if passwordTooShort {
                            Text(language.text("Use at least 6 characters."))
                                .font(APEXFont.body(11))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            focus = nil
                            submit()
                        } label: {
                            if session.isBusy {
                                ProgressView().tint(.white)
                            } else {
                                HStack {
                                    Text(isSignUp ? language.text("Create account") : language.text(.signIn))
                                    Image(systemName: "arrow.right")
                                }
                            }
                        }
                        .buttonStyle(APEXPrimaryButtonStyle())
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.5)
                    }
                }

                Button {
                    clearConfirmationNotice()
                    withAnimation(.snappy) { isSignUp.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(language.text(isSignUp ? "Already have an account?" : "New here?"))
                            .foregroundStyle(APEXColor.secondaryInk)
                        Text(isSignUp ? language.text(.signIn) : language.text("Sign Up"))
                            .fontWeight(.bold)
                            .foregroundStyle(APEXColor.violet)
                    }
                    .font(APEXFont.body(14))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }

    /// Cleared whenever the form changes, so a notice from one attempt does
    /// not sit above a different address.
    private func clearConfirmationNotice() {
        session.awaitingConfirmationFor = nil
    }

    private func submit() {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if isSignUp {
                await session.signUp(email: address, password: password)
            } else {
                await session.signIn(email: address, password: password)
            }
        }
    }

    private func field(
        title: String,
        icon: String,
        text: Binding<String>,
        secure: Bool
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(APEXColor.secondaryInk)
                .frame(width: 20)
            Group {
                if secure {
                    SecureField(title, text: text)
                } else {
                    TextField(title, text: text)
                }
            }
            .font(APEXFont.body(15))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 15))
    }
}
