import CoreLocation
import Foundation
import UniformTypeIdentifiers

enum OrbitGPXService {
    static func parse(_ data: Data) throws -> [OrbitGeoPoint] {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.points.count >= 2 else {
            throw OrbitGPXError.invalid
        }
        return delegate.points
    }

    static func export(route: OrbitRouteRecord) throws -> URL {
        let points = route.geoPoints
        guard points.count >= 2 else { throw OrbitGPXError.invalid }
        let body = points.map { point in
            let elevation = point.elevationM.map { "<ele>\($0)</ele>" } ?? ""
            return "<trkpt lat=\"\(point.lat)\" lon=\"\(point.lng)\">\(elevation)</trkpt>"
        }.joined()
        let escapedName = route.name
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="APEX Orbit" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>\(escapedName)</name><trkseg>\(body)</trkseg></trk>
        </gpx>
        """
        let safeName = route.name.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safeName.isEmpty ? "APEX-Route" : safeName).gpx")
        try Data(xml.utf8).write(to: url, options: .atomic)
        return url
    }

    static func candidate(points: [OrbitGeoPoint], option: Int = 1) -> OrbitRouteCandidate {
        let distance = Int(zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + CLLocation(latitude: pair.0.lat, longitude: pair.0.lng)
                .distance(from: CLLocation(latitude: pair.1.lat, longitude: pair.1.lng))
        }.rounded())
        let elevations = points.compactMap(\.elevationM)
        var gain = 0.0
        if elevations.count >= 2 {
            for pair in zip(elevations, elevations.dropFirst()) where pair.1 - pair.0 > 2 {
                gain += pair.1 - pair.0
            }
        }
        return OrbitRouteCandidate(
            id: UUID(), points: points, distanceM: distance,
            elevationGainM: elevations.count >= 2 ? Int(gain.rounded()) : nil,
            navigationComplexity: points.count < 30 ? "low" : points.count < 120 ? "moderate" : "high",
            terrain: distance > 0 && gain / (Double(distance) / 1_000) >= 24 ? "hilly" : gain > 10 ? "rolling" : "flat",
            score: 100,
            explanation: "Imported or manually drawn by the user. Orbit preserves the geometry without making a safety claim.",
            optionNumber: option
        )
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var points: [OrbitGeoPoint] = []
    private var pendingLatitude: Double?
    private var pendingLongitude: Double?
    private var pendingElevation: Double?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        guard ["trkpt", "rtept", "wpt"].contains(elementName) else { return }
        pendingLatitude = attributeDict["lat"].flatMap(Double.init)
        pendingLongitude = attributeDict["lon"].flatMap(Double.init)
        pendingElevation = nil
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "ele" { pendingElevation = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard ["trkpt", "rtept", "wpt"].contains(elementName),
              let latitude = pendingLatitude,
              let longitude = pendingLongitude
        else { return }
        points.append(.init(lat: latitude, lng: longitude, elevationM: pendingElevation))
        pendingLatitude = nil
        pendingLongitude = nil
        pendingElevation = nil
    }
}

enum OrbitGPXError: LocalizedError {
    case invalid

    var errorDescription: String? {
        "The GPX file did not contain a usable route."
    }
}

extension UTType {
    static let gpx = UTType(filenameExtension: "gpx") ?? .xml
}
