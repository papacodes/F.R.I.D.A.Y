import Foundation

@MainActor
struct BatterySkill {
    static func getBatteryStatus() -> String {
        let state = FridayState.shared
        let level = Int(state.batteryLevel)

        var parts: [String] = ["Battery is at \(level)%."]

        if state.isCharging {
            parts.append("Currently charging.")
        } else if state.isPluggedIn {
            parts.append("Plugged in and fully charged.")
        } else {
            parts.append("Running on battery power.")
        }

        if state.isInLowPowerMode {
            parts.append("Low Power Mode is active.")
        }

        return parts.joined(separator: " ")
    }
}
