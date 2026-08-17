import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    let persona: Persona

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Button {
                        session.returnToPersonas()
                    } label: {
                        Label(language.text(.back), systemImage: "chevron.left")
                            .font(APEXFont.body(14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    PortalLanguagePicker()
                }

                PortraitImage(name: persona.portraitName)
                    .scaledToFit()
                    .frame(width: 176, height: 214)
                    .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 42, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                    .shadow(color: accent.opacity(0.25), radius: 34, y: 14)

                VStack(spacing: 6) {
                    Text(persona.displayName)
                        .font(APEXFont.display(32))
                    Text(language.text(persona.subtitle).uppercased(with: language.language.locale))
                        .font(APEXFont.mono(10))
                        .tracking(1.5)
                        .foregroundStyle(APEXColor.secondaryInk)
                }

                GlassCard(radius: 30, padding: 22) {
                    VStack(spacing: 16) {
                        loginField(title: language.text(.email), icon: "envelope", text: $email, secure: false)
                            .focused($focus, equals: .email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        loginField(title: language.text(.password), icon: "lock", text: $password, secure: true)
                            .focused($focus, equals: .password)
                            .textContentType(.password)

                        Button {
                            focus = nil
                            Task { await session.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
                        } label: {
                            if session.isBusy {
                                ProgressView().tint(.white)
                            } else {
                                HStack {
                                    Text(language.text(.signIn))
                                    Image(systemName: "arrow.right")
                                }
                            }
                        }
                        .buttonStyle(APEXPrimaryButtonStyle(color: accent))
                        .disabled(email.isEmpty || password.isEmpty || session.isBusy)
                        .opacity(email.isEmpty || password.isEmpty ? 0.52 : 1)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var accent: Color {
        switch persona {
        case .iulian: APEXColor.green
        case .june: APEXColor.teal
        case .matthew: APEXColor.cyan
        case .constantine: APEXColor.violet
        }
    }

    @ViewBuilder
    private func loginField(title: String, icon: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 22)
            if secure {
                SecureField(title, text: text)
            } else {
                TextField(title, text: text)
            }
        }
        .font(APEXFont.body(16, weight: .medium))
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.9)))
    }
}
