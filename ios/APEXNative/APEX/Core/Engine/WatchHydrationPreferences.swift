import Foundation

struct WatchHydrationPreferences: Codable, Equatable, Sendable {
    enum Unit: String, Codable, CaseIterable, Identifiable, Sendable {
        case liters
        case gallons

        var id: Self { self }
        var label: String { self == .liters ? "Litres" : "US gallons" }
    }

    enum MotionIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
        case off
        case subtle
        case full

        var id: Self { self }
        var label: String { rawValue.capitalized }

        var scale: Double {
            switch self {
            case .off: 0
            case .subtle: 0.6
            case .full: 1
            }
        }
    }

    enum ValidationError: LocalizedError {
        case targetOutOfRange

        var errorDescription: String? {
            "Choose a daily target from 1.00 to 6.00 litres."
        }
    }

    static let `default` = WatchHydrationPreferences(
        targetLiters: 2.75,
        unit: .liters,
        showsPresetNames: true,
        confirmationHaptics: true,
        motionIntensity: .subtle,
        remindersEnabled: false,
        reminderIntervalMinutes: 90,
        quietHoursStartMinutes: (21 * 60) + 30,
        quietHoursEndMinutes: 8 * 60
    )

    var targetLiters: Double
    var unit: Unit
    var showsPresetNames: Bool
    var confirmationHaptics: Bool
    var motionIntensity: MotionIntensity
    var remindersEnabled: Bool
    var reminderIntervalMinutes: Int
    var quietHoursStartMinutes: Int
    var quietHoursEndMinutes: Int

    static func validatedTargetLiters(_ value: Double) throws -> Double {
        guard value.isFinite, (1.0...6.0).contains(value) else {
            throw ValidationError.targetOutOfRange
        }
        return value
    }

    func formattedAmount(liters: Double) -> String {
        switch unit {
        case .liters:
            return "\(liters.formatted(.number.precision(.fractionLength(2)))) L"
        case .gallons:
            let gallons = liters * 0.264_172_052
            return "\(gallons.formatted(.number.precision(.fractionLength(2)))) gal"
        }
    }

    var formattedTarget: String {
        formattedAmount(liters: targetLiters)
    }
}
