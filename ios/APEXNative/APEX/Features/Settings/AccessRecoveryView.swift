import SwiftUI

/// A truthful escape surface for the beta build when server-owned access
/// cannot be confirmed. StoreKit and price presentation belong to the later
/// commerce phase; this screen only retries the server fact or lets the person
/// leave the account safely.
struct AccessRecoveryView: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var entitlements = EntitlementStore.shared
    @State private var statusMessage: String?
    @State private var checking = false
    @State private var showingCoachInvitation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onClose: (() -> Void)?

    private let primaryInk = Color.white
    private let secondaryInk = Color.white.opacity(0.7)

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let onClose {
                    HStack {
                        Spacer()
                        Button(language.text("Close"), action: onClose)
                            .font(APEXFont.body(14, weight: .bold))
                            .foregroundStyle(primaryInk)
                    }
                }

                headline
                recoveryActions
                if showingCoachInvitation && entitlements.access != .updateRequired {
                    CoachInvitationAcceptanceCard {
                        Task { await resumeAfterGrant() }
                    }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Text(language.text("Purchases are not available in this TestFlight build."))
                    .font(APEXFont.body(11, weight: .medium))
                    .foregroundStyle(secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .background { JewelBackdrop(animated: !reduceMotion) }
        .foregroundStyle(primaryInk)
        .preferredColorScheme(.dark)
    }

    private var headline: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, APEXColor.cyan.opacity(0.7), APEXColor.violet.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: APEXColor.cyan.opacity(0.45), radius: 20)
                .accessibilityHidden(true)

            Text(language.text("Access needs attention"))
                .font(APEXFont.display(29))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(language.text(recoveryBody))
                .font(APEXFont.body(13, weight: .medium))
                .foregroundStyle(secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var recoveryBody: String {
        switch entitlements.recoveryReason {
        case .updateRequired:
            "This version of APEX needs an update before it can open this account. Your account data has not been changed."
        case .revoked:
            "Access for this account has been revoked. Your account data has not been changed."
        case .expired:
            "Access for this account has expired. Your account data has not been changed."
        case .locked:
            "This account does not currently have access. Your account data has not been changed."
        case .unavailable, nil:
            "APEX could not confirm access for this account. Your account data has not been changed."
        }
    }

    private var recoveryActions: some View {
        FacetPanel(radius: 24, padding: 17) {
            VStack(spacing: 12) {
                Button {
                    guard let operation = session.accountOperationLease() else {
                        statusMessage = language.text("Sign in again to check access.")
                        return
                    }
                    Task { await checkAccess(operation: operation) }
                } label: {
                    HStack(spacing: 9) {
                        if checking { ProgressView().tint(.white) }
                        Text(language.text("Check access again"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.teal))
                .disabled(checking)

                if entitlements.access != .updateRequired {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            showingCoachInvitation.toggle()
                        }
                    } label: {
                        Text(language.text("Accept coach invitation"))
                            .font(APEXFont.body(14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(primaryInk)
                    .accessibilityIdentifier("access-recovery-coach-invitation")
                }

                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Text(language.text("Sign out"))
                        .font(APEXFont.body(14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(primaryInk)

                if let statusMessage {
                    Text(statusMessage)
                        .font(APEXFont.body(11, weight: .medium))
                        .foregroundStyle(APEXColor.amber)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(statusMessage)
                }
            }
        }
    }

    @MainActor
    private func checkAccess(operation: AccountOperationLease) async {
        guard session.accountOperationIsCurrent(operation) else { return }
        checking = true
        statusMessage = nil
        defer {
            if session.accountOperationIsCurrent(operation) { checking = false }
        }

        do {
            try await session.refreshAccountAccess(expectedUserID: operation.ownerID)
            guard session.accountOperationIsCurrent(operation) else { return }
            guard entitlements.resolvedUserID == operation.ownerID,
                  entitlements.isUnlocked else {
                statusMessage = language.text("Access is still unavailable. Try again when online, or sign out safely.")
                return
            }
            try await session.resumePrivateWorkAfterAccessRecovery(operation: operation)
            guard session.accountOperationIsCurrent(operation) else { return }
            onClose?()
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            statusMessage = language.text("Access is still unavailable. Try again when online, or sign out safely.")
        }
    }

    @MainActor
    private func resumeAfterGrant() async {
        guard let operation = session.accountOperationLease(),
              entitlements.resolvedUserID == operation.ownerID,
              entitlements.isUnlocked else { return }
        do {
            try await session.resumePrivateWorkAfterAccessRecovery(operation: operation)
            guard session.accountOperationIsCurrent(operation) else { return }
            onClose?()
        } catch is CancellationError {
            return
        } catch {
            guard session.accountOperationIsCurrent(operation) else { return }
            statusMessage = language.text("Access was restored, but APEX could not refresh your account yet. Try again when online.")
        }
    }
}
