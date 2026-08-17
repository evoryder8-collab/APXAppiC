import CoreLocation
import Foundation

struct OrbitSegmentEffort: Hashable, Sendable {
    let runID: UUID
    let segmentID: UUID
    let durationSeconds: Double
    let paceSecondsPerKM: Double
    let heartRateAverage: Double?
    let cadenceAverage: Double?
    let elevationDeltaM: Double?
}

struct OrbitSegmentSummary: Hashable, Sendable {
    let attempts: Int
    let best: OrbitSegmentEffort
    let recent: OrbitSegmentEffort
    let typicalDurationSeconds: Double
    let interpretation: String
}

struct OrbitRouteDNA: Hashable, Sendable {
    let completions: Int
    let typicalDistanceM: Double
    let typicalElevationGainM: Double?
    let typicalDurationSeconds: Double
    let typicalPaceSecondsPerKM: Double?
    let typicalHeartRate: Double?
    let paceVariationPercent: Double?
    let recentTrend: String
    let interpretation: String
}

struct OrbitRunAnalysis: Hashable, Sendable {
    let paceVariationPercent: Double?
    let splitClassification: String
    let finalThirdChangePercent: Double?
    let cardiacDriftPercent: Double?
    let trainingLoad: Double?
    let recoveryCost: String?
    let facts: [String]
}

enum OrbitAnalysisEngine {
    static func analyze(run: OrbitRunRecord) -> OrbitRunAnalysis {
        let splitPaces = fullSplitPaces(run)
        let variation = coefficientOfVariation(splitPaces).map { $0 * 100 }
        let classification: String
        if splitPaces.count < 4 {
            classification = "insufficient_data"
        } else {
            let half = splitPaces.count / 2
            let first = mean(Array(splitPaces.prefix(half))) ?? 0
            let second = mean(Array(splitPaces.suffix(half))) ?? 0
            let change = first > 0 ? (second - first) / first : 0
            classification = change <= -0.02 ? "negative" : change >= 0.02 ? "positive" : "even"
        }
        let finalThird: Double?
        if splitPaces.count >= 3 {
            let third = max(1, splitPaces.count / 3)
            let first = mean(Array(splitPaces.prefix(third))) ?? 0
            let final = mean(Array(splitPaces.suffix(third))) ?? 0
            finalThird = first > 0 ? ((final - first) / first * 1_000).rounded() / 10 : nil
        } else {
            finalThird = nil
        }
        let effort = run.checkIn["perceived_effort"]?.numberValue
        let movingMinutes = (run.metrics["moving_s"]?.numberValue ?? 0) / 60
        let load = effort.map { (movingMinutes * $0).rounded() }
        let recovery: String?
        if let effort {
            recovery = effort >= 8 || movingMinutes >= 120 ? "high" : effort >= 5 || movingMinutes >= 60 ? "moderate" : "low"
        } else {
            recovery = nil
        }
        let drift = cardiacDrift(run)
        var facts: [String] = []
        switch classification {
        case "negative": facts.append("The second half was faster than the first half.")
        case "positive": facts.append("The second half was slower than the first half.")
        case "even": facts.append("The two halves were paced evenly.")
        default: break
        }
        if let drift { facts.append(String(format: "Aerobic decoupling was approximately %.1f%%.", abs(drift))) }
        if let finalThird, finalThird <= -2 { facts.append("The final third was stronger than the opening third.") }
        if let finalThird, finalThird >= 4 { facts.append("The final third faded relative to the opening third.") }
        return .init(
            paceVariationPercent: variation,
            splitClassification: classification,
            finalThirdChangePercent: finalThird,
            cardiacDriftPercent: drift,
            trainingLoad: load,
            recoveryCost: recovery,
            facts: facts
        )
    }

    static func routeDNA(route: OrbitRouteRecord, runs: [OrbitRunRecord]) -> OrbitRouteDNA? {
        let matches = runs.filter { $0.routeID == route.id && $0.status == "completed" }
        guard matches.count >= 2 else { return nil }
        let sorted = matches.sorted { $0.startedAt < $1.startedAt }
        let paces = matches.compactMap { $0.metrics["avg_pace_sec_km"]?.numberValue }
        let heartRates = matches.compactMap { $0.metrics["heart_rate_avg"]?.numberValue }
        let elevations = matches.compactMap { $0.metrics["elevation_gain_m"]?.numberValue }
        let controlled = matches
            .filter { ($0.checkIn["perceived_effort"]?.numberValue ?? 10) <= 6 }
            .compactMap { run -> (OrbitRunRecord, Double)? in
                guard let pace = run.metrics["avg_pace_sec_km"]?.numberValue else { return nil }
                return (run, pace)
            }
            .sorted { $0.1 < $1.1 }
        let recent = Array(sorted.suffix(min(3, sorted.count)))
        let earlier = Array(sorted.prefix(min(3, sorted.count)))
        let recentPace = mean(recent.compactMap { $0.metrics["avg_pace_sec_km"]?.numberValue })
        let earlierPace = mean(earlier.compactMap { $0.metrics["avg_pace_sec_km"]?.numberValue })
        let recentHR = mean(recent.compactMap { $0.metrics["heart_rate_avg"]?.numberValue })
        let earlierHR = mean(earlier.compactMap { $0.metrics["heart_rate_avg"]?.numberValue })

        let trend: String
        if let recentPace, let earlierPace, matches.count >= 3 {
            let delta = (recentPace - earlierPace) / earlierPace
            trend = delta < -0.02 ? "Recent controlled attempts are faster." : delta > 0.02 ? "Recent attempts were slower or more demanding." : "Recent performance is stable."
        } else {
            trend = "Not enough comparable pace data yet."
        }

        var interpretation = controlled.first == nil
            ? "Repeated runs are building a useful private baseline."
            : "The best controlled attempt is separated from a fastest-at-any-cost result."
        if let recentPace, let earlierPace, let recentHR, let earlierHR {
            if recentPace < earlierPace * 0.98 && recentHR <= earlierHR * 1.02 {
                interpretation = "Faster at a similar heart rate, suggesting improved efficiency."
            } else if abs(recentPace - earlierPace) / earlierPace < 0.02 && recentHR < earlierHR * 0.97 {
                interpretation = "Similar pace at a lower heart rate, suggesting improved efficiency."
            } else if recentPace < earlierPace * 0.98 && recentHR > earlierHR * 1.04 {
                interpretation = "Faster, but with clearly greater cardiovascular effort."
            }
        }

        return .init(
            completions: matches.count,
            typicalDistanceM: median(matches.compactMap { $0.metrics["distance_m"]?.numberValue }),
            typicalElevationGainM: elevations.isEmpty ? nil : median(elevations),
            typicalDurationSeconds: median(matches.compactMap { $0.metrics["moving_s"]?.numberValue }),
            typicalPaceSecondsPerKM: paces.isEmpty ? nil : median(paces),
            typicalHeartRate: heartRates.isEmpty ? nil : median(heartRates),
            paceVariationPercent: coefficientOfVariation(paces).map { $0 * 100 },
            recentTrend: trend,
            interpretation: interpretation
        )
    }

    static func segmentSummary(
        segment: OrbitSegment,
        runs: [OrbitRunRecord]
    ) -> OrbitSegmentSummary? {
        let efforts = runs
            .filter { $0.routeID == segment.routeID && $0.status == "completed" }
            .compactMap { segmentEffort(run: $0, segment: segment) }
        guard let best = efforts.min(by: { $0.durationSeconds < $1.durationSeconds }),
              let recent = efforts.last
        else { return nil }
        let typical = median(efforts.map(\.durationSeconds))
        let interpretation: String
        if let bestHR = best.heartRateAverage,
           let recentHR = recent.heartRateAverage,
           recent.durationSeconds <= best.durationSeconds * 1.02,
           recentHR < bestHR * 0.97 {
            interpretation = "Recent performance is near your best time at a lower heart rate."
        } else if recent.durationSeconds < typical * 0.98 {
            interpretation = "The recent attempt was faster than your typical private baseline."
        } else if recent.durationSeconds > typical * 1.04 {
            interpretation = "The recent attempt was slower; effort and conditions provide the missing context."
        } else {
            interpretation = "Recent segment performance is stable."
        }
        return .init(
            attempts: efforts.count,
            best: best,
            recent: recent,
            typicalDurationSeconds: typical,
            interpretation: interpretation
        )
    }

    static func segmentEffort(run: OrbitRunRecord, segment: OrbitSegment) -> OrbitSegmentEffort? {
        let samples = trackPoints(run)
        guard samples.count >= 2 else { return nil }
        var cumulative = [0.0]
        for index in 1..<samples.count {
            cumulative.append(cumulative[index - 1] + samples[index - 1].location.distance(from: samples[index].location))
        }
        guard let startIndex = cumulative.indices.min(by: { abs(cumulative[$0] - Double(segment.startDistanceM)) < abs(cumulative[$1] - Double(segment.startDistanceM)) }),
              let endIndex = cumulative.indices.min(by: { abs(cumulative[$0] - Double(segment.endDistanceM)) < abs(cumulative[$1] - Double(segment.endDistanceM)) }),
              endIndex > startIndex
        else { return nil }
        let slice = Array(samples[startIndex...endIndex])
        let distance = zip(slice, slice.dropFirst()).reduce(0) { $0 + $1.0.location.distance(from: $1.1.location) }
        let duration = ((slice.last?.recordedAtMS ?? 0) - (slice.first?.recordedAtMS ?? 0)) / 1_000
        guard distance >= 50, duration > 0 else { return nil }
        let heartRates = slice.compactMap(\.heartRate)
        let cadences = slice.compactMap(\.cadence)
        let elevation: Double?
        if let first = slice.first?.elevation, let last = slice.last?.elevation { elevation = (last - first).rounded() }
        else { elevation = nil }
        return .init(
            runID: run.id, segmentID: segment.id,
            durationSeconds: duration.rounded(),
            paceSecondsPerKM: (duration / (distance / 1_000)).rounded(),
            heartRateAverage: mean(heartRates)?.rounded(),
            cadenceAverage: mean(cadences)?.rounded(),
            elevationDeltaM: elevation
        )
    }

    private static func fullSplitPaces(_ run: OrbitRunRecord) -> [Double] {
        guard case .array(let values)? = run.metrics["splits"] else { return [] }
        return values.compactMap { value in
            guard let object = value.objectValue,
                  (object["distance_m"]?.numberValue ?? 0) >= 900
            else { return nil }
            return object["pace_sec_km"]?.numberValue
        }
    }

    private static func cardiacDrift(_ run: OrbitRunRecord) -> Double? {
        let samples = trackPoints(run).filter { $0.heartRate != nil }
        guard samples.count >= 20,
              let first = samples.first,
              let last = samples.last,
              last.recordedAtMS - first.recordedAtMS >= 30 * 60 * 1_000
        else { return nil }
        let half = samples.count / 2
        let efficiencies = [Array(samples.prefix(half)), Array(samples.suffix(half))].map { values -> Double in
            let distance = zip(values, values.dropFirst()).reduce(0) { $0 + $1.0.location.distance(from: $1.1.location) }
            let duration = ((values.last?.recordedAtMS ?? 0) - (values.first?.recordedAtMS ?? 0)) / 1_000
            let speed = duration > 0 ? distance / duration : 0
            let heartRate = mean(values.compactMap(\.heartRate)) ?? 0
            return heartRate > 0 ? speed / heartRate : 0
        }
        guard efficiencies[0] > 0, efficiencies[1] > 0 else { return nil }
        return ((efficiencies[0] - efficiencies[1]) / efficiencies[0] * 1_000).rounded() / 10
    }

    private static func trackPoints(_ run: OrbitRunRecord) -> [TrackPoint] {
        run.samples.compactMap { value in
            guard let object = value.objectValue,
                  let lat = object["lat"]?.numberValue,
                  let lng = object["lng"]?.numberValue,
                  let recorded = object["recorded_at"]?.numberValue
            else { return nil }
            return .init(
                location: CLLocation(latitude: lat, longitude: lng),
                recordedAtMS: recorded,
                elevation: object["elevation_m"]?.numberValue,
                heartRate: object["heart_rate_bpm"]?.numberValue,
                cadence: object["cadence_spm"]?.numberValue
            )
        }
    }

    private static func coefficientOfVariation(_ values: [Double]) -> Double? {
        guard values.count >= 2, let average = mean(values), average > 0 else { return nil }
        let variance = values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count)
        return sqrt(variance) / average
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard sorted.isEmpty == false else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

private struct TrackPoint: Hashable, Sendable {
    let location: CLLocation
    let recordedAtMS: Double
    let elevation: Double?
    let heartRate: Double?
    let cadence: Double?
}
