import Foundation

@main
struct WaterAccessChecks {
    static func main() {
        precondition(HealthWaterWriteState.notDetermined.action == .requestPermission)
        precondition(HealthWaterWriteState.denied.action == .openHealth)
        precondition(HealthWaterWriteState.authorized.action == .none)
        precondition(HealthWaterWriteState.unavailable.action == .none)
        precondition(HealthWaterWriteState.denied.explanation.contains("optional"))
        precondition(!HealthWaterWriteState.denied.explanation.contains("APEX"))
        precondition(HealthWaterWriteState.denied.actionTitle == "Manage water access")
        precondition(HealthWaterWriteState.notDetermined.actionTitle == "Enable water sharing")
        print("Water access: 8 checks passed")
    }
}
