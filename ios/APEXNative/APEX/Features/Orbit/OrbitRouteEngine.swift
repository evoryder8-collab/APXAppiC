import CoreLocation
import Foundation
import Supabase

struct OrbitGeoPoint: Codable, Hashable, Sendable {
    let lat: Double
    let lng: Double
    let elevationM: Double?

    enum CodingKeys: String, CodingKey {
        case lat, lng
        case elevationM = "elevation_m"
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
}

struct OrbitRouteCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let points: [OrbitGeoPoint]
    let distanceM: Int
    let elevationGainM: Int?
    let navigationComplexity: String
    let terrain: String
    let score: Int
    let explanation: String
    let optionNumber: Int
}

actor OrbitRouteEngine {
    static let shared = OrbitRouteEngine()

    func generate(
        start: CLLocationCoordinate2D,
        distanceKM: Double,
        shape: String,
        terrain: String,
        surface: String,
        mission: String,
        simpleNavigation: Bool
    ) async throws -> [OrbitRouteCandidate] {
        guard let client = SupabaseService.shared.client else { throw APEXServiceError.configurationMissing }
        let starts = waypointSets(start: start, distanceM: distanceKM * 1_000, shape: shape, terrain: terrain)
        return try await withThrowingTaskGroup(of: OrbitRouteCandidate?.self) { group in
            for (index, waypoints) in starts.enumerated() {
                group.addTask {
                    let body = OrbitGeoFunctionRequest(
                        operation: "route",
                        payload: .init(
                            waypoints: waypoints.map { .init(lat: $0.latitude, lng: $0.longitude) },
                            surface: surface
                        )
                    )
                    do {
                        let response: OrbitGeoRouteResponse = try await client.functions.invoke(
                            "orbit-geo",
                            options: .init(body: body)
                        )
                        guard response.points.count >= 2 else { return nil }
                        let distance = Int(Self.polylineDistance(response.points).rounded())
                        let inferred = Self.inferredTerrain(gain: response.elevationGainM, distanceM: distance)
                        let complexity = Self.navigationComplexity(response.points)
                        let score = Self.score(
                            distanceM: distance,
                            requestedM: distanceKM * 1_000,
                            terrain: inferred,
                            requestedTerrain: terrain,
                            complexity: complexity,
                            shape: shape,
                            mission: mission,
                            simpleNavigation: simpleNavigation
                        )
                        return OrbitRouteCandidate(
                            id: UUID(),
                            points: Self.simplify(response.points),
                            distanceM: distance,
                            elevationGainM: response.elevationGainM,
                            navigationComplexity: complexity,
                            terrain: inferred,
                            score: score,
                            explanation: Self.explanation(mission: mission, terrain: inferred, complexity: complexity),
                            optionNumber: index + 1
                        )
                    } catch {
                        return nil
                    }
                }
            }
            var candidates: [OrbitRouteCandidate] = []
            for try await candidate in group {
                if let candidate { candidates.append(candidate) }
            }
            guard candidates.isEmpty == false else { throw OrbitRouteError.unavailable }
            return candidates.sorted { $0.score > $1.score }
        }
    }

    nonisolated static func distance(from point: CLLocationCoordinate2D, to route: [OrbitGeoPoint]) -> Double? {
        guard route.count >= 2 else { return nil }
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        return route.map { location.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng)) }.min()
    }

    private func waypointSets(start: CLLocationCoordinate2D, distanceM: Double, shape: String, terrain: String) -> [[CLLocationCoordinate2D]] {
        let bias = terrain == "hilly" ? 1.08 : terrain == "flat" ? 0.96 : 1
        if shape == "point_to_point" {
            return [25, 145, 265].map { bearing in
                [start, destination(start: start, distanceM: distanceM * bias * 0.72, bearing: Double(bearing))]
            }
        }
        if shape == "out_back" {
            return [20, 140, 260].map { bearing in
                let far = destination(start: start, distanceM: distanceM * 0.5, bearing: Double(bearing))
                return [start, far, start]
            }
        }
        return [15, 135, 255].map { bearing in
            let radius = distanceM / 3.7
            let a = destination(start: start, distanceM: radius, bearing: Double(bearing))
            let b = destination(start: start, distanceM: radius, bearing: Double(bearing + 105))
            return [start, a, b, start]
        }
    }

    private func destination(start: CLLocationCoordinate2D, distanceM: Double, bearing: Double) -> CLLocationCoordinate2D {
        let earth = 6_371_000.0
        let angular = distanceM / earth
        let radians = bearing * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lng1 = start.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(radians))
        let lng2 = lng1 + atan2(sin(radians) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return .init(latitude: lat2 * 180 / .pi, longitude: lng2 * 180 / .pi)
    }

    private nonisolated static func polylineDistance(_ points: [OrbitGeoPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + CLLocation(latitude: pair.0.lat, longitude: pair.0.lng)
                .distance(from: CLLocation(latitude: pair.1.lat, longitude: pair.1.lng))
        }
    }

    private nonisolated static func navigationComplexity(_ points: [OrbitGeoPoint]) -> String {
        guard points.count >= 15 else { return "low" }
        var turns = 0
        for index in 2..<points.count {
            let a = points[index - 2]
            let b = points[index - 1]
            let c = points[index]
            let first = atan2(b.lat - a.lat, b.lng - a.lng)
            let second = atan2(c.lat - b.lat, c.lng - b.lng)
            var delta = abs(first - second)
            if delta > .pi { delta = 2 * .pi - delta }
            if delta > 0.55 { turns += 1 }
        }
        return turns <= 6 ? "low" : turns <= 14 ? "moderate" : "high"
    }

    private nonisolated static func inferredTerrain(gain: Int?, distanceM: Int) -> String {
        guard let gain, distanceM > 0 else { return "rolling" }
        let gainPerKM = Double(gain) / (Double(distanceM) / 1_000)
        return gainPerKM < 10 ? "flat" : gainPerKM < 24 ? "rolling" : "hilly"
    }

    private nonisolated static func score(
        distanceM: Int,
        requestedM: Double,
        terrain: String,
        requestedTerrain: String,
        complexity: String,
        shape: String,
        mission: String,
        simpleNavigation: Bool
    ) -> Int {
        var value = 50.0
        let normalizedMission = mission.lowercased().replacingOccurrences(of: " ", with: "_")
        if ["recovery", "easy"].contains(normalizedMission) {
            if terrain == "flat" { value += 22 }
            if complexity == "low" { value += 18 }
        }
        if ["tempo", "threshold", "marathon_pace"].contains(normalizedMission), complexity == "low" { value += 22 }
        if normalizedMission == "hills" { value += terrain == "hilly" ? 32 : terrain == "rolling" ? 16 : 0 }
        if normalizedMission == "long_run", shape == "loop" { value += 10 }
        if terrain == requestedTerrain { value += 8 }
        if simpleNavigation, complexity == "low" { value += 10 }
        value -= abs(Double(distanceM) - requestedM) / max(requestedM, 1) * 45
        return Int(min(max(value.rounded(), 0), 100))
    }

    private nonisolated static func explanation(mission: String, terrain: String, complexity: String) -> String {
        let normalized = mission.lowercased().replacingOccurrences(of: " ", with: "_")
        if normalized == "recovery" {
            return terrain == "flat" && complexity == "low"
                ? "Best recovery option: mostly flat with lower navigation complexity."
                : "A manageable recovery route. Keep effort controlled on every rise."
        }
        if ["tempo", "threshold"].contains(normalized) {
            return complexity == "low"
                ? "Best quality option: longer uninterrupted sections with fewer major turns."
                : "Use the clearest uninterrupted section for the quality block."
        }
        if normalized == "hills" { return "Repeated elevation changes suit controlled climbing work." }
        if normalized == "marathon_pace" { return "Stable route geometry supports disciplined marathon-pace work." }
        return "A balanced option for today’s mission, distance and navigation preference."
    }

    private nonisolated static func simplify(_ points: [OrbitGeoPoint], stride: Int = 4) -> [OrbitGeoPoint] {
        guard points.count > 400 else { return points }
        var result = points.enumerated().compactMap { index, point in index.isMultiple(of: stride) ? point : nil }
        if result.last != points.last, let last = points.last { result.append(last) }
        return result
    }
}

private struct OrbitGeoFunctionRequest: Encodable, Sendable {
    let operation: String
    let payload: Payload

    struct Payload: Encodable, Sendable {
        let waypoints: [Waypoint]
        let surface: String
    }

    struct Waypoint: Encodable, Sendable {
        let lat: Double
        let lng: Double
    }
}

private struct OrbitGeoRouteResponse: Decodable, Sendable {
    let points: [OrbitGeoPoint]
    let elevationGainM: Int?
}

enum OrbitRouteError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Automatic routing is unavailable. You can still start a free run."
    }
}
