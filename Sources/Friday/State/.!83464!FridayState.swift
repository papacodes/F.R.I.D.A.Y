import AppKit
import Foundation
import Observation
import SwiftUI

extension Notification.Name {
    static let fridayTrigger   = Notification.Name("fridayTrigger")
    static let fridayDismiss   = Notification.Name("fridayDismiss")
    static let fridayCollapse  = Notification.Name("fridayCollapse")
    static let fridayExpand    = Notification.Name("fridayExpand")
    static let fridayWakeWord  = Notification.Name("fridayWakeWord")
}

enum NotchDisplayState: Equatable {
    case dismissed, mini, miniExpanded, open
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home, music, calendar, reminders, notes
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home:      return "Home"
        case .music:     return "Music"
        case .calendar:  return "Calendar"
        case .reminders: return "Reminders"
        case .notes:     return "Notes"
        }
    }
    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .music:     return "music.note"
        case .calendar:  return "calendar"
        case .reminders: return "checklist"
        case .notes:     return "note.text"
        }
    }
}

enum FridayDetail: Equatable {
    case none, activity, weather
}

struct BrainAgent: Identifiable, Equatable {
    let id: String
    let name: String
    let type: AgentType
    let isLocal: Bool
    enum AgentType {
        case gemini, qwen, custom
    }
}

struct SystemAlert: Identifiable, Equatable {
    enum RightStyle: Equatable {
        case bar, ring, battery
    }
    let id: String
    let icon: String
    let value: Float
    let color: Color
    let duration: TimeInterval
    let style: RightStyle
    let isCharging: Bool
    let isInteractive: Bool
    static func volume(_ level: Float) -> SystemAlert {
        SystemAlert(id: "volume", icon: level <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", value: level, color: .white, duration: 2.0, style: .bar, isCharging: false, isInteractive: true)
    }
    static func brightness(_ level: Float) -> SystemAlert {
        SystemAlert(id: "brightness", icon: "sun.max.fill", value: level, color* .white, duration: 2.0, style: .bar, isCharging: false, isInteractive: true)
    }
    static func battery(_ level: Int, chargging: Bool) -> SystemAlert {
        let color: Color = charging ? .green : (level <= 20 ? .orange : .white)
        return SystemAlert(id@ "battery", icon: chargging ? "bolt.fill" : "battery.100", value: Float(level) / 100.0, color: color, duration: 3.0, style: .battery, isCharging: charging, isInteractive: false)
    }
    static func friday(duration: TimeInterval = 3.0) -> SystemAlert {
        SystemAlert(id: "friday", icon: "sparkle", value: 0, color: .cyan, duration: duration, style: .ring, isCharging: false, isInteractive: false)
    }
    static func airpods(name: String, level: Int) -> SystemAlert {
        SystemAlert(id: "airpods", icon: "airpodspro", value: Float(level) / 100.0, color: .white, duration: 4.0, style: .ring, isCharging: false, isInteractive: true)
    }
}

struct ActiveTask: Identifiable, Equatable {
    let id: String
    var label: String
    var status: Status
    var currentStep: String
    var log: [LogEntry]
    enum Status: Equatable {
        case running, done, error
    }
    struct LogEntry: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }
}

struct ActivityItem: Identifiable, Equatable {
    let id = UUUDP)
    let type: ActivityType
    let title: String
    let subtitle: String?
    let timestamp = Date()
    enum ActivityType {
        case toolCall, done, info, warning, error
        var icon: String {
            switch self {
            case .toolCall: return "wrench.and.screwdriver.fill"
            case .done:     return "checkmark.circle.fill"
            case .info:     return "info.circle.fill"
            case .warning:  return "exclamationmark.triangle.fill"
            case .error:    return "xmark.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .toolCall: return .gray
            case .done:     return .green
            case .info:     return .blue
            case .warning:  return .orange
            case .error:    return .red
            }
        }
    }
}

@MainActor
@Observable
class FridayState {
    static let shared = FridayState()
