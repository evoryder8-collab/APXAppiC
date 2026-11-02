import Foundation

enum HealthWaterAccessAction: Equatable, Sendable {
    case none, requestPermission, openHealth
}

enum HealthWaterWriteState: Equatable, Sendable {
    case unavailable, notDetermined, denied, authorized

    var action: HealthWaterAccessAction {
        switch self {
        case .notDetermined: .requestPermission
        case .denied: .openHealth
        case .authorized, .unavailable: .none
        }
    }

    var actionTitle: String {
        self == .denied ? "Manage water access" : "Enable water sharing"
    }

    var explanation: String {
        switch self {
        case .authorized:
            "Water sharing is on. Your logged water can be saved to Apple Health."
        case .denied:
            "Apple Health water sharing is optional. You can keep logging water in FITR MAX."
        case .notDetermined:
            "Allow FITR MAX to save your logged water to Apple Health."
        case .unavailable:
            "Apple Health water tracking is unavailable on this device."
        }
    }
}
