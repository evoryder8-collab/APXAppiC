import SwiftUI
import UIKit

/*
 * A pan that only ever claims sideways movement.
 *
 * SwiftUI's DragGesture recognises in every direction and then leaves it to the
 * handler to ignore what it does not want. Inside a scroll view that is too
 * late: by the time the handler decides the drag was vertical, the gesture has
 * already taken the touch and the page has stopped moving under the finger.
 * A finger that lands on a meal by accident should never cost the person their
 * scroll.
 *
 * UIKit can say no earlier. This recogniser watches the first movement and, if
 * it is more vertical than sideways, fails outright. Failing is what matters:
 * the enclosing scroll view picks the touch straight back up, mid-flick, with
 * nothing lost.
 */
final class DirectionalPanGestureRecognizer: UIPanGestureRecognizer {
    /// How much more sideways than vertical the first movement has to be.
    var horizontalBias: CGFloat = 1.4
    /// Movement below this is still undecided, so nothing is claimed yet.
    var decisionThreshold: CGFloat = 10

    private var start: CGPoint?
    private var decided = false

    override func reset() {
        super.reset()
        start = nil
        decided = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        start = touches.first?.location(in: view?.window)
        decided = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard !decided, let start, let current = touches.first?.location(in: view?.window) else { return }
        let dx = abs(current.x - start.x)
        let dy = abs(current.y - start.y)
        guard max(dx, dy) > decisionThreshold else { return }
        decided = true
        if dy * horizontalBias >= dx {
            /* Vertical: this belongs to the scroll view, not to us. */
            state = .failed
        }
    }
}

/*
 * Everything a meal row does with a finger, in one place.
 *
 * Tap, sideways swipe and hold-to-move all live on the same UIKit view, so they
 * arbitrate with each other rather than racing SwiftUI's gesture system, and
 * anything vertical is handed straight back to the scroll view.
 */
struct MealRowGestures: UIViewRepresentable {
    var onTap: () -> Void
    var onSwipeChanged: (CGFloat) -> Void
    var onSwipeEnded: (CGFloat, CGFloat) -> Void
    var onHoldChanged: (CGFloat) -> Void
    var onHoldEnded: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = DirectionalPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        /* A deliberate hold, not a pause: resting a finger before scrolling
           must not start moving the meal. */
        let hold = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleHold(_:))
        )
        hold.minimumPressDuration = 0.55
        hold.allowableMovement = 6
        hold.delegate = context.coordinator
        view.addGestureRecognizer(hold)

        context.coordinator.hold = hold
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onSwipeChanged = onSwipeChanged
        context.coordinator.onSwipeEnded = onSwipeEnded
        context.coordinator.onHoldChanged = onHoldChanged
        context.coordinator.onHoldEnded = onHoldEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onSwipeChanged: onSwipeChanged,
            onSwipeEnded: onSwipeEnded,
            onHoldChanged: onHoldChanged,
            onHoldEnded: onHoldEnded
        )
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void
        var onSwipeChanged: (CGFloat) -> Void
        var onSwipeEnded: (CGFloat, CGFloat) -> Void
        var onHoldChanged: (CGFloat) -> Void
        var onHoldEnded: (CGFloat) -> Void
        weak var hold: UILongPressGestureRecognizer?
        private var holding = false

        init(
            onTap: @escaping () -> Void,
            onSwipeChanged: @escaping (CGFloat) -> Void,
            onSwipeEnded: @escaping (CGFloat, CGFloat) -> Void,
            onHoldChanged: @escaping (CGFloat) -> Void,
            onHoldEnded: @escaping (CGFloat) -> Void
        ) {
            self.onTap = onTap
            self.onSwipeChanged = onSwipeChanged
            self.onSwipeEnded = onSwipeEnded
            self.onHoldChanged = onHoldChanged
            self.onHoldEnded = onHoldEnded
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard !holding else { return }
            onTap()
        }

        @objc func handlePan(_ recognizer: DirectionalPanGestureRecognizer) {
            /* While the meal is being moved, sideways travel is not a reveal. */
            guard !holding else { return }
            let translation = recognizer.translation(in: recognizer.view).x
            switch recognizer.state {
            case .changed:
                onSwipeChanged(translation)
            case .ended, .cancelled:
                /* Velocity settles where a flick was heading, so a quick swipe
                   opens the card instead of falling back to closed. */
                onSwipeEnded(translation, recognizer.velocity(in: recognizer.view).x)
            default:
                break
            }
        }

        @objc func handleHold(_ recognizer: UILongPressGestureRecognizer) {
            /*
             * Window coordinates, converted by the timeline against its own
             * frame. Reporting against the recogniser's superview measured the
             * finger inside the row, which is not where the timeline thinks it
             * is, so the meal leapt hours away the instant the hold began.
             * Absolute also means the row cannot chase itself as it moves.
             */
            let y = recognizer.location(in: nil).y
            switch recognizer.state {
            case .began:
                holding = true
                onHoldChanged(y)
            case .changed:
                onHoldChanged(y)
            case .ended, .cancelled, .failed:
                if holding { onHoldEnded(y) }
                holding = false
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            /* The hold drives the move on its own; the pan must not also fire. */
            !(gestureRecognizer is DirectionalPanGestureRecognizer && other === hold)
        }
    }
}
