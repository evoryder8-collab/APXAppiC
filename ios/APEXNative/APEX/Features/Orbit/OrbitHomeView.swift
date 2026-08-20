import MapKit
import SwiftUI
import UIKit

struct OrbitHomeView: View {
    @Environment(AppSession.self) private var session
    @State private var location = OrbitLocationManager.shared
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var language = LanguageState.shared
    @State private var moreExpanded = false
    @State private var showDeleteConfirmation = false
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                APEXTopBar(profile: session.profile) {
                    session.navigationPath.append(.settings)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(language.text("APEX ORBIT · RUN INTELLIGENCE"))
                        .font(APEXFont.mono(10))
                        .tracking(1.8)
                        .foregroundStyle(APEXColor.cyan)
                    Text(language.text("The right run,\nfor this body, today."))
                        .font(APEXFont.display(36))
                    Text(language.text(recommendationReason))
                        .font(APEXFont.body(14, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)

                OrbitMapHero(position: $mapPosition, samples: location.samples)

                GlassCard(radius: 32, padding: 21) {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(language.format("Today · %@", language.text(recommendedMission).uppercased(with: language.language.locale)))
                                    .font(APEXFont.mono(10))
                                    .tracking(1.4)
                                    .foregroundStyle(APEXColor.cyan)
                                Text(language.text(recommendedPrescription))
                                    .font(APEXFont.display(25))
                            }
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 25))
                                .foregroundStyle(APEXColor.cyan)
                        }

                        Text(language.text(recommendationReason))
                            .font(APEXFont.body(13, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)

                        NavigationLink {
                            LiveRunView(
                                mission: recommendedMission,
                                plannedRoute: recoverableRoute,
                                campaignSessionID: todayCampaignSession?.id
                            )
                        } label: {
                            Label(
                                language.text(location.hasRecoverableRun ? "Continue interrupted run" : "Start today's run"),
                                systemImage: location.hasRecoverableRun ? "arrow.clockwise.circle.fill" : "play.fill"
                            )
                        }
                        .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.cyan))
                    }
                }

                HStack(spacing: 12) {
                    OrbitActionCard(icon: "map.fill", title: "Plan", color: APEXColor.violet) {
                        RoutePlannerView()
                    }
                    OrbitActionCard(icon: "figure.run", title: "Free run", color: APEXColor.cyan) {
                        LiveRunView(mission: "Free run")
                    }
                    OrbitActionCard(icon: "moon.stars.fill", title: "Campaign", color: APEXColor.amber) {
                        MarathonCampaignView()
                    }
                }

                OrbitContextCard()

                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text(language.text("Recent runs"))
                            .font(APEXFont.display(25))
                        Spacer()
                        NavigationLink("Library") { OrbitLibraryView() }
                            .font(APEXFont.body(13, weight: .bold))
                    }
                    if session.data.orbitRuns.isEmpty {
                        GlassCard(radius: 26, padding: 19) {
                            HStack(spacing: 13) {
                                Image(systemName: "figure.run.circle")
                                    .font(.system(size: 34))
                                    .foregroundStyle(APEXColor.cyan)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(language.text("Your first route becomes your baseline"))
                                        .font(APEXFont.display(17))
                                    Text(language.text("Orbit will interpret the mission, pacing and recovery cost after you finish."))
                                        .font(APEXFont.body(12, weight: .medium))
                                        .foregroundStyle(APEXColor.secondaryInk)
                                }
                            }
                        }
                    } else {
                        ForEach(session.data.orbitRuns.prefix(3)) { run in
                            RunHistoryRow(run: run)
                        }
                    }
                }

                GlassCard(radius: 29, padding: 17) {
                    DisclosureGroup(isExpanded: $moreExpanded) {
                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                NavigationLink {
                                    OrbitLibraryView()
                                } label: {
                                    OrbitMoreLink(title: "Saved routes and runs", icon: "map.fill")
                                }
                                NavigationLink {
                                    OrbitScienceView()
                                } label: {
                                    OrbitMoreLink(title: "Science ledger", icon: "books.vertical.fill")
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Label(language.text("Private by design"), systemImage: "lock.shield.fill")
                                    .font(APEXFont.display(17))
                                    .foregroundStyle(APEXColor.ink)
                                Text(language.text("Routes, tracks, readiness answers and campaign notes remain user-scoped. There is no public feed, leaderboard or follower graph."))
                                    .font(APEXFont.body(11, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)

                                HStack(spacing: 10) {
                                    Button {
                                        do { shareURL = try session.exportOrbitData() }
                                        catch { session.alertMessage = error.localizedDescription }
                                    } label: {
                                        Label(language.text("Export Orbit data"), systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.bordered)

                                    Button(role: .destructive) {
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label(language.text("Delete Orbit data"), systemImage: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .font(APEXFont.body(11, weight: .bold))
                            }
                            .padding(14)
                            .background(.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .padding(.top, 14)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(language.text("More from Orbit"))
                                .font(APEXFont.display(20))
                            Text(language.text("Routes, science and private data controls"))
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                    }
                    .tint(APEXColor.cyan)
                }
            }
            .padding(18)
            .padding(.bottom, 28)
.dockClearance()
        }
        .navigationTitle("Orbit")  // brand name
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            location.requestLocation()
            if let ownerID = session.profile?.userID { location.restoreDraft(for: ownerID) }
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL { OrbitShareSheet(items: [shareURL]) }
        }
        .confirmationDialog(
            language.text("Permanently delete all Orbit routes, runs, campaign answers and shoe records for this profile?"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("Delete permanently"), role: .destructive) {
                Task { await session.deleteAllOrbitData() }
            }
            Button(language.text("Cancel"), role: .cancel) {}
        }
    }

    private var recoverableRoute: OrbitRouteRecord? {
        guard let routeID = location.draftRouteID else { return nil }
        return session.data.orbitRoutes.first { $0.id == routeID }
    }

    private var todayCampaignSession: OrbitCampaignSession? {
        guard let campaign = session.data.orbitCampaigns.first(where: { $0.status == "active" }) else { return nil }
        return session.data.orbitCampaignSessions.first {
            $0.campaignID == campaign.id && $0.date == Date().apexDateKey && $0.status == "planned"
        }
    }

    private var recommendedMission: String {
        if location.hasRecoverableRun { return location.draftMission ?? "Free run" }
        if let mission = todayCampaignSession?.adapted["mission"]?.stringValue {
            return mission.replacingOccurrences(of: "_", with: " ").capitalized
        }
        let completedLegsYesterday = session.data.workoutSessions.contains { workout in
            guard workout.completed,
                  let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)?.apexDateKey,
                  workout.date == yesterday,
                  let day = session.data.programDays.first(where: { $0.id == workout.programDayID })
            else { return false }
            return ["legs_a", "legs_b"].contains(day.dayType)
        }
        return completedLegsYesterday ? "Recovery" : session.data.orbitRuns.isEmpty ? "Aerobic base" : "Easy"
    }

    private var recommendedPrescription: String {
        if location.hasRecoverableRun {
            return language.format("%d km · paused and protected", Int(location.distanceM / 1_000))
        }
        if let duration = todayCampaignSession?.adapted["duration_min"]?.numberValue {
            return language.format("%d minutes · campaign session", Int(duration))
        }
        return language.text(recommendedMission == "Recovery" ? "28 minutes easy" : "42 minutes conversational")
    }

    private var recommendationReason: String {
        if location.hasRecoverableRun {
            return "Your active GPS track was recovered on this iPhone. Continue when ready or discard it from the live run screen."
        }
        if let why = todayCampaignSession?.adapted["why"]?.stringValue { return language.text(why) }
        if recommendedMission == "Recovery" {
            return "Yesterday included demanding lower-body work, so Orbit protects adaptation with a short, controlled run."
        }
        if session.data.orbitRuns.isEmpty {
            return "A calm aerobic baseline gives Orbit useful data without forcing a performance test on day one."
        }
        return "Recent workload supports easy aerobic volume without compromising your strength plan."
    }
}

private struct OrbitMoreLink: View {
    @State private var language = LanguageState.shared
    let title: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(APEXColor.cyan)
            Text(language.text(title))
                .font(APEXFont.body(11, weight: .bold))
                .foregroundStyle(APEXColor.ink)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct OrbitShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct OrbitMapHero: View {
    @State private var language = LanguageState.shared
    @Binding var position: MapCameraPosition
    let samples: [OrbitLocationSample]

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
                UserAnnotation()
                if samples.count > 1 {
                    MapPolyline(coordinates: samples.map(\.coordinate))
                        .stroke(APEXColor.cyan.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapUserLocationButton()
                MapScaleView()
            }

            HStack {
                Label(language.text("NATIVE MAPKIT"), systemImage: "location.fill")
                    .font(APEXFont.mono(9))
                    .tracking(1.2)
                Spacer()
                Text(language.text("GPS READY"))
                    .font(APEXFont.mono(9))
                    .tracking(1.2)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(.black.opacity(0.52))
        }
        .frame(height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 35, style: .continuous).stroke(.white.opacity(0.72)))
        .shadow(color: APEXColor.cyan.opacity(0.18), radius: 24, y: 12)
    }
}

private struct OrbitActionCard<Destination: View>: View {
    @State private var language = LanguageState.shared
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let destination: Destination

    init(icon: String, title: String, color: Color, @ViewBuilder destination: () -> Destination) {
        self.icon = icon
        self.title = title
        self.color = color
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color.gradient, in: Circle())
                Text(language.text(title))
                    .font(APEXFont.body(12, weight: .bold))
                    .foregroundStyle(APEXColor.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.9)))
        }
        .buttonStyle(.plain)
    }
}

private struct OrbitContextCard: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared

    var body: some View {
        GlassCard(radius: 29, padding: 18) {
            VStack(alignment: .leading, spacing: 13) {
                Text(language.text("APEX context"))
                    .font(APEXFont.display(21))
                HStack(spacing: 14) {
                    context(
                        "WEEK",
                        language.format("%.1f km", weekDistance),
                        "calendar"
                    )
                    context("LAST RUN", lastRun, "clock")
                    context("STRENGTH", "\(strengthCount)", "dumbbell")
                }
            }
        }
    }

    private var weekDistance: Double {
        session.data.orbitRuns.filter { run in
            guard let date = ISO8601DateFormatter.apexDateOnly.date(from: run.localDate) else { return false }
            return date >= (Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast)
        }.reduce(0) { total, run in
            total + ((run.metrics["distance_m"]?.numberValue ?? 0) / 1_000)
        }
    }

    private var lastRun: String {
        guard let date = session.data.orbitRuns.first?.localDate,
              let parsed = ISO8601DateFormatter.apexDateOnly.date(from: date) else { return "None" }
        return parsed.formatted(.relative(presentation: .named).locale(language.language.locale))
    }

    private var strengthCount: Int {
        session.data.workoutSessions.filter { $0.completed && $0.date >= (Calendar.current.date(byAdding: .day, value: -7, to: .now)?.apexDateKey ?? "") }.count
    }

    private func context(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(APEXColor.cyan)
            Text(language.text(title)).font(APEXFont.mono(8)).foregroundStyle(APEXColor.secondaryInk)
            Text(value).font(APEXFont.display(15))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RunHistoryRow: View {
    @State private var language = LanguageState.shared
    let run: OrbitRunRecord

    var body: some View {
        GlassCard(radius: 25, padding: 16) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(APEXColor.cyan.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text(run.mission.replacingOccurrences(of: "_", with: " ").capitalized))
                        .font(APEXFont.display(17))
                    Text(language.format("%.2f km · %@", (run.metrics["distance_m"]?.numberValue ?? 0) / 1_000, language.dateKey(run.localDate)))
                        .font(APEXFont.mono(10))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
        }
    }
}
