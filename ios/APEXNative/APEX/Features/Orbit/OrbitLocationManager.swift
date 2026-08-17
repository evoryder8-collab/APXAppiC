@preconcurrency import CoreLocation
import Foundation
import Observation
import UIKit

struct OrbitLocationSample: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        altitude: Double,
        horizontalAccuracy: Double,
        timestamp: Date
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct OrbitPauseInterval: Codable, Hashable, Sendable {
    let startedAt: Date
    var endedAt: Date?

    var json: JSONValue {
        .object([
            "started_at": .number(startedAt.timeIntervalSince1970 * 1_000),
            "ended_at": endedAt.map { .number($0.timeIntervalSince1970 * 1_000) } ?? .null
        ])
    }
}

@MainActor
@Observable
final class OrbitLocationManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = OrbitLocationManager()

    enum RunState: Equatable { case idle, countdown(Int), running, paused, finished }

    var authorization: CLAuthorizationStatus = .notDetermined
    var currentLocation: CLLocation?
    var samples: [OrbitLocationSample] = []
    var state: RunState = .idle
    var startedAt: Date?
    var elapsedSeconds: TimeInterval = 0
    var movingSeconds: TimeInterval = 0
    var distanceM: Double = 0
    var pauseIntervals: [OrbitPauseInterval] = []
    var manualLapsM: [Double] = []
    var weakGPS = false
    var errorMessage: String?
    var draftOwnerID: UUID?
    var draftMission: String?
    var draftRouteID: UUID?
    var draftCampaignSessionID: UUID?
    var draftShoeID: UUID?

    var hasRecoverableRun: Bool {
        draftOwnerID != nil && startedAt != nil && samples.isEmpty == false && state == .paused
    }

    private let manager = CLLocationManager()
    private var timer: Timer?
    private var lastAcceptedLocation: CLLocation?
    private var lastTick = Date()
    private var lastPersistedAt = Date.distantPast
    private let draftURL: URL

    override private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appending(path: "APEX", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        draftURL = directory.appending(path: "active-orbit-run.json")
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        authorization = manager.authorizationStatus
    }

    func restoreDraft(for ownerID: UUID) {
        guard state == .idle || state == .finished else { return }
        guard let data = try? Data(contentsOf: draftURL),
              let draft = try? JSONDecoder.apex.decode(OrbitRunDraft.self, from: data),
              draft.ownerID == ownerID,
              Date().timeIntervalSince(draft.savedAt) < 36 * 60 * 60,
              draft.samples.isEmpty == false
        else { return }

        draftOwnerID = draft.ownerID
        draftMission = draft.mission
        draftRouteID = draft.routeID
        draftCampaignSessionID = draft.campaignSessionID
        draftShoeID = draft.shoeID
        startedAt = draft.startedAt
        samples = draft.samples
        elapsedSeconds = draft.elapsedSeconds
        movingSeconds = draft.movingSeconds
        distanceM = draft.distanceM
        pauseIntervals = draft.pauseIntervals
        manualLapsM = draft.manualLapsM
        if let last = samples.last {
            lastAcceptedLocation = CLLocation(
                coordinate: last.coordinate,
                altitude: last.altitude,
                horizontalAccuracy: last.horizontalAccuracy,
                verticalAccuracy: -1,
                timestamp: last.timestamp
            )
        }
        state = .paused
    }

    func prepare(
        ownerID: UUID,
        mission: String,
        routeID: UUID?,
        campaignSessionID: UUID? = nil,
        shoeID: UUID? = nil
    ) {
        if hasRecoverableRun { return }
        draftOwnerID = ownerID
        draftMission = mission
        draftRouteID = routeID
        draftCampaignSessionID = campaignSessionID
        draftShoeID = shoeID
    }

    func assignShoe(_ id: UUID?) {
        draftShoeID = id
        persistDraft(force: true)
    }

    func requestLocation() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    func beginCountdown() {
        guard state == .idle || state == .finished else { return }
        reset()
        state = .countdown(3)
        Task {
            for remaining in stride(from: 3, through: 1, by: -1) {
                state = .countdown(remaining)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                try? await Task.sleep(for: .seconds(1))
            }
            startRun()
        }
    }

    func startRun() {
        startedAt = .now
        lastTick = .now
        state = .running
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
        startTimer()
        persistDraft(force: true)
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        pauseIntervals.append(.init(startedAt: .now, endedAt: nil))
        persistDraft(force: true)
    }

    func resume() {
        guard state == .paused else { return }
        closeOpenPause()
        lastTick = .now
        state = .running
        manager.startUpdatingLocation()
        startTimer()
        persistDraft(force: true)
    }

    func finish() {
        guard state == .running || state == .paused else { return }
        closeOpenPause()
        state = .finished
        timer?.invalidate()
        timer = nil
        manager.stopUpdatingLocation()
        persistDraft(force: true)
    }

    func cancel() {
        reset()
        draftOwnerID = nil
        draftMission = nil
        draftRouteID = nil
        draftCampaignSessionID = nil
        draftShoeID = nil
        state = .idle
        manager.stopUpdatingLocation()
        clearPersistedDraft()
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        samples = []
        distanceM = 0
        pauseIntervals = []
        manualLapsM = []
        elapsedSeconds = 0
        movingSeconds = 0
        startedAt = nil
        lastAcceptedLocation = nil
        weakGPS = false
    }

    func clearCompletedRun() {
        reset()
        draftOwnerID = nil
        draftMission = nil
        draftRouteID = nil
        draftCampaignSessionID = nil
        draftShoeID = nil
        state = .idle
        clearPersistedDraft()
    }

    func persistForAppTransition() {
        if state == .running || state == .paused { persistDraft(force: true) }
    }

    func markManualLap() {
        guard state == .running || state == .paused, distanceM > 0 else { return }
        manualLapsM.append(distanceM.rounded())
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        persistDraft(force: true)
    }

    var paceSecondsPerKM: Double? {
        guard distanceM >= 25, movingSeconds > 0 else { return nil }
        return movingSeconds / (distanceM / 1_000)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 40 else {
                weakGPS = true
                continue
            }
            weakGPS = location.horizontalAccuracy > 18
            currentLocation = location
            guard state == .running else { continue }
            if let last = lastAcceptedLocation {
                let delta = location.distance(from: last)
                let dt = location.timestamp.timeIntervalSince(last.timestamp)
                let speed = dt > 0 ? delta / dt : 0
                guard delta >= 1.5, speed < 12 else { continue }
                distanceM += delta
            }
            lastAcceptedLocation = location
            samples.append(.init(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                horizontalAccuracy: location.horizontalAccuracy,
                timestamp: location.timestamp
            ))
            persistDraft(force: false)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startedAt)
                if self.state == .running {
                    let now = Date()
                    self.movingSeconds += now.timeIntervalSince(self.lastTick)
                    self.lastTick = now
                }
                self.persistDraft(force: false)
            }
        }
    }

    private func persistDraft(force: Bool) {
        guard let ownerID = draftOwnerID,
              let mission = draftMission,
              let startedAt,
              state == .running || state == .paused || state == .finished
        else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastPersistedAt) >= 5 else { return }
        lastPersistedAt = now
        let draft = OrbitRunDraft(
            ownerID: ownerID,
            mission: mission,
            routeID: draftRouteID,
            campaignSessionID: draftCampaignSessionID,
            shoeID: draftShoeID,
            startedAt: startedAt,
            samples: samples,
            elapsedSeconds: elapsedSeconds,
            movingSeconds: movingSeconds,
            distanceM: distanceM,
            pauseIntervals: pauseIntervals,
            manualLapsM: manualLapsM,
            savedAt: now
        )
        guard let data = try? JSONEncoder.apex.encode(draft) else { return }
        do {
            try data.write(to: draftURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            errorMessage = "The active run could not be protected for recovery."
        }
    }

    private func clearPersistedDraft() {
        try? FileManager.default.removeItem(at: draftURL)
    }

    private func closeOpenPause() {
        guard let index = pauseIntervals.lastIndex(where: { $0.endedAt == nil }) else { return }
        pauseIntervals[index].endedAt = .now
    }
}

private struct OrbitRunDraft: Codable, Sendable {
    let ownerID: UUID
    let mission: String
    let routeID: UUID?
    let campaignSessionID: UUID?
    let shoeID: UUID?
    let startedAt: Date
    let samples: [OrbitLocationSample]
    let elapsedSeconds: Double
    let movingSeconds: Double
    let distanceM: Double
    let pauseIntervals: [OrbitPauseInterval]
    let manualLapsM: [Double]
    let savedAt: Date
}

private extension JSONEncoder {
    static let apex: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let apex: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
