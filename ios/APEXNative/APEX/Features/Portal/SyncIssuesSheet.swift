import SwiftUI

struct SyncIssuesButton: View {
    let count: Int
    let action: () -> Void
    @State private var language = LanguageState.shared

    var body: some View {
        Button(action: action) {
            Label(
                "\(count) \(language.text("needs attention"))",
                systemImage: "exclamationmark.icloud"
            )
            .font(APEXFont.mono(9))
            .foregroundStyle(APEXColor.danger)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(language.text("Shows which changes failed and why."))
    }
}

struct SyncIssuesSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.text("These changes could not be synced."))
                            .font(APEXFont.body(15, weight: .bold))
                        Text(language.text("They stay listed here so nothing disappears silently."))
                            .font(APEXFont.body(13))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    .padding(.vertical, 4)
                }

                ForEach(session.failedSyncOperations) { failure in
                    SyncIssueRow(failure: failure, language: language)
                }
            }
            .navigationTitle(language.text("Sync issues"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Done")) { dismiss() }
                }
            }
            .task { await session.refreshFailedSyncOperations() }
        }
    }
}

private struct SyncIssueRow: View {
    let failure: FailedOfflineOperation
    let language: LanguageState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(language.text(subjectKey))
                    .font(APEXFont.body(15, weight: .bold))
                Spacer(minLength: 12)
                Text(failure.failedAt.formatted(
                    .dateTime
                        .locale(language.language.locale)
                        .day()
                        .month(.abbreviated)
                        .hour()
                        .minute()
                ))
                    .font(APEXFont.mono(10))
                    .foregroundStyle(APEXColor.secondaryInk)
            }

            Text(language.text(explanationKey))
                .font(APEXFont.body(13))
                .foregroundStyle(APEXColor.secondaryInk)

            DisclosureGroup(language.text("Technical reason")) {
                Text(failure.reason)
                    .font(APEXFont.mono(11))
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
            .font(APEXFont.body(12, weight: .bold))
            .accessibilityIdentifier(
                "sync-technical-reason-\(failure.id.uuidString.lowercased())"
            )
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    private var subjectKey: String {
        switch failure.operation.rpcFunction ?? failure.operation.table {
        case "log_structured_meal", "logged_meals", "logged_food_entries", "meal_logs":
            "Meal change"
        case "workout_sessions", "workout_logs":
            "Workout change"
        case "health_metrics":
            "Health metric"
        case "rpg_snapshots":
            "Progress update"
        case "activity_logs", "imported_activities":
            "Activity change"
        case "profile", "settings":
            "Profile change"
        default:
            "App change"
        }
    }

    private var explanationKey: String {
        switch SyncFailurePolicy.category(persistedReason: failure.reason) {
        case .authentication:
            return "Your sign-in expired before this change could upload. APEX will retry it after authentication recovers."
        case .duplicate:
            return "The server already has this change."
        case .missingDependency:
            return "A required part of this change had not synced yet."
        case .invalidValue:
            return "The server rejected a value that no longer matches its accepted format."
        case .permission:
            return "The server does not allow this type of change."
        case .rejected:
            return "The server rejected this change."
        }
    }
}
