import MapKit
import SwiftUI

struct LiveRunView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var location = OrbitLocationManager.shared
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showFinish = false
    @State private var showCancel = false
    @State private var debriefRun: OrbitRunRecord?
    @State private var selectedShoeID: UUID?
    @State private var language = LanguageState.shared
    let mission: String
    var plannedRoute: OrbitRouteRecord? = nil
    var campaignSessionID: UUID? = nil

    private var activeRoute: OrbitRouteRecord? {
        if let plannedRoute { return plannedRoute }
        guard let routeID = location.draftRouteID else { return nil }
        return session.data.orbitRoutes.first { $0.id == routeID }
    }

    private var effectiveMission: String {
        location.draftMission ?? mission
    }

    private var routePoints: [OrbitGeoPoint] {
        activeRoute?.geoPoints ?? []
    }

    var body: some View {
        ZStack {
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
                UserAnnotation()
                if routePoints.count > 1 {
                    MapPolyline(coordinates: routePoints.map(\.coordinate))
                        .stroke(.white.opacity(0.82), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: routePoints.map(\.coordinate))
                        .stroke(APEXColor.violet.opacity(0.82), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if location.samples.count > 1 {
                    MapPolyline(coordinates: location.samples.map(\.coordinate))
                        .stroke(APEXColor.cyan.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            LinearGradient(colors: [.black.opacity(0.54), .clear, .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button {
                        if location.state == .idle { dismiss() }
                        else { showCancel = true }
                    } label: {
                        Image(systemName: "xmark").frame(width: 45, height: 45).background(.black.opacity(0.5), in: Circle())
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text(language.text(effectiveMission).uppercased(with: language.language.locale)).font(APEXFont.mono(11)).tracking(1.4)
                        if location.weakGPS { Text(language.text("WEAK GPS")).font(APEXFont.mono(8)).foregroundStyle(APEXColor.amber) }
                    }
                    Spacer()
                    Button { position = .userLocation(followsHeading: true, fallback: .automatic) } label: {
                        Image(systemName: "location.fill").frame(width: 45, height: 45).background(.black.opacity(0.5), in: Circle())
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Spacer()

                if case .countdown(let number) = location.state {
                    Text("\(number)")
                        .font(APEXFont.display(96))
                        .foregroundStyle(.white)
                        .shadow(color: APEXColor.cyan, radius: 25)
                }

                if let guidanceMessage {
                    HStack(spacing: 9) {
                        Image(systemName: offRouteDistance == nil ? "sparkles" : "arrow.triangle.turn.up.right.diamond.fill")
                        Text(language.text(guidanceMessage))
                            .font(APEXFont.body(12, weight: .bold))
                            .lineLimit(2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 46)
                    .background(.black.opacity(0.67), in: Capsule())
                    .padding(.horizontal, 18)
                }

                VStack(spacing: 20) {
                    if location.state == .idle {
                        Menu {
                            Button(language.text("No shoe assigned")) {
                                selectedShoeID = nil
                                location.assignShoe(nil)
                            }
                            ForEach(session.data.orbitShoes.filter { $0.archived == false }) { shoe in
                                Button(shoe.name) {
                                    selectedShoeID = shoe.id
                                    location.assignShoe(shoe.id)
                                }
                            }
                        } label: {
                            Label(selectedShoeName, systemImage: "shoe.2.fill")
                                .font(APEXFont.body(11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                    }

                    HStack(spacing: 0) {
                        liveMetric(formatTime(location.elapsedSeconds), "TIME")
                        liveMetric(formatPace(location.paceSecondsPerKM), "PACE /KM")
                        liveMetric((location.distanceM / 1_000).formatted(.number.precision(.fractionLength(2)).locale(language.language.locale)), "DISTANCE KM")
                    }

                    HStack(spacing: 18) {
                        if location.state == .idle || location.state == .finished {
                            Button { location.beginCountdown() } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 29, weight: .bold))
                                    .frame(width: 78, height: 78)
                            }
                            .buttonStyle(OrbitControlStyle(color: APEXColor.cyan))
                        } else {
                            Button {
                                location.state == .paused ? location.resume() : location.pause()
                            } label: {
                                Image(systemName: location.state == .paused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 25, weight: .bold))
                                    .frame(width: 66, height: 66)
                            }
                            .buttonStyle(OrbitControlStyle(color: APEXColor.amber))

                            Button { location.markManualLap() } label: {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 19, weight: .bold))
                                    .frame(width: 58, height: 58)
                            }
                            .buttonStyle(OrbitControlStyle(color: APEXColor.violet))

                            Button { showFinish = true } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 23, weight: .bold))
                                    .frame(width: 66, height: 66)
                            }
                            .buttonStyle(OrbitControlStyle(color: APEXColor.danger))
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
                .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .padding(14)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            location.requestLocation()
            guard let ownerID = session.profile?.userID else { return }
            location.restoreDraft(for: ownerID)
            selectedShoeID = location.draftShoeID
            location.prepare(
                ownerID: ownerID,
                mission: mission,
                routeID: plannedRoute?.id,
                campaignSessionID: campaignSessionID,
                shoeID: selectedShoeID
            )
        }
        .confirmationDialog("Finish this run?", isPresented: $showFinish, titleVisibility: .visible) {
            Button(language.text("Finish and save")) {
                let endedAt = Date()
                let startedAt = location.startedAt ?? endedAt
                location.finish()
                let samples = location.samples
                let distanceM = location.distanceM
                let movingSeconds = location.movingSeconds
                let pauses = location.pauseIntervals
                let manualLaps = location.manualLapsM
                let routeID = activeRoute?.id
                Task {
                    let run = await session.saveOrbitRun(
                        mission: effectiveMission.lowercased().replacingOccurrences(of: " ", with: "_"),
                        startedAt: startedAt, endedAt: endedAt,
                        samples: samples, distanceM: distanceM,
                        movingSeconds: movingSeconds,
                        pauses: pauses,
                        manualLapsM: manualLaps,
                        routeID: routeID,
                        campaignSessionID: location.draftCampaignSessionID ?? campaignSessionID,
                        shoeID: location.draftShoeID ?? selectedShoeID
                    )
                    if let run {
                        location.clearCompletedRun()
                        debriefRun = run
                    }
                }
            }
            Button(language.text("Keep running"), role: .cancel) {}
        }
        .confirmationDialog("Cancel this run?", isPresented: $showCancel, titleVisibility: .visible) {
            Button(language.text("Discard run"), role: .destructive) { location.cancel(); dismiss() }
            Button(language.text("Keep run"), role: .cancel) {}
        }
        .fullScreenCover(item: $debriefRun) { run in
            RunDebriefView(run: run) {
                debriefRun = nil
                dismiss()
            }
        }
    }

    private var offRouteDistance: Double? {
        guard routePoints.count > 1,
              let coordinate = location.currentLocation?.coordinate,
              let distance = OrbitRunMetricsEngine.routeDeviationM(point: coordinate, route: routePoints),
              distance >= 45
        else { return nil }
        return distance
    }

    private var guidanceMessage: String? {
        if let offRouteDistance {
            return language.format("Off route by about %d m. Return to the violet line when practical.", Int(offRouteDistance.rounded()))
        }
        guard location.state == .running || location.state == .paused else { return nil }
        let normalized = effectiveMission.lowercased()
        if normalized.contains("recovery") {
            return "Keep this genuinely easy. Faster is not better for today’s mission."
        }
        if normalized.contains("tempo") || normalized.contains("threshold") {
            return "Settle into controlled quality. Do not race the opening minutes."
        }
        return "Stay inside the purpose of the run and finish with control."
    }

    private var selectedShoeName: String {
        guard let selectedShoeID,
              let shoe = session.data.orbitShoes.first(where: { $0.id == selectedShoeID })
        else { return language.text("Choose running shoes") }
        return shoe.name
    }

    private func liveMetric(_ value: String, _ title: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(APEXFont.display(24))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(language.text(title)).font(APEXFont.mono(8)).tracking(1).foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func formatPace(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "–:––" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct OrbitControlStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(color.gradient, in: Circle())
            .shadow(color: color.opacity(0.5), radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
    }
}
