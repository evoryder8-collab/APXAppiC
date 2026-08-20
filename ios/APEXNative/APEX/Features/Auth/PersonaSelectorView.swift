import SwiftUI

struct PersonaSelectorView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var selectedIndex = 2
    @State private var dragOffset: CGFloat = 0
    @State private var summoned = false
    @State private var rotatingLine = 0

    // Matthew remains the initial centre. June and Constantine retain the
    // immediate left/right positions, while Iulian occupies the far orbit.
    private let personas: [Persona] = [.iulian, .june, .matthew, .constantine]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    APEXMark(size: 34)
                    Text(language.text("APEX"))
                        .font(APEXFont.display(19))
                        .tracking(6)
                    Spacer()
                    PortalLanguagePicker()
                }
                .padding(.horizontal, 22)
                .padding(.top, max(proxy.safeAreaInsets.top, 14) + 8)

                Spacer(minLength: 18)

                VStack(spacing: 8) {
                    Text(language.text(.chooseWhoEnters))
                        .font(APEXFont.display(27))
                        .foregroundStyle(APEXColor.ink)
                        .multilineTextAlignment(.center)
                    Text(language.text(.swipeToRotate))
                        .font(APEXFont.mono(11))
                        .tracking(1.2)
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .opacity(summoned ? 1 : 0)
                .offset(y: summoned ? 0 : 14)

                ZStack {
                    Ellipse()
                        .fill(APEXColor.violet.opacity(0.13))
                        .frame(width: proxy.size.width * 0.72, height: 70)
                        .blur(radius: 22)
                        .offset(y: 172)

                    ForEach(Array(personas.enumerated()), id: \.element) { index, persona in
                        personaCard(persona, index: index, width: proxy.size.width)
                    }
                }
                .frame(height: min(510, proxy.size.height * 0.57))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { dragOffset = $0.translation.width }
                        .onEnded { value in
                            let threshold = max(42, proxy.size.width * 0.12)
                            var next = selectedIndex
                            if value.predictedEndTranslation.width < -threshold { next += 1 }
                            if value.predictedEndTranslation.width > threshold { next -= 1 }
                            withAnimation(.spring(response: 0.58, dampingFraction: 0.79)) {
                                selectedIndex = wrapped(next)
                                dragOffset = 0
                            }
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                )

                VStack(spacing: 15) {
                    let persona = personas[selectedIndex]
                    Text(persona.displayName)
                        .font(APEXFont.display(29))
                    Text(language.text(persona.subtitle).uppercased(with: language.language.locale))
                        .font(APEXFont.mono(10))
                        .tracking(1.8)
                        .foregroundStyle(APEXColor.secondaryInk)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        session.choose(persona)
                    } label: {
                        HStack {
                            Text(language.text(.enterApex))
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: color(for: persona)))
                    .padding(.horizontal, 30)
                }
                .id(personaID)
                .transition(.opacity)

                Spacer(minLength: max(proxy.safeAreaInsets.bottom, 18))
            }
            .onAppear {
                withAnimation(.spring(response: 0.95, dampingFraction: 0.72).delay(0.12)) {
                    summoned = true
                }
            }
        }
    }

    private var personaID: String { personas[selectedIndex].rawValue }

    @ViewBuilder
    private func personaCard(_ persona: Persona, index: Int, width: CGFloat) -> some View {
        let raw = relative(index)
        let dragProgress = dragOffset / max(width * 0.72, 1)
        let position = CGFloat(raw) + dragProgress
        let depth = min(abs(position), 1)
        let active = abs(position) < 0.48

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 54, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(active ? 0.72 : 0.34), color(for: persona).opacity(active ? 0.18 : 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 54, style: .continuous)
                        .stroke(.white.opacity(active ? 0.95 : 0.42), lineWidth: 1)
                }

            PortraitImage(name: persona.portraitName)
                .scaledToFit()
                .padding(.top, 8)
                .mask(RoundedRectangle(cornerRadius: 52, style: .continuous))

            LinearGradient(
                colors: [.clear, color(for: persona).opacity(0.20)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 52, style: .continuous))
        }
        .frame(width: min(width * 0.68, 310), height: 402)
        .scaleEffect(1 - depth * 0.28)
        .rotation3DEffect(.degrees(Double(-position * 37)), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
        .offset(x: position * width * 0.56, y: depth * 42)
        .opacity(1 - depth * 0.24)
        .zIndex(Double(10 - abs(position)))
        .shadow(color: color(for: persona).opacity(active ? 0.25 : 0.08), radius: active ? 34 : 12, y: 18)
        .onTapGesture {
            if index == selectedIndex {
                session.choose(persona)
            } else {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.78)) { selectedIndex = index }
            }
        }
        .opacity(summoned ? 1 : 0)
        .scaleEffect(summoned ? (1 - depth * 0.28) : 0.72)
    }

    private func relative(_ index: Int) -> Int {
        let difference = index - selectedIndex
        if difference > 1 { return difference - personas.count }
        if difference < -1 { return difference + personas.count }
        return difference
    }

    private func wrapped(_ index: Int) -> Int {
        (index % personas.count + personas.count) % personas.count
    }

    private func color(for persona: Persona) -> Color {
        switch persona {
        case .iulian: APEXColor.green
        case .june: APEXColor.teal
        case .matthew: APEXColor.cyan
        case .constantine: APEXColor.violet
        }
    }
}

struct PortraitImage: View {
    let name: String

    var body: some View {
        // UIImage(named:) keeps the decoded portrait in the system image
        // cache. The carousel body is recomputed continuously while dragging,
        // so contentsOfFile here would otherwise re-read three PNGs per frame.
        if let image = UIImage(named: name, in: .main, compatibleWith: nil) {
            Image(uiImage: image).resizable()
        } else {
            Image(systemName: "person.crop.square.fill").resizable()
        }
    }
}
