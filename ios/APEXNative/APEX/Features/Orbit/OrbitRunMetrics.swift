import CoreLocation
import Foundation

struct OrbitSplit: Hashable, Sendable {
    let index: Int
    let distanceM: Double
    let durationSeconds: Double
    let paceSecondsPerKM: Double
    let elevationDeltaM: Double?

    var json: JSONValue {
        .object([
            "index": .number(Double(index)),
            "distance_m": .number(distanceM),
            "duration_s": .number(durationSeconds),
            "pace_sec_km": .number(paceSecondsPerKM),
            "elevation_delta_m": elevationDeltaM.map { .number($0) } ?? .null,
            "heart_rate_avg": .null
        ])
    }
}

struct OrbitRunMetrics: Hashable, Sendable {
    let acceptedSamples: [OrbitLocationSample]
    let rejectedSampleCount: Int
    let distanceM: Double
    let elapsedSeconds: Double
    let movingSeconds: Double
    let averagePaceSecondsPerKM: Double?
    let bestPaceSecondsPerKM: Double?
    let elevationGainM: Double?
    let caloriesKcal: Double?
    let splits: [OrbitSplit]
    let gpsConfidence: String

    var json: [String: JSONValue] {
        [
            "distance_m": .number(distanceM),
            "elapsed_s": .number(elapsedSeconds),
            "moving_s": .number(movingSeconds),
            "avg_pace_sec_km": averagePaceSecondsPerKM.map { .number($0) } ?? .null,
            "best_pace_sec_km": bestPaceSecondsPerKM.map { .number($0) } ?? .null,
            "elevation_gain_m": elevationGainM.map { .number($0) } ?? .null,
            "heart_rate_avg": .null,
            "cadence_avg": .null,
            "calories_kcal": caloriesKcal.map { .number($0) } ?? .null,
            "splits": .array(splits.map(\.json)),
            "rejected_samples": .number(Double(rejectedSampleCount)),
            "gps_confidence": .string(gpsConfidence),
            "source": .string("ios_native")
        ]
    }
}

enum OrbitRunMetricsEngine {
    private static let maximumAccuracyM = 40.0
    private static let weakAccuracyM = 20.0
    private static let impossibleSpeedMPS = 12.0
    private static let jumpDistanceM = 125.0
    private static let jumpWindowSeconds = 10.0
    private static let maximumMovingGapSeconds = 20.0
    private static let movingSpeedMPS = 0.55

    static func calculate(
        samples rawSamples: [OrbitLocationSample],
        elapsedSeconds fallbackElapsed: Double,
        movingSeconds fallbackMoving: Double,
        weightKG: Double?
    ) -> OrbitRunMetrics {
        let filtered = filter(rawSamples)
        let samples = filtered.accepted
        let distance = polylineDistance(samples)
        let recordedElapsed: Double
        if let first = samples.first, let last = samples.last {
            recordedElapsed = max(0, last.timestamp.timeIntervalSince(first.timestamp))
        } else {
            recordedElapsed = max(0, fallbackElapsed)
        }
        let measuredMoving = movingTime(samples)
        let moving = measuredMoving > 0 ? measuredMoving : max(0, fallbackMoving)
        let denominator = moving > 0 ? moving : recordedElapsed
        let averagePace = distance >= 100 && denominator > 0 ? denominator / (distance / 1_000) : nil
        let splits = kilometreSplits(samples)
        let fullSplitPaces = splits.filter { $0.distanceM >= 900 }.map(\.paceSecondsPerKM)
        let bestPace = fullSplitPaces.min() ?? averagePace
        let averageAccuracy = mean(samples.map(\.horizontalAccuracy))
        let confidence: String
        if samples.count < 3 || averageAccuracy == nil || (averageAccuracy ?? 0) > weakAccuracyM {
            confidence = "low"
        } else if Double(filtered.rejected.count) > Double(samples.count) * 0.15 || (averageAccuracy ?? 0) > 16 {
            confidence = "moderate"
        } else {
            confidence = "high"
        }

        return OrbitRunMetrics(
            acceptedSamples: samples,
            rejectedSampleCount: filtered.rejected.count,
            distanceM: distance.rounded(),
            elapsedSeconds: max(recordedElapsed, fallbackElapsed).rounded(),
            movingSeconds: moving.rounded(),
            averagePaceSecondsPerKM: averagePace?.rounded(),
            bestPaceSecondsPerKM: bestPace?.rounded(),
            elevationGainM: elevationGain(samples)?.rounded(),
            caloriesKcal: weightKG.map { ($0 * distance / 1_000).rounded() },
            splits: splits,
            gpsConfidence: confidence
        )
    }

    static func routeDeviationM(
        point: CLLocationCoordinate2D,
        route: [OrbitGeoPoint]
    ) -> Double? {
        guard route.count >= 2 else { return nil }
        var minimum = Double.greatestFiniteMagnitude
        for index in 1..<route.count {
            minimum = min(
                minimum,
                pointToSegmentDistance(point, start: route[index - 1].coordinate, end: route[index].coordinate)
            )
        }
        return minimum.isFinite ? minimum : nil
    }

    private static func filter(_ rawSamples: [OrbitLocationSample]) -> (accepted: [OrbitLocationSample], rejected: [OrbitLocationSample]) {
        var accepted: [OrbitLocationSample] = []
        var rejected: [OrbitLocationSample] = []
        for sample in rawSamples.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard sample.latitude.isFinite,
                  sample.longitude.isFinite,
                  sample.horizontalAccuracy >= 0,
                  sample.horizontalAccuracy <= maximumAccuracyM
            else {
                rejected.append(sample)
                continue
            }
            guard let previous = accepted.last else {
                accepted.append(sample)
                continue
            }
            let elapsed = sample.timestamp.timeIntervalSince(previous.timestamp)
            guard elapsed > 0 else {
                rejected.append(sample)
                continue
            }
            let distance = geographicDistance(previous.coordinate, sample.coordinate)
            let speed = distance / elapsed
            let impossibleJump = distance > jumpDistanceM && elapsed < jumpWindowSeconds
            if speed > impossibleSpeedMPS || impossibleJump {
                rejected.append(sample)
            } else {
                accepted.append(sample)
            }
        }
        return (accepted, rejected)
    }

    private static func polylineDistance(_ samples: [OrbitLocationSample]) -> Double {
        zip(samples, samples.dropFirst()).reduce(0) { result, pair in
            result + geographicDistance(pair.0.coordinate, pair.1.coordinate)
        }
    }

    private static func movingTime(_ samples: [OrbitLocationSample]) -> Double {
        zip(samples, samples.dropFirst()).reduce(0) { result, pair in
            let elapsed = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
            guard elapsed > 0, elapsed <= maximumMovingGapSeconds else { return result }
            let speed = geographicDistance(pair.0.coordinate, pair.1.coordinate) / elapsed
            return speed >= movingSpeedMPS && speed <= impossibleSpeedMPS ? result + elapsed : result
        }
    }

    private static func kilometreSplits(_ samples: [OrbitLocationSample]) -> [OrbitSplit] {
        guard samples.count >= 2, let first = samples.first else { return [] }
        var result: [OrbitSplit] = []
        var cumulativeM = 0.0
        var splitStartTime = first.timestamp
        var splitStartElevation: Double? = first.altitude.isFinite ? first.altitude : nil
        var nextBoundaryM = 1_000.0

        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let segmentM = geographicDistance(previous.coordinate, current.coordinate)
            guard segmentM > 0 else { continue }

            while cumulativeM + segmentM >= nextBoundaryM {
                let ratio = (nextBoundaryM - cumulativeM) / segmentM
                let boundaryTime = previous.timestamp.addingTimeInterval(
                    current.timestamp.timeIntervalSince(previous.timestamp) * ratio
                )
                let boundaryElevation: Double?
                if previous.altitude.isFinite, current.altitude.isFinite {
                    boundaryElevation = previous.altitude + (current.altitude - previous.altitude) * ratio
                } else {
                    boundaryElevation = nil
                }
                let duration = max(1, boundaryTime.timeIntervalSince(splitStartTime))
                result.append(
                    OrbitSplit(
                        index: result.count + 1,
                        distanceM: 1_000,
                        durationSeconds: duration.rounded(),
                        paceSecondsPerKM: duration.rounded(),
                        elevationDeltaM: elevationDelta(from: splitStartElevation, to: boundaryElevation)
                    )
                )
                splitStartTime = boundaryTime
                splitStartElevation = boundaryElevation
                nextBoundaryM += 1_000
            }
            cumulativeM += segmentM
        }

        let remainderM = cumulativeM - Double(result.count) * 1_000
        if remainderM >= 200, let last = samples.last {
            let duration = max(1, last.timestamp.timeIntervalSince(splitStartTime))
            result.append(
                OrbitSplit(
                    index: result.count + 1,
                    distanceM: remainderM.rounded(),
                    durationSeconds: duration.rounded(),
                    paceSecondsPerKM: (duration / (remainderM / 1_000)).rounded(),
                    elevationDeltaM: elevationDelta(
                        from: splitStartElevation,
                        to: last.altitude.isFinite ? last.altitude : nil
                    )
                )
            )
        }
        return result
    }

    private static func elevationGain(_ samples: [OrbitLocationSample]) -> Double? {
        let elevations: [Double?] = samples.enumerated().map { index, sample in
            guard sample.altitude.isFinite else { return nil }
            let lower = max(0, index - 2)
            let upper = min(samples.count, index + 3)
            let values = samples[lower..<upper].map(\.altitude).filter(\.isFinite)
            return mean(values)
        }
        guard elevations.compactMap({ $0 }).count >= 3 else { return nil }
        var anchor: Double?
        var gain = 0.0
        for elevation in elevations.compactMap({ $0 }) {
            guard let previous = anchor else {
                anchor = elevation
                continue
            }
            let delta = elevation - previous
            guard abs(delta) >= 2.5 else { continue }
            if delta > 0 { gain += delta }
            anchor = elevation
        }
        return gain
    }

    private static func elevationDelta(from: Double?, to: Double?) -> Double? {
        guard let from, let to else { return nil }
        return (to - from).rounded()
    }

    private static func geographicDistance(_ first: CLLocationCoordinate2D, _ second: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
    }

    private static func pointToSegmentDistance(
        _ point: CLLocationCoordinate2D,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> Double {
        let origin = start
        let latitudeScale = Double.pi * 6_371_000.0 / 180.0
        let longitudeScale = latitudeScale * cos(origin.latitude * .pi / 180)
        let px = (point.longitude - origin.longitude) * longitudeScale
        let py = (point.latitude - origin.latitude) * latitudeScale
        let bx = (end.longitude - origin.longitude) * longitudeScale
        let by = (end.latitude - origin.latitude) * latitudeScale
        let lengthSquared = bx * bx + by * by
        guard lengthSquared > 0 else { return hypot(px, py) }
        let ratio = min(1, max(0, (px * bx + py * by) / lengthSquared))
        return hypot(px - bx * ratio, py - by * ratio)
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

extension OrbitRouteRecord {
    var geoPoints: [OrbitGeoPoint] {
        points.compactMap { value in
            guard case .object(let object) = value,
                  case .number(let lat) = object["lat"],
                  case .number(let lng) = object["lng"]
            else { return nil }
            let elevation: Double?
            if case .number(let value) = object["elevation_m"] { elevation = value }
            else { elevation = nil }
            return OrbitGeoPoint(lat: lat, lng: lng, elevationM: elevation)
        }
    }
}
