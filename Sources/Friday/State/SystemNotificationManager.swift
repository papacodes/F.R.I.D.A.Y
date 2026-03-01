import Foundation
import AppKit
import CoreAudio
import SwiftUI
import IOKit
import IOKit.ps
import ApplicationServices

// kVirtualMasterVolumeSelector = 'vmvc'
// This is the same property the macOS Sound panel uses for system volume.
// Not exposed in the Swift CoreAudio module, so we define it directly.
private let kVirtualMasterVolumeSelector: AudioObjectPropertySelector = 0x766D_7663

/// Monitors system-level events: volume (key interception + OSD suppression),
/// brightness (key detection + CoreDisplay read), AirPods, and power events.
@MainActor
class SystemNotificationManager: ObservableObject {
    static let shared = SystemNotificationManager()

    // MARK: - State

    private var preMuteVolume: Float? = nil   // For software mute toggle

    private var systemKeyTap: CFMachPort?
    private var systemKeyRunLoopSource: CFRunLoopSource?

    private var peripheralTimer: Timer?
    private var knownDevices: Set<String> = []

    private init() {}

    func start() {
        setupSystemKeyInterceptor()
        startPeripheralMonitoring()
        setupPowerNotifications()
    }

    // MARK: - Volume control

    func adjustVolume(up: Bool) {
        let step: Float = 1.0 / 16.0
        let current = Self.readVolume()
        let target = max(0, min(1, current + (up ? step : -step)))
        Self.setVolume(target)
        NotchAlertEngine.shared.postAlert(.volume(target))
    }

    func toggleMute() {
        let deviceID = Self.defaultOutputDevice()
        guard deviceID != 0 else { return }
        // Try hardware mute first
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddr) {
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted)
            var newVal: UInt32 = muted == 0 ? 1 : 0
            AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, size, &newVal)
            NotchAlertEngine.shared.postAlert(.volume(newVal == 1 ? 0 : Self.readVolume()))
        } else {
            // Software mute: save/restore volume
            let current = Self.readVolume()
            if current > 0.001 {
                preMuteVolume = current
                Self.setVolume(0)
                NotchAlertEngine.shared.postAlert(.volume(0))
            } else if let pre = preMuteVolume {
                Self.setVolume(pre)
                NotchAlertEngine.shared.postAlert(.volume(pre))
                preMuteVolume = nil
            }
        }
    }

    // MARK: - Brightness control

    func adjustBrightness(up: Bool) {
        let step: Float = 1.0 / 16.0
        let current = Self.readBrightness()
        let target = max(0, min(1, current + (up ? step : -step)))
        Self.setBrightness(target)
        NotchAlertEngine.shared.postAlert(.brightness(target))
    }

    // MARK: - CoreAudio helpers (always use fresh device ID)

    /// Returns the current default output device ID.
    private static func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    /// Reads the system volume using the virtual master volume property —
    /// the same property the macOS Sound panel uses. Falls back to averaging
    /// per-channel scalars on devices that don't expose a virtual master.
    static func readVolume() -> Float {
        let deviceID = defaultOutputDevice()
        guard deviceID != 0 else { return 0 }
        var size = UInt32(MemoryLayout<Float32>.size)

        // 1. Virtual master volume ('vmvc') — works on built-in speakers + AirPods
        var vmAddr = AudioObjectPropertyAddress(
            mSelector: kVirtualMasterVolumeSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vm: Float32 = 0
        if AudioObjectGetPropertyData(deviceID, &vmAddr, 0, nil, &size, &vm) == noErr {
            return vm
        }

        // 2. Per-channel average fallback
        var total: Float32 = 0
        var count = 0
        var chAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0
        )
        for ch in UInt32(1)...UInt32(8) {
            chAddr.mElement = ch
            var v: Float32 = 0
            if AudioObjectGetPropertyData(deviceID, &chAddr, 0, nil, &size, &v) == noErr {
                total += v; count += 1
            }
        }
        return count > 0 ? total / Float32(count) : 0
    }

    /// Sets the system volume. Tries virtual master first, then sets all
    /// individual channels so the change is reflected on every output type.
    private static func setVolume(_ value: Float) {
        let deviceID = defaultOutputDevice()
        guard deviceID != 0 else { return }
        var v = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)

        // 1. Virtual master volume — most reliable for system-level control
        var vmAddr = AudioObjectPropertyAddress(
            mSelector: kVirtualMasterVolumeSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectSetPropertyData(deviceID, &vmAddr, 0, nil, size, &v) == noErr { return }

        // 2. Per-channel fallback — set ALL settable channels (built-in speakers need 1+2)
        var chAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0
        )
        for ch in UInt32(1)...UInt32(8) {
            chAddr.mElement = ch
            if AudioObjectHasProperty(deviceID, &chAddr) {
                var settable: DarwinBoolean = false
                AudioObjectIsPropertySettable(deviceID, &chAddr, &settable)
                if settable.boolValue {
                    AudioObjectSetPropertyData(deviceID, &chAddr, 0, nil, size, &v)
                }
            }
        }
    }

    // MARK: - CoreDisplay helpers (brightness)
    //
    // CoreDisplay is a private framework — NOT guaranteed to be loaded in Friday's
    // process. RTLD_NOLOAD returns NULL when it isn't. Load it once with
    // RTLD_GLOBAL | RTLD_LAZY and cache the function pointers permanently.
    // Never dlclose: function pointers must remain valid for the process lifetime.

    private static func readBrightness() -> Float {
        if let get = DisplayServicesBridge.getBrightness {
            var v: Float = 0
            if get(CGMainDisplayID(), &v) == 0 { return max(0, min(1, v)) }
        }
        if let get = CoreDisplayBridge.getBrightness {
            let v = Float(get(CGMainDisplayID()))
            if v > 0.01 { return max(0, min(1, v)) }
        }
        var brightness: Float = 0.5
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iter) == KERN_SUCCESS {
            var service = IOIteratorNext(iter)
            while service != 0 {
                var val: Float = 0
                if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &val) == KERN_SUCCESS { brightness = val }
                IOObjectRelease(service)
                service = IOIteratorNext(iter)
            }
            IOObjectRelease(iter)
        }
        return brightness
    }

    private static func setBrightness(_ value: Float) {
        if let set = DisplayServicesBridge.setBrightness {
            if set(CGMainDisplayID(), value) == 0 { return }
        }
        if let set = CoreDisplayBridge.setBrightness {
            set(CGMainDisplayID(), Double(value))
            return
        }
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iter) == KERN_SUCCESS {
            var service = IOIteratorNext(iter)
            while service != 0 {
                IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, value)
                IOObjectRelease(service)
                service = IOIteratorNext(iter)
            }
            IOObjectRelease(iter)
        }
    }


    // MARK: - CGEventTap (volume OSD suppression + brightness key detection)
    //
    // Requires Accessibility permission (already granted for HotkeyManager).
    // Volume keys → consumed (return nil) → native OSD suppressed, we handle it.
    // Brightness keys → passed through (return event) → macOS adjusts, we read after delay.

    private func setupSystemKeyInterceptor() {
        guard AXIsProcessTrusted() else { return }

        // NSEventType.systemDefined = 14
        let kSystemDefinedType = CGEventType(rawValue: 14)!
        let mask = CGEventMask(1 << kSystemDefinedType.rawValue)

        systemKeyTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, _ -> Unmanaged<CGEvent>? in
                // Validate event type
                guard type.rawValue == 14 else { return Unmanaged.passRetained(cgEvent) }
                guard let nsEvent = NSEvent(cgEvent: cgEvent),
                      nsEvent.type == .systemDefined,
                      nsEvent.subtype.rawValue == 8 else {
                    return Unmanaged.passRetained(cgEvent)
                }
                let data1: Int = nsEvent.data1
                let keyCode  = (data1 & 0xFFFF_0000) >> 16
                let keyState = (data1 & 0x0000_FF00) >> 8
                // 0xA = key down
                guard keyState == 0xA else { return Unmanaged.passRetained(cgEvent) }

                switch keyCode {
                case 0:  // sound up
                    Task { @MainActor in SystemNotificationManager.shared.adjustVolume(up: true) }
                    return nil   // Consume — suppress native OSD
                case 1:  // sound down
                    Task { @MainActor in SystemNotificationManager.shared.adjustVolume(up: false) }
                    return nil
                case 7:  // mute
                    Task { @MainActor in SystemNotificationManager.shared.toggleMute() }
                    return nil
                case 2:  // brightness up — consume + handle ourselves
                    Task { @MainActor in SystemNotificationManager.shared.adjustBrightness(up: true) }
                    return nil
                case 3:  // brightness down — consume + handle ourselves
                    Task { @MainActor in SystemNotificationManager.shared.adjustBrightness(up: false) }
                    return nil
                default:
                    return Unmanaged.passRetained(cgEvent)
                }
            },
            userInfo: nil
        )

        if let tap = systemKeyTap {
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            systemKeyRunLoopSource = src
        }
    }

    // MARK: - Peripherals / AirPods (system_profiler on background thread)

    private func startPeripheralMonitoring() {
        peripheralTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.launchPath = "/usr/sbin/system_profiler"
                p.arguments = ["SPBluetoothDataType"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                try? p.run()
                p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Task { @MainActor in
                    SystemNotificationManager.shared.processAirPodsOutput(out)
                }
            }
        }
    }

    private func processAirPodsOutput(_ out: String) {
        if out.contains("Connected: Yes") && out.contains("Battery Level:") && out.contains("AirPods") {
            if !knownDevices.contains("AirPods") {
                knownDevices.insert("AirPods")
                NotchAlertEngine.shared.postAlert(.airpods(name: "AirPods", level: 100))
            }
        } else {
            knownDevices.remove("AirPods")
        }
    }

    // MARK: - Power (wake from sleep)

    private func setupPowerNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                NotchAlertEngine.shared.postAlert(SystemAlert(
                    id: "wake", icon: "sun.max.fill", value: 1.0, color: Color.cyan,
                    duration: 2.0, style: SystemAlert.RightStyle.bar, isCharging: false, isInteractive: true
                ))
            }
        }
    }
}

// MARK: - CoreDisplay Dynamic Bridge

/// Handles late-binding to CoreDisplay.framework symbols.
private struct CoreDisplayBridge {
    typealias GetBrightnessFn = @convention(c) (UInt32) -> Double
    typealias SetBrightnessFn = @convention(c) (UInt32, Double) -> Void

    static let getBrightness: GetBrightnessFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_GLOBAL | RTLD_LAZY) else { return nil }
        guard let sym = dlsym(handle, "CoreDisplay_Display_GetUserBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetBrightnessFn.self)
    }()

    static let setBrightness: SetBrightnessFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_GLOBAL | RTLD_LAZY) else { return nil }
        guard let sym = dlsym(handle, "CoreDisplay_Display_SetUserBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetBrightnessFn.self)
    }()
}

// MARK: - DisplayServices Dynamic Bridge

private struct DisplayServicesBridge {
    typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightnessFn = @convention(c) (UInt32, Float) -> Int32

    static let getBrightness: GetBrightnessFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_GLOBAL | RTLD_LAZY) else { return nil }
        guard let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetBrightnessFn.self)
    }()

    static let setBrightness: SetBrightnessFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_GLOBAL | RTLD_LAZY) else { return nil }
        guard let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetBrightnessFn.self)
    }()
}
