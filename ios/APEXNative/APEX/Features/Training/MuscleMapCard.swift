import SwiftUI
import UIKit
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

    var spinning = !APEXRuntimeEnvironment.usesLocalUITestFixture()
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
    @Environment(AppSession.self) private var session

    let dayType: String
    var sessionDate: String? = nil
    var exerciseNames: [String] = []
    /* 30% taller than it was. The session title sat across the figure's neck,
       because the label and the model were competing for the same band of the
       card. The extra height is headroom for the title and the tooltip. */
    var height: CGFloat = 442
    var accent: Color = APEXColor.violet
    var eyebrow: String?
    var focus: String?

    @State private var controller = MuscleMapController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = LanguageState.shared
    @State private var showBriefing = false

    private var decorativeMotionEnabled: Bool {
        !reduceMotion && !APEXRuntimeEnvironment.usesLocalUITestFixture()
    }

    var body: some View {
        MuscleMapView(
            dayType: dayType,
            exerciseNames: exerciseNames,
            xray: controller.xray,
            controller: controller
        )
        .accessibilityIdentifier("training-muscle-signal")
        .frame(height: height)
        /* Behind the figure, never in front of it: the model has to stay the
           brightest thing in the card. */
        .background(alignment: .center) {
            ModelAura(accent: accent, animated: decorativeMotionEnabled)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            HorizontalTurnSurface { delta in
                controller.turn(by: Double(delta) * 0.55)
            }
            .accessibilityHidden(true)
        }
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
        /* Top right, opposite the session title, so the figure itself stays
           clear. The model shows which muscles light up but never says why they
           were chosen; this is that half. */
        .overlay(alignment: .topTrailing) {
            Button {
                showBriefing = true
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, accent)
                    /* A halo and a slow gleam across the glyph. A flat icon in a
                       corner reads as decoration; this reads as a control. */
                    .background {
                        Circle()
                            .fill(accent.opacity(0.28))
                            .frame(width: 42, height: 42)
                            .blur(radius: 9)
                    }
                    .overlay {
                        TooltipGleam(active: decorativeMotionEnabled)
                            .mask(
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 22))
                            )
                    }
                    .padding(16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("What this session trains"))
            .accessibilityIdentifier("session-briefing-open")
        }
        .sheet(isPresented: $showBriefing) {
            SessionBriefingSheet(
                briefing: SessionBriefing.briefing(dayType: dayType, exercises: exerciseNames),
                knowledge: SessionBriefing.knowledge(context: SessionBriefing.knowledgeContext(
                    dayType: dayType,
                    exerciseNames: exerciseNames,
                    date: sessionDate,
                    data: session.data
                )),
                accent: accent
            ) { showBriefing = false }
            .apexTransientSheet(.fraction(0.66))
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

/// UIKit can decline a pan before it begins. SwiftUI's `DragGesture` cannot,
/// so even a vertical drag it later ignored still prevented the parent phase
/// page from scrolling. Horizontal turns remain interactive while vertical
/// movement is handed straight to the enclosing `ScrollView`.
private struct HorizontalTurnSurface: UIViewRepresentable {
    let onDelta: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDelta: onDelta)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDelta = onDelta
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDelta: (CGFloat) -> Void

        init(onDelta: @escaping (CGFloat) -> Void) {
            self.onDelta = onDelta
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed,
                  let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)
            onDelta(translation.x)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
