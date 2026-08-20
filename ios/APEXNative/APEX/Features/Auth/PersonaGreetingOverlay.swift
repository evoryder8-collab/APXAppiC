import SwiftUI

/// The portrait of the person who just signed in, briefly, on the way to the app.
///
/// Only ever one face: the account has already been identified by its
/// credentials, so offering a carousel of other people at this point would be
/// asking a question that has just been answered.
struct PersonaGreetingOverlay: View {
    let persona: Persona
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = LanguageState.shared
    @State private var appeared = false

    var body: some View {
        ZStack {
            APEXColor.canvas
            AuroraField(animated: !reduceMotion)

            VStack(spacing: 22) {
                PortraitImage(name: persona.portraitName)
                    .scaledToFit()
                    .frame(width: 196, height: 238)
                    .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .stroke(.white.opacity(0.9), lineWidth: 1)
                    )
                    .shadow(color: APEXColor.violet.opacity(0.28), radius: 38, y: 16)
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 6) {
                    Text(persona.displayName)
                        .font(APEXFont.display(30))
                    Text(language.text(persona.subtitle).uppercased(with: language.language.locale))
                        .font(APEXFont.mono(10))
                        .tracking(1.5)
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
            }
        }
        .ignoresSafeArea()
        .task {
            withAnimation(.smooth(duration: 0.65)) { appeared = true }
            /* Long enough to register, short enough that nobody waits on it. */
            try? await Task.sleep(for: .milliseconds(1500))
            onFinished()
        }
    }
}
