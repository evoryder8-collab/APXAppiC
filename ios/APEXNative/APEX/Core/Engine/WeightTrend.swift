import Foundation

/*
 * Port of src/lib/weightTrend.ts.
 *
 * A chronological weight series from the synced daily log. Two rows for one
 * date should not normally exist, but keeping the last valid value makes the
 * graph survive an older import or an interrupted sync.
 */
enum WeightTrend {
    enum Range: Int, Sendable, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case quarter = 90
        case year = 365

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .week: "7 days"
            case .month: "30 days"
            case .quarter: "90 days"
            case .year: "1 year"
            }
        }
    }

    struct Point: Hashable, Sendable {
        let date: String
        let weightKG: Double
    }

    /// Outside this band the value is a typo or a unit mix-up, not a weigh-in.
    private static let plausible: ClosedRange<Double> = 25...300

    static func build(logs: [DailyLog], anchorDate: String, range: Range) -> [Point] {
        guard let anchor = APEXDateMath.date(from: anchorDate) else { return [] }
        let start = anchor.addingTimeInterval(-Double(range.rawValue - 1) * 86_400)
        var byDate: [String: Double] = [:]
        var order: [String] = []

        for log in logs {
            guard let date = APEXDateMath.date(from: log.date) else { continue }
            guard date >= start, date <= anchor else { continue }
            guard let weight = log.weightKG, weight.isFinite, plausible.contains(weight) else { continue }
            if byDate[log.date] == nil { order.append(log.date) }
            byDate[log.date] = (weight * 10).rounded() / 10
        }

        return order.sorted().compactMap { date in
            byDate[date].map { Point(date: date, weightKG: $0) }
        }
    }

    static func change(_ points: [Point]) -> Double? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return ((last.weightKG - first.weightKG) * 10).rounded() / 10
    }
}
