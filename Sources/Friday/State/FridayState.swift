import Foundation
import SwiftUI

extension Notification.Name {
    static let fridayTrigger  = Notification.Name("fridayTrigger")
    static let fridayDismiss  = Notification.Name("fridayDismiss")
    static let fridayExpand   = Notification.Name("fridayExpand")
    static let fridayWakeWord = Notification.Name("fridayWakeWord")
}

// MARK: - Alert System

struct SystemAlert: Identifiable, Equatable {

    enum RightStyle: Equatable {
        case bar       // Horizontal fill bar — volume, brightness
        case ring      // Circular progress — AirPods battery
        case battery   // Battery shape with fill — charging / battery level
    }

    /// Stable type key — same alert type reuses the same id so SwiftUI updates
    /// the existing view in-place (animates the slider) rather than recreating it.
    let id: String
    let icon: String
    let value: Float         // 0.0 – 1.0, drives every right-side visual
    let color: Color
    let duration: TimeInterval
    let style: RightStyle
    let isCharging: Bool

    static func volume(_ level: Float) -> SystemAlert {
        SystemAlert(id: "volume",
                    icon: level <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    value: level, color: .white, duration: 2.0, style: .bar, isCharging: false)
    }

    static func brightness(_ level: Float) -> SystemAlert {
        SystemAlert(id: "brightness", icon: "sun.max.fill",
                    value: level, color: .white, duration: 2.0, style: .bar, isCharging: false)
    }

    static func battery(_ level: Int, charging: Bool) -> SystemAlert {
        let color: Color = charging ? .green : (level <= 20 ? .orange : .white)
        return SystemAlert(id: "battery",
                           icon: charging ? "bolt.fill" : "battery.100",
                           value: Float(level) / 100.0, color: color,
                           duration: 3.0, style: .battery, isCharging: charging)
    }

    static func airpods(name: String, level: Int) -> SystemAlert {
        SystemAlert(id: "airpods", icon: "airpodspro",
                    value: Float(level) / 100.0, color: .white,
                    duration: 4.0, style: .ring, isCharging: false)
    }
}

// MARK: - Display state

enum NotchDisplayState: Equatable {
    case alert       // System Notification (Volume, Brightness, etc.)
    case dismissed   // Physical notch only
    case standard    // Horizontal expansion
    case open        // Full vertical expansion
}

// MARK: - Activity Item

struct ActivityItem: Identifiable, Equatable {
    let id = UUID()
    let type: ActivityType
    let title: String
    let subtitle: String?
    let timestamp = Date()

    enum ActivityType {
        case toolCall, done, info, warning, error
        var icon: String {
            switch self {
            case .toolCall: return "hammer.fill"
            case .done:     return "checkmark.circle.fill"
            case .info:     return "info.circle.fill"
            case .warning:  return "exclamationmark.triangle.fill"
            case .error:    return "xmark.octagon.fill"
            }
        }
        var color: Color {
            switch self {
            case .toolCall: return .blue
            case .done:     return .green
            case .info:     return .cyan
            case .warning:  return .orange
            case .error:    return .red
            }
        }
    }
}

// MARK: - Tab navigation

enum NotchTab: CaseIterable, Identifiable {
    case home, music, calendar, reminders, notes
    var id: Self { self }
    var icon: String {
        switch self {
        case .home:      return "sparkle"
        case .music:     return "music.note"
        case .calendar:  return "calendar"
        case .reminders: return "bell"
        case .notes:     return "note.text"
        }
    }
    var label: String {
        switch self {
        case .home:      return "Home"
        case .music:     return "Music"
        case .calendar:  return "Calendar"
        case .reminders: return "Reminders"
        case .notes:     return "Notes"
        }
    }
}

// MARK: - State

@MainActor
final class FridayState: ObservableObject {
    static let shared = FridayState()
    private init() {}

    // MARK: AI
    @Published var isListening  = false
    @Published var isThinking   = false
    @Published var isSpeaking   = false
    @Published var isError      = false
    @Published var isConnected  = false
    @Published var isDevTaskRunning = false
    @Published var transcript   = ""
    @Published var volume: Float = 0.0
    @Published var modelName    = "Gemini 2.5 Flash"
    @Published var hasGreetedThisSession = false
    @Published var lastActivityTime = Date()
    @Published var activityFeed: [ActivityItem] = []

    // MARK: Window
    @Published var displayState: NotchDisplayState = .dismissed
    @Published var closedNotchSize: CGSize = CGSize(width: 200, height: 32)
    @Published var standardWidth: CGFloat = 440

    // MARK: Alerts
    @Published var activeAlert: SystemAlert? = nil
    private var preAlertState: NotchDisplayState = .dismissed
    private var alertTimer: Timer?
    /// true when postAlert was the reason the notch transitioned dismissed→standard.
    /// Only auto-dismiss on alert expiry when this is true.
    private var alertForcedStandard = false

    // MARK: Navigation
    @Published var activeTab: NotchTab = .home

    // MARK: Music
    @Published var isPlayingMusic    = false
    @Published var isMusicPaused     = false
    @Published var nowPlayingTitle   = ""
    @Published var nowPlayingArtist  = ""
    @Published var albumArt: NSImage? = nil
    @Published var albumAccentColor: Color = .cyan
    @Published var playbackPosition: TimeInterval = 0
    @Published var playbackDuration: TimeInterval = 0

    // MARK: System
    @Published var batteryLevel: Float = 0.0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var isInLowPowerMode: Bool = false
    @Published var lastMusicActivity: Date = Date()

    var hasMusicTrack: Bool { isPlayingMusic || isMusicPaused }
    var isActive: Bool { isListening || isThinking || isSpeaking }
    var isExpanded: Bool { displayState == .open }

    func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<FridayState, T>, to value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    func recordActivity() { lastActivityTime = Date(); lastMusicActivity = Date() }

    func addActivity(type: ActivityItem.ActivityType, title: String, subtitle: String? = nil) {
        let item = ActivityItem(type: type, title: title, subtitle: subtitle)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            activityFeed.insert(item, at: 0)
            if activityFeed.count > 10 { activityFeed.removeLast() }
        }
    }

    func postAlert(_ alert: SystemAlert) {
        alertTimer?.invalidate()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if self.displayState != .alert { self.preAlertState = self.displayState }
            self.activeAlert = alert
            self.displayState = .alert
        }
        alertTimer = Timer.scheduledTimer(withTimeInterval: alert.duration, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.activeAlert = nil
                    self.displayState = self.preAlertState
                }
            }
        }
    }


}

