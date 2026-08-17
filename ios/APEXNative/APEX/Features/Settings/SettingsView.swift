import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var health = HealthKitManager.shared
    @State private var language = LanguageState.shared
    @State private var showLogout = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                APEXTopBar(profile: session.profile)

                VStack(alignment: .leading, spacing: 6) {
                    Text(language.text(.settings))
                        .font(APEXFont.display(36))
                    Text("Preferences sync across your APEX clients.")
                        .font(APEXFont.body(14, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GlassCard(radius: 29, padding: 19) {
                    VStack(spacing: 0) {
                        settingsToggle("Voice coaching", icon: "waveform", value: session.data.settings?.voiceOn ?? true) { next in
                            Task { await session.updateSettings { $0.voiceOn = next } }
                        }
                        Divider().padding(.leading, 46)
                        settingsToggle("Haptic ticks", icon: "hand.tap", value: session.data.settings?.ticksOn ?? true) { next in
                            Task { await session.updateSettings { $0.ticksOn = next } }
                        }
                        Divider().padding(.leading, 46)
                        settingsToggle("Reminders", icon: "bell", value: session.data.settings?.notificationsOn ?? false) { next in
                            Task { await session.updateSettings { $0.notificationsOn = next } }
                        }
                    }
                }

                GlassCard(radius: 29, padding: 19) {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Apple Health")
                                    .font(APEXFont.display(21))
                                Text("Weight, VO₂ max, resting heart rate, workouts, steps and water")
                                    .font(APEXFont.body(12, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                        }

                        Text("Only the Health categories you allow are copied to your private APEX account so iPhone and web stay aligned. APEX never sells them or uses them for advertising.")
                            .font(APEXFont.body(11, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)

                        Button {
                            Task {
                                if let snapshot = await health.requestAccessAndImport() {
                                    await session.applyHealthSnapshot(snapshot)
                                }
                            }
                        } label: {
                            if health.isSyncing {
                                ProgressView().tint(.white)
                            } else {
                                Label(language.text(health.isAuthorized ? "Sync now" : "Connect Apple Health"), systemImage: "heart.fill")
                            }
                        }
                        .buttonStyle(APEXPrimaryButtonStyle(color: .red))

                        if let snapshot = health.lastSnapshot {
                            HStack(spacing: 16) {
                                healthMetric("WATER", snapshot.dietaryWaterL, "L")
                                healthMetric("STEPS", snapshot.steps, "")
                                healthMetric("ACTIVE", snapshot.activeEnergyKcal, "kcal")
                            }
                        }
                        if let message = health.message {
                            Text(language.text(message))
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                }

                GlassCard(radius: 29, padding: 19) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Account")
                            .font(APEXFont.display(21))
                        Text(session.profile?.displayName ?? "APEX")
                            .font(APEXFont.body(15, weight: .bold))
                        Text("Your records remain private under Supabase row-level security and are shared only between your authenticated APEX clients.")
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                        Button(role: .destructive) { showLogout = true } label: {
                            Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(APEXColor.danger)
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 25)
        }
        .navigationTitle(language.text(.settings))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(language.text(.logoutWarning), isPresented: $showLogout, titleVisibility: .visible) {
            Button(language.text(.yesLogout), role: .destructive) { Task { await session.signOut() } }
            Button(language.text(.cancel), role: .cancel) {}
        }
    }

    private func settingsToggle(
        _ title: String,
        icon: String,
        value: Bool,
        onChange: @escaping @Sendable (Bool) -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(APEXColor.violet)
                .frame(width: 34)
            Text(language.text(title))
                .font(APEXFont.body(15, weight: .semibold))
            Spacer()
            Toggle("", isOn: Binding(get: { value }, set: onChange))
                .labelsHidden()
                .tint(APEXColor.teal)
        }
        .frame(height: 52)
    }

    private func healthMetric(_ title: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(language.text(title)).font(APEXFont.mono(8)).foregroundStyle(APEXColor.secondaryInk)
            Text(value.map { language.format("%d %@", Int($0.rounded()), language.text(unit)) } ?? "—")
                .font(APEXFont.display(15))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
