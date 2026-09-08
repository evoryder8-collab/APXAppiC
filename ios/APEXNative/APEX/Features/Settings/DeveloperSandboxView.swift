import SwiftUI
import UIKit

/// Owns a disposable session; the authenticated session stays mounted underneath.
struct DeveloperSandboxView: View {
    let role: DeveloperSandboxRole
    let owner: AppSession
    let returnToAccount: () -> Void
    @State private var preview: AppSession

    init(role: DeveloperSandboxRole, owner: AppSession, returnToAccount: @escaping () -> Void) {
        self.role = role
        self.owner = owner
        self.returnToAccount = returnToAccount
        _preview = State(initialValue: AppSession(developerSandboxRole: role))
    }

    var body: some View {
        Group {
            switch preview.route {
            case .induction: InductionView()
            case .consent: ConsentView()
            case .portal: PortalShellView()
            default: ProgressView().task { leavePreview() }
            }
        }
        .environment(preview)
        .environment(\.developerSandboxPreview, true)
        .defaultAppStorage(preview.defaults)
        .safeAreaInset(edge: .top) { Color.clear.frame(height: 48) }
        .background(DeveloperSandboxChrome(role: role, exit: leavePreview))
        .onChange(of: owner.canOpenDeveloperSandbox) { _, allowed in
            if !allowed { leavePreview() }
        }
    }

    private func leavePreview() {
        preview.invalidateDeveloperSandbox()
        returnToAccount()
    }
}

struct DeveloperSandboxNotice: View {
    var body: some View {
        Label(LanguageState.shared.text("Sample mode: device connections, photos, purchases and notifications are unavailable. Changes stay in this preview."), systemImage: "testtube.2")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding()
    }
}

private struct DeveloperSandboxPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var developerSandboxPreview: Bool {
        get { self[DeveloperSandboxPreviewKey.self] }
        set { self[DeveloperSandboxPreviewKey.self] = newValue }
    }
}

struct DeveloperSandboxSheetClearance: ViewModifier {
    @Environment(\.developerSandboxPreview) private var preview
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if preview { Color.clear.frame(height: 48) }
        }
    }
}

/// Non-key, scene-local chrome remains reachable over sheets and workout covers.
/// Only the small top strip intercepts input; the rest passes to the app.
private struct DeveloperSandboxChrome: UIViewRepresentable {
    let role: DeveloperSandboxRole
    let exit: () -> Void

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.content = AnyView(chrome)
        return anchor
    }

    func updateUIView(_ view: Anchor, context: Context) {
        view.content = AnyView(chrome)
        view.updateChrome()
    }

    static func dismantleUIView(_ view: Anchor, coordinator: ()) { view.removeChrome() }

    private var chrome: some View {
        HStack(spacing: 12) {
            Label(LanguageState.shared.shortText(role.titleKey), systemImage: "testtube.2")
                .font(.caption.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Button(action: exit) {
                Label(LanguageState.shared.shortText("My account"), systemImage: "arrow.uturn.backward")
                    .font(.caption.weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.vertical, 12)
            }
            .accessibilityIdentifier("developer-sandbox-return")
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(.regularMaterial)
    }

    final class Anchor: UIView {
        var content = AnyView(EmptyView())
        private var chromeWindow: ChromeWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { updateChrome() }
        }

        func updateChrome() {
            guard let scene = window?.windowScene else { return }
            let overlay = chromeWindow ?? ChromeWindow(windowScene: scene)
            overlay.windowLevel = .alert + 1
            overlay.backgroundColor = .clear
            overlay.frame = scene.coordinateSpace.bounds
            let top = window?.safeAreaInsets.top ?? 0
            overlay.interactiveStrip = CGRect(x: 0, y: top, width: overlay.bounds.width, height: 48)
            let controller = UIHostingController(rootView: VStack(spacing: 0) {
                Color.clear.frame(height: top)
                content
                Spacer(minLength: 0)
            })
            controller.safeAreaRegions = []
            controller.view.backgroundColor = .clear
            overlay.rootViewController = controller
            overlay.isHidden = false
            chromeWindow = overlay
        }

        func removeChrome() {
            chromeWindow?.isHidden = true
            chromeWindow?.rootViewController = nil
            chromeWindow = nil
        }
    }

    final class ChromeWindow: UIWindow {
        var interactiveStrip = CGRect.zero

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard interactiveStrip.contains(point) else { return nil }
            return super.hitTest(point, with: event)
        }
    }
}
