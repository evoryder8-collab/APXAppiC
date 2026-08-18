import SwiftUI
import WebKit

/*
 * The figure plus its controls, in the app's own hand.
 *
 * The three.js widget can drive itself, but WebKit claims every touch it is
 * offered, which meant a finger resting on the figure stopped the card behind
 * it from scrolling. So the widget renders and Swift does the rest: a
 * horizontal drag turns the figure, a vertical drag belongs to the scroll view,
 * and the mode buttons are ordinary SwiftUI in the app's glass.
 */
@MainActor
@Observable
final class MuscleMapController {
    private weak var webView: WKWebView?
    private var facing: Double = 0

    var spinning = true
    var xray = true

    func attach(_ view: WKWebView) {
        webView = view
        push()
    }

    /// Turning by hand stops the turntable, the way grabbing a globe does.
    func turn(by degrees: Double) {
        if spinning { spinning = false }
        facing = (facing + degrees).truncatingRemainder(dividingBy: 360)
        run("MuscleMap.facing(\(facing))")
    }

    func toggleSpin() {
        spinning.toggle()
        run("MuscleMap.spin(\(spinning))")
    }

    func toggleXray() {
        xray.toggle()
        run("MuscleMap.xray(\(xray))")
    }

    private func push() {
        run("MuscleMap.spin(\(spinning)); MuscleMap.xray(\(xray))")
    }

    private func run(_ body: String) {
        webView?.evaluateJavaScript("window.MuscleMap && (function(){ \(body) })()")
    }
}

struct MuscleMapCard: View {
    let dayType: String
    var exerciseNames: [String] = []
    var height: CGFloat = 340
    var accent: Color = APEXColor.violet
    var eyebrow: String?
    var focus: String?

    @State private var controller = MuscleMapController()
    @State private var lastTranslation: CGFloat = 0
    @State private var isTurning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = LanguageState.shared

    /// A drag only turns the figure once it is clearly sideways, so a scroll
    /// that happens to start on the figure still scrolls.
    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if !isTurning {
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                    isTurning = true
                    lastTranslation = 0
                }
                let delta = value.translation.width - lastTranslation
                lastTranslation = value.translation.width
                controller.turn(by: Double(delta) * 0.55)
            }
            .onEnded { _ in
                isTurning = false
                lastTranslation = 0
            }
    }

    var body: some View {
        MuscleMapView(
            dayType: dayType,
            exerciseNames: exerciseNames,
            xray: controller.xray,
            controller: controller
        )
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .simultaneousGesture(turnGesture)
        .overlay(alignment: .topLeading) {
            if eyebrow != nil || focus != nil {
                /* The figure sits on a pale backdrop, so this label carries the
                   app's ink rather than white. */
                VStack(alignment: .leading, spacing: 4) {
                    if let eyebrow {
                        Text(eyebrow)
                            .font(APEXFont.mono(9))
                            .tracking(1.4)
                            .foregroundStyle(accent)
                    }
                    if let focus {
                        Text(focus)
                            .font(APEXFont.display(18))
                            .foregroundStyle(APEXColor.ink)
                    }
                }
                .padding(20)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 7) {
                modeButton(
                    label: "SPIN",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    on: controller.spinning
                ) {
                    controller.toggleSpin()
                }
                modeButton(label: "X-RAY", systemImage: "circle.lefthalf.filled", on: controller.xray) {
                    controller.toggleXray()
                }
            }
            .padding(15)
        }
        .onAppear {
            if reduceMotion, controller.spinning { controller.toggleSpin() }
        }
    }

    private func modeButton(
        label: String,
        systemImage: String,
        on: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(language.text(label))
                    .font(APEXFont.mono(9, weight: .bold))
                    .tracking(1.1)
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .foregroundStyle(on ? .white : APEXColor.secondaryInk)
            .background(
                on ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(.regularMaterial),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("musclemap-\(label.lowercased())")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
