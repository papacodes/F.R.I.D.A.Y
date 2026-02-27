import Foundation
import SwiftUI

extension Notification.Name {
    static let fridayTrigger = Notification.Name("fridayTrigger")
}

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

@MainActor
final class FridayState: ObservableObject {
    static let shared = FridayState()
    private init() {}

    // MARK: - AI state
    @Published var isListening  = false
    @Published var isThinking   = false
    @Published var isSpeaking   = false
    @Published var isError      = false
    @Published var transcript   = ""
    @Published var volume: Float = 0.0
    @Published var modelName    = "Gemini 2.5 Flash"
    @Published var hasGreetedThisSession = false
    @Published var lastActivityTime = Date()

    // MARK: - Window state
    @Published var isExpanded       = false
    @Published var closedNotchSize: CGSize = CGSize(width: 200, height: 32)
    @Published var showInfoCard     = false

    // MARK: - Navigation
    @Published var activeTab: NotchTab = .home

    // MARK: - Music
    @Published var isPlayingMusic    = false
    @Published var nowPlayingTitle   = ""
    @Published var nowPlayingArtist  = ""

    // MARK: - Helpers
    var isActive: Bool { isListening || isThinking || isSpeaking }

    func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<FridayState, T>, to value: T) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    func recordActivity() {
        lastActivityTime = Date()
    }
}
