import Charts
import SwiftUI

struct AvatarView: View {
    @Environment(AppSession.self) private var session
    @State private var animate = false
    @State private var language = LanguageState.shared

    private var snapshot: RPGSnapshot? {
        session.data.snapshots.sorted { $0.date > $1.date }.first
    }

    private var stats: [AvatarStat] {
        guard let snapshot else {
            return [
                .init(name: "Overall Fitness Level", value: 1, color: APEXColor.violet, icon: "sparkles"),
                .init(name: "Health", value: 1, color: APEXColor.green, icon: "heart.fill"),
                .init(name: "Joint Health", value: 1, color: APEXColor.amber, icon: "figure.flexibility"),
                .init(name: "Flexibility", value: 1, color: APEXColor.teal, icon: "figure.cooldown"),
                .init(name: "Endurance & VO₂ max", value: 1, color: APEXColor.cyan, icon: "lungs.fill"),
                .init(name: "Upper Body Strength", value: 1, color: APEXColor.violet, icon: "figure.strengthtraining.traditional"),
                .init(name: "Lower Body Strength", value: 1, color: APEXColor.amberDeep, icon: "figure.stairs"),
            ]
        }
        return [
            .init(name: "Overall Fitness Level", value: snapshot.overall, color: APEXColor.violet, icon: "sparkles"),
            .init(name: "Health", value: snapshot.health, color: APEXColor.green, icon: "heart.fill"),
            .init(name: "Joint Health", value: snapshot.joint, color: APEXColor.amber, icon: "figure.flexibility"),
            .init(name: "Flexibility", value: snapshot.flexibility, color: APEXColor.teal, icon: "figure.cooldown"),
            .init(name: "Endurance & VO₂ max", value: snapshot.endurance, color: APEXColor.cyan, icon: "lungs.fill"),
            .init(name: "Upper Body Strength", value: snapshot.strengthUpper, color: APEXColor.violet, icon: "figure.strengthtraining.traditional"),
            .init(name: "Lower Body Strength", value: snapshot.strengthLower, color: APEXColor.amberDeep, icon: "figure.stairs"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                APEXTopBar(profile: session.profile) {
                    session.navigationPath.append(.settings)
                }

                AvatarHero(profile: session.profile, overall: snapshot?.overall ?? 1)

                GlassCard(radius: 32, padding: 20) {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your performance body")
                                    .font(APEXFont.display(26))
                                Text("Clear signals, no mystery score")
                                    .font(APEXFont.body(13, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            Spacer()
                            Text(language.format("LV %d", Int((snapshot?.overall ?? 1).rounded())))
                                .font(APEXFont.mono(12))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(APEXColor.violet.gradient, in: Capsule())
                        }

                        ForEach(stats) { stat in
                            AvatarStatRow(stat: stat, animate: animate)
                        }
                    }
                }

                NavigationLink(value: PortalDestination.visualProgress) {
                    HStack(spacing: 15) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(APEXColor.violet.gradient, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Private Visual Progress")
                                .font(APEXFont.display(20))
                            Text("Before, after and the stats behind the change")
                                .font(APEXFont.body(12, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(APEXColor.ink)
                    .padding(17)
                    .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 29, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).stroke(.white.opacity(0.9)))
                }
                .buttonStyle(.plain)

                GlassCard(radius: 32, padding: 21) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("What your body needs now", systemImage: "sparkles")
                            .font(APEXFont.display(23))
                        Text(assessment)
                            .font(APEXFont.body(15, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .lineSpacing(4)
                    }
                }

                if session.data.snapshots.count > 1 {
                    GlassCard(radius: 32, padding: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Evolution")
                                .font(APEXFont.display(22))
                            Chart(session.data.snapshots.sorted { $0.date < $1.date }.suffix(30)) { point in
                                LineMark(x: .value("Date", point.date), y: .value("Overall", point.overall))
                                    .foregroundStyle(APEXColor.violet.gradient)
                                    .interpolationMethod(.catmullRom)
                                AreaMark(x: .value("Date", point.date), y: .value("Overall", point.overall))
                                    .foregroundStyle(APEXColor.violet.opacity(0.12).gradient)
                            }
                            .chartYAxis(.hidden)
                            .frame(height: 150)
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 28)
        }
        .navigationTitle(session.profile?.displayName ?? "Avatar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.15)) { animate = true }
        }
    }

    private var assessment: String {
        guard let weakest = stats.min(by: { $0.value < $1.value }),
              let strongest = stats.max(by: { $0.value < $1.value }) else { return language.text("Complete your first logs to give the Avatar reliable signals.") }
        return language.format(
            "%@ is currently your clearest asset. %@ is the most useful next opportunity, not a failure. APEX will improve it through consistent training, recovery and nutrition signals while preserving what is already strong.",
            language.text(strongest.name),
            language.text(weakest.name)
        )
    }
}

private struct AvatarStat: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
    let icon: String
}

private struct AvatarStatRow: View {
    @State private var language = LanguageState.shared
    let stat: AvatarStat
    let animate: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(language.text(stat.name), systemImage: stat.icon)
                    .font(APEXFont.body(13, weight: .bold))
                Spacer()
                Text("\(Int(stat.value.rounded()))")
                    .font(APEXFont.mono(13))
                    .foregroundStyle(stat.color)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(APEXColor.ink.opacity(0.07))
                    Capsule()
                        .fill(stat.color.gradient)
                        .frame(width: animate ? proxy.size.width * min(max(stat.value / 100, 0.025), 1) : 0)
                        .shadow(color: stat.color.opacity(0.34), radius: 8)
                }
            }
            .frame(height: 10)
        }
    }
}

private struct AvatarHero: View {
    @State private var language = LanguageState.shared
    let profile: Profile?
    let overall: Double
    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.03, green: 0.04, blue: 0.10), Color(red: 0.11, green: 0.05, blue: 0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(APEXColor.violet.opacity(0.35), lineWidth: 1)
                .frame(width: pulse ? 245 : 215)
                .opacity(pulse ? 0.15 : 0.7)
            Circle()
                .fill(APEXColor.violet.opacity(0.16))
                .frame(width: 205, height: 205)
                .blur(radius: 20)
            PortraitImage(name: profile?.persona.portraitName ?? "constantine")
                .scaledToFit()
                .frame(height: 285)
                .mask(RoundedRectangle(cornerRadius: 38, style: .continuous))
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text((profile?.displayName ?? "APEX").uppercased())
                            .font(APEXFont.mono(11))
                            .tracking(2)
                        Text(language.format("Overall %d", Int(overall.rounded())))
                            .font(APEXFont.display(22))
                    }
                    Spacer()
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 27, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(20)
                .background(.black.opacity(0.26))
            }
        }
        .frame(height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .shadow(color: APEXColor.violet.opacity(0.22), radius: 30, y: 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
