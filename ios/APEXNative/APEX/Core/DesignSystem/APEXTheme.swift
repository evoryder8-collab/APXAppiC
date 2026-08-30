import SwiftUI
import UIKit

enum APEXColor {
    static let ink = Color(red: 0.075, green: 0.073, blue: 0.11)
    static let secondaryInk = Color(red: 0.34, green: 0.35, blue: 0.42)
    static let canvas = Color(red: 0.974, green: 0.977, blue: 0.99)
    static let amber = Color(red: 1.0, green: 0.64, blue: 0.035)
    static let amberDeep = Color(red: 0.75, green: 0.29, blue: 0.02)
    static let teal = Color(red: 0.03, green: 0.73, blue: 0.64)
    static let cyan = Color(red: 0.12, green: 0.78, blue: 0.91)
    static let violet = Color(red: 0.51, green: 0.27, blue: 0.96)
    static let green = Color(red: 0.04, green: 0.72, blue: 0.47)
    static let danger = Color(red: 0.78, green: 0.10, blue: 0.12)
    static let whiteGlass = Color.white.opacity(0.72)
}

enum APEXFont {
    /* Every font in the app comes from here, and until now every one was a
       fixed point size, so a person who turns text size up in Accessibility
       settings saw no change anywhere. Scaling in this one place fixes all 874
       call sites at once, which is the reason the helper exists.

       The sizes are scaled against a text style rather than swapped for one,
       because the layouts are built around these specific sizes and a heading
       that jumps from 26pt to .largeTitle would reflow every screen. */
    private static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: size)
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: scaled(size, .title2), weight: weight, design: .rounded)
    }

    /* Monospaced text is mostly numbers in tight columns, so it scales against
       a caption, which grows more gently than body. */
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: scaled(size, .caption1), weight: weight, design: .monospaced)
    }

    static func body(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size, .body), weight: weight, design: .rounded)
    }
}

struct APEXBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                APEXColor.canvas
                Circle()
                    .fill(APEXColor.amber.opacity(0.22))
                    .frame(width: proxy.size.width * 1.05)
                    .blur(radius: 72)
                    .offset(x: proxy.size.width * 0.36, y: -proxy.size.height * 0.31)
                Circle()
                    .fill(APEXColor.teal.opacity(0.17))
                    .frame(width: proxy.size.width * 1.1)
                    .blur(radius: 82)
                    .offset(x: -proxy.size.width * 0.45, y: proxy.size.height * 0.32)
                Circle()
                    .fill(APEXColor.violet.opacity(0.12))
                    .frame(width: proxy.size.width * 0.82)
                    .blur(radius: 86)
                    .offset(x: proxy.size.width * 0.42, y: proxy.size.height * 0.48)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

struct GlassCard<Content: View>: View {
    var radius: CGFloat = 28
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial.opacity(0.94), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.07), radius: 24, y: 12)
    }
}

struct APEXMark: View {
    var size: CGFloat = 42

    var body: some View {
        Canvas { context, canvas in
            let width = canvas.width
            let height = canvas.height
            var left = Path()
            left.move(to: CGPoint(x: width * 0.10, y: height * 0.88))
            left.addLine(to: CGPoint(x: width * 0.48, y: height * 0.08))
            left.addLine(to: CGPoint(x: width * 0.59, y: height * 0.34))
            left.addLine(to: CGPoint(x: width * 0.31, y: height * 0.88))
            left.closeSubpath()

            var right = Path()
            right.move(to: CGPoint(x: width * 0.49, y: height * 0.08))
            right.addLine(to: CGPoint(x: width * 0.91, y: height * 0.88))
            right.addLine(to: CGPoint(x: width * 0.69, y: height * 0.88))
            right.addLine(to: CGPoint(x: width * 0.41, y: height * 0.35))
            right.closeSubpath()

            context.fill(left, with: .linearGradient(
                Gradient(colors: [APEXColor.violet, APEXColor.cyan]),
                startPoint: .zero,
                endPoint: CGPoint(x: width, y: height)
            ))
            context.fill(right, with: .linearGradient(
                Gradient(colors: [APEXColor.amber, APEXColor.teal]),
                startPoint: CGPoint(x: width, y: 0),
                endPoint: CGPoint(x: 0, y: height)
            ))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("APEX")
    }
}

struct APEXTopBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var profile: Profile?
    var onSettings: (() -> Void)?
    /* The bell appears only when there is something to read. An always-present
       empty bell trains people to stop looking at it. */
    var nudges: NudgeCenter?
    var onOpenNudges: (() -> Void)?
    /// Retained as an API hook for screens that offer membership management.
    var onOpenPaywall: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            APEXMark(size: 33)
            Text("APEX")  // brand name, never translated
                .font(APEXFont.display(20))
                .tracking(6)
                /* The wordmark never wraps. Adding icons to this bar once broke
                   it into "APE / X", which is the sort of thing that makes a
                   whole app look unfinished. */
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 6)
            /* Dropped outright at accessibility text sizes rather than merely
               yielding. Squeezed to nothing it left an empty white capsule
               beside the logo, which reads as a rendering fault rather than as
               a name that did not fit. */
            if let profile, !dynamicTypeSize.isAccessibilitySize {
                Text(profile.displayName.uppercased())
                    .font(APEXFont.mono(10))
                    .tracking(2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    /* The name yields first when the bar is crowded: it is the
                       one thing here the user already knows. */
                    .layoutPriority(-1)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.55), in: Capsule())
            }
            if let nudges, !nudges.pending.isEmpty {
                Button(action: { onOpenNudges?() }) {
                    Image(systemName: nudges.unreadCount > 0 ? "bell.badge.fill" : "bell")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(nudges.unreadCount > 0 ? APEXColor.amber : APEXColor.secondaryInk)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageState.shared.text("Reminders"))
            }
            Button(action: { onSettings?() }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(APEXColor.secondaryInk)
            .accessibilityLabel(LanguageState.shared.text(.settings))
            .accessibilityIdentifier("portal.settings")
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
        .background(.ultraThinMaterial.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 20, y: 9)
    }
}

struct APEXPrimaryButtonStyle: ButtonStyle {
    var color: Color = APEXColor.amber

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(APEXFont.body(17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .shadow(color: color.opacity(0.3), radius: configuration.isPressed ? 5 : 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

extension View {
    func apexPageMargins() -> some View {
        padding(.horizontal, 18)
    }
}
