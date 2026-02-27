import Foundation
import IOKit.ps
import SwiftUI

/// Manages and monitors battery status changes for Friday.
/// Refined and simplified from boring.notch.
@MainActor
class BatteryManager: ObservableObject {
    static let shared = BatteryManager()
    
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

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
        
        // Charging
        if let isCharging = description["Is Charging"] as? Bool {
            state.isCharging = isCharging
        }
        
        // Plugged In
        if let powerSourceState = description[kIOPSPowerSourceStateKey] as? String {
            state.isPluggedIn = (powerSourceState == kIOPSACPowerValue)
        }
        
        // Low Power Mode
        state.isInLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    
    deinit {
        // CFRunLoopRemoveSource is thread-safe or we don't care at exit
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
