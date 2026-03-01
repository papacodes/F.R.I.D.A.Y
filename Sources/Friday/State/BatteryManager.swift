import Foundation
import IOKit.ps
import SwiftUI

/// Manages and monitors battery status changes for Friday.
/// Refined and simplified from boring.notch.
@MainActor
class BatteryManager: ObservableObject {
    static let shared = BatteryManager()

    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    // Track previous state to detect actual changes and post alerts
    private var prevIsCharging: Bool? = nil
    private var prevIsPluggedIn: Bool? = nil

    private init() {
        startMonitoring()
        updateBatteryInfo()
    }
    
    private func startMonitoring() {
        guard let powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let manager = Unmanaged<BatteryManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                manager.updateBatteryInfo()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() else {
            return
        }
        runLoopSource = powerSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), powerSource, .defaultMode)
        
        // Also listen for low power mode changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lowPowerModeChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    @objc private func lowPowerModeChanged() {
        updateBatteryInfo()
    }

    func updateBatteryInfo() {
        let state = FridayState.shared
        
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef], !sources.isEmpty else { return }
        
        let source = sources.first!
        guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { return }
        
        // Level
        if let current = description[kIOPSCurrentCapacityKey] as? Float {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                state.batteryLevel = current
            }
        }
        
        // Charging — alert on change
        var chargingAlertFired = false
        if let isCharging = description["Is Charging"] as? Bool {
            if let prev = prevIsCharging, prev != isCharging {
                NotchAlertEngine.shared.postAlert(.battery(Int(state.batteryLevel), charging: isCharging))
                chargingAlertFired = true
            }
            prevIsCharging = isCharging
            state.isCharging = isCharging
        }

        // Plugged In — alert on change (only if charging state didn't already fire)
        if let powerSourceState = description[kIOPSPowerSourceStateKey] as? String {
            let isPluggedIn = (powerSourceState == kIOPSACPowerValue)
            if let prev = prevIsPluggedIn, prev != isPluggedIn, !chargingAlertFired {
                NotchAlertEngine.shared.postAlert(.battery(Int(state.batteryLevel), charging: state.isCharging))
            }
            prevIsPluggedIn = isPluggedIn
            state.isPluggedIn = isPluggedIn
        }

        // Low Power Mode
        let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled
        if state.isInLowPowerMode != lpm {
            state.isInLowPowerMode = lpm
            if lpm { NotchAlertEngine.shared.postAlert(.battery(Int(state.batteryLevel), charging: state.isCharging)) }
        }
    }
    
    deinit {
        // CFRunLoopRemoveSource is thread-safe or we don't care at exit
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
