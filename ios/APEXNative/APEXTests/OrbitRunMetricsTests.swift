import CoreLocation
import XCTest
@testable import APEX

final class OrbitRunMetricsTests: XCTestCase {
    func testRunMetricsGenerateHonestSplitsAndWebCompatibleKeys() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = (0...11).map { index in
            OrbitLocationSample(
                latitude: 47.0,
                longitude: 8.0 + Double(index) * 0.00132,
                altitude: 430 + Double(index) * 0.2,
                horizontalAccuracy: 5,
                timestamp: start.addingTimeInterval(Double(index) * 60)
            )
        }

        let metrics = OrbitRunMetricsEngine.calculate(
            samples: samples,
            elapsedSeconds: 660,
            movingSeconds: 660,
            weightKG: 70
        )

        XCTAssertGreaterThan(metrics.distanceM, 1_050)
        XCTAssertLessThan(metrics.distanceM, 1_150)
        XCTAssertEqual(metrics.splits.count, 1)
        XCTAssertEqual(metrics.gpsConfidence, "high")
        XCTAssertNotNil(metrics.json["avg_pace_sec_km"])
        XCTAssertNotNil(metrics.json["moving_s"])
        XCTAssertNil(metrics.json["moving_seconds"])
    }

    func testImpossibleJumpIsRejectedInsteadOfInflatingDistance() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            sample(lat: 47, lng: 8, at: start),
            sample(lat: 47, lng: 8.001, at: start.addingTimeInterval(60)),
            sample(lat: 48, lng: 9, at: start.addingTimeInterval(61))
        ]

        let metrics = OrbitRunMetricsEngine.calculate(
            samples: samples,
            elapsedSeconds: 61,
            movingSeconds: 60,
            weightKG: nil
        )

        XCTAssertEqual(metrics.rejectedSampleCount, 1)
        XCTAssertLessThan(metrics.distanceM, 100)
    }

    func testDeviationUsesNearestRouteSegment() {
        let route = [
            OrbitGeoPoint(lat: 47, lng: 8, elevationM: nil),
            OrbitGeoPoint(lat: 47, lng: 8.01, elevationM: nil)
        ]
        let point = CLLocationCoordinate2D(latitude: 47.0001, longitude: 8.005)
        let deviation = OrbitRunMetricsEngine.routeDeviationM(point: point, route: route)

        XCTAssertNotNil(deviation)
        XCTAssertLessThan(deviation ?? 1_000, 15)
    }

    private func sample(lat: Double, lng: Double, at date: Date) -> OrbitLocationSample {
        OrbitLocationSample(
            latitude: lat,
            longitude: lng,
            altitude: 420,
            horizontalAccuracy: 5,
            timestamp: date
        )
    }
}
