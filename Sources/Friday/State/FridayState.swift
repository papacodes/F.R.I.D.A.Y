import Foundation
import SwiftUI

extension Notification.Name {
    static let fridayTrigger = Notification.Name("fridayTrigger")
}

// MARK: - Display state

enum NotchDisplayState: Equatable {
    case dismissed   // Physical notch only — nothing visible
    case standard    // Horizontal expansion — alive indicator / music bar
    case open        // Full vertical expansion — interactive UI
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
    @Published var transcript   = ""
    @Published var volume: Float = 0.0
    @Published var modelName    = "Gemini 2.5 Flash"
    @Published var hasGreetedThisSession = false
    @Published var lastActivityTime = Date()
    @Published var activityFeed: [ActivityItem] = []

    // MARK: Window
    @Published var displayState: NotchDisplayState = .dismissed
    @Published var closedNotchSize: CGSize = CGSize(width: 200, height: 32)

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

    var hasMusicTrack: Bool { isPlayingMusic || isMusicPaused }

    // MARK: Helpers
    var isActive: Bool { isListening || isThinking || isSpeaking }

    // Legacy — kept so GeminiVoicePipeline doesn't need touching
    var isExpanded: Bool { displayState == .open }
    var showInfoCard: Bool = false

    func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<FridayState, T>, to value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    func recordActivity() { lastActivityTime = Date() }
    
    func addActivity(type: ActivityItem.ActivityType, title: String, subtitle: String? = nil) {
        let item = ActivityItem(type: type, title: title, subtitle: subtitle)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            activityFeed.insert(item, at: 0)
            if activityFeed.count > 10 { activityFeed.removeLast() }
        }
    }
}
