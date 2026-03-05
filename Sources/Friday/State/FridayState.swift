import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Notification Names

extension Notification.Name {
    static let fridayTrigger   = Notification.Name("fridayTrigger")
    static let fridayDismiss   = Notification.Name("fridayDismiss")
    static let fridayCollapse  = Notification.Name("fridayCollapse")
    static let fridayExpand    = Notification.Name("fridayExpand")
    static let fridayWakeWord  = Notification.Name("fridayWakeWord")
}

// MARK: - Display State

enum NotchDisplayState: Equatable {
    case dismissed, mini, miniExpanded, open
}

// MARK: - Tab

enum NotchTab: String, CaseIterable, Identifiable {
    case home, music, calendar, reminders, notes, assistant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home:      return "Home"
        case .music:     return "Music"
        case .calendar:  return "Calendar"
        case .reminders: return "Reminders"
        case .notes:     return "Notes"
        case .assistant: return "Assistant"
        }
    }

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .music:     return "music.note"
        case .calendar:  return "calendar"
        case .reminders: return "checklist"
        case .notes:     return "note.text"
        case .assistant: return "sparkles"
        }
    }
}

// MARK: - Friday Detail Panel

/// Which content panel is overlaid on the home tab's main area.
/// .none shows the default Friday orb. .activity and beyond are
/// triggered by Friday's responses — not manually navigable (except .activity).
enum FridayDetail: Equatable {
    case none, activity, weather
}

// MARK: - Brain Agents

struct BrainAgent: Identifiable, Equatable {
    let id: String
    let name: String
    let type: AgentType
    let isLocal: Bool
    
    enum AgentType {
        case gemini, qwen, llama, custom
    }
}

// MARK: - Alert System

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
        SystemAlert(id: "brightness", icon: "sun.max.fill", value: level, color: .white, duration: 2.0, style: .bar, isCharging: false, isInteractive: true)
    }

    static func battery(_ level: Int, charging: Bool) -> SystemAlert {
        let color: Color = charging ? .green : (level <= 20 ? .orange : .white)
        return SystemAlert(id: "battery", icon: charging ? "bolt.fill" : "battery.100", value: Float(level) / 100.0, color: color, duration: 3.0, style: .battery, isCharging: charging, isInteractive: false)
    }

    static func friday(duration: TimeInterval = 3.0) -> SystemAlert {
        SystemAlert(id: "friday", icon: "sparkle", value: 0, color: .cyan, duration: duration, style: .ring, isCharging: false, isInteractive: false)
    }

    static func airpods(name: String, level: Int) -> SystemAlert {
        SystemAlert(id: "airpods", icon: "airpodspro", value: Float(level) / 100.0, color: .white, duration: 4.0, style: .ring, isCharging: false, isInteractive: true)
    }
}

// MARK: - Active Task

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

// MARK: - Activity Feed

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

// MARK: - Main State

@MainActor
class FridayState: ObservableObject {

    static let shared = FridayState()

    // MARK: Display

    @Published var displayState: NotchDisplayState = .mini
    @Published var activeTab: NotchTab = .home
    @Published var activeAlert: SystemAlert?
    @Published var closedNotchSize: CGSize = .zero
    @Published var isHovering: Bool = false
    @Published var isUserInitiatedExpansion: Bool = false
    @Published var isFridaySessionActive: Bool = false
    @Published var activeDetail: FridayDetail = .none

    var isFridayDetailOpen: Bool { activeDetail != .none }

    var standardWidth: CGFloat { 440 }

    // MARK: Pipeline State

    @Published var isListening: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var isThinking: Bool = false
    @Published var isConnected: Bool = false
    @Published var isError: Bool = false
    @Published var isContextWarning: Bool = false
    @Published var volume: Float = 0.0
    @Published var transcript: String = ""
    @Published var currentToolLabel: String?
    @Published var hasGreetedThisSession: Bool = false
    @Published var longTermMemoryContext: String = ""
    @Published var isLocalMode: Bool = true // Defaulting to Local mode
    
    // Multi-Agent tracking
    @Published var availableAgents: [BrainAgent] = []
    @Published var activeAgentID: String = "local-qwen-3.5"

    var modelName: String {
        if let agent = availableAgents.first(where: { $0.id == activeAgentID }) {
            return agent.name
        }
        return isLocalMode ? "Qwen 3.5 2B (Local)" : "Gemini 2.0 Flash"
    }

    var isActive: Bool {
        isListening || isSpeaking || isThinking || isFridaySessionActive
    }

    // MARK: Tasks

    @Published var activeTasks: [ActiveTask] = []
    @Published var activityHistory: [ActivityItem] = []

    var isDevTaskRunning: Bool {
        activeTasks.contains { $0.status == .running }
    }

    // MARK: Music

    @Published var isPlayingMusic: Bool = false
    @Published var isMusicPaused: Bool = false
    @Published var albumArt: NSImage?
    @Published var albumAccentColor: Color = .cyan
    @Published var nowPlayingTitle: String = ""
    @Published var nowPlayingArtist: String = ""
    @Published var playbackPosition: TimeInterval = 0
    @Published var playbackDuration: TimeInterval = 0

    var hasMusicTrack: Bool { !nowPlayingTitle.isEmpty }

    // MARK: Battery / System

    @Published var batteryLevel: Float = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var isInLowPowerMode: Bool = false

    // MARK: Weather

    @Published var currentWeather: Weather?

    // MARK: - Singleton

    private init() {}

    // MARK: - State Update Helper

    func update<T>(_ keyPath: ReferenceWritableKeyPath<FridayState, T>, to value: T) {
        self[keyPath: keyPath] = value
    }

    // MARK: - Activity

    func recordActivity() {
        // Called on UI transitions and voice activity — keeps last-active timestamp for dismissal logic.
    }

    func addActivity(type: ActivityItem.ActivityType, title: String, subtitle: String? = nil) {
        let item = ActivityItem(type: type, title: title, subtitle: subtitle)
        activityHistory.insert(item, at: 0)
        if activityHistory.count > 50 {
            activityHistory = Array(activityHistory.prefix(50))
        }
    }

    // MARK: - Dev Task State

    func beginDevTask() {
        // Deprecated thin wrapper — isDevTaskRunning now derives from activeTasks.
    }

    func endDevTask() {
        // Deprecated thin wrapper.
    }

    // MARK: - Task Manager

    func startTask(id: String, label: String) {
        let task = ActiveTask(id: id, label: label, status: .running, currentStep: "", log: [])
        if let index = activeTasks.firstIndex(where: { $0.id == id }) {
            activeTasks[index] = task
        } else {
            activeTasks.append(task)
        }
    }

    func updateTask(id: String, step: String) {
        guard let index = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        activeTasks[index].currentStep = step
        let entry = ActiveTask.LogEntry(text: step, isError: false)
        activeTasks[index].log.append(entry)
    }

    func completeTask(id: String) {
        guard let index = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        activeTasks[index].status = .done
        activeTasks[index].currentStep = ""
    }

    func errorTask(id: String, message: String) {
        guard let index = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        activeTasks[index].status = .error
        activeTasks[index].currentStep = message
        let entry = ActiveTask.LogEntry(text: message, isError: true)
        activeTasks[index].log.append(entry)
    }

    func dismissTask(id: String) {
        activeTasks.removeAll { $0.id == id }
    }

    func dismissCompletedTasks() {
        activeTasks.removeAll { $0.status == .done || $0.status == .error }
    }
}
