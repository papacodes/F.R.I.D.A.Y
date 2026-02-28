import Foundation
import SwiftUI
import Combine

extension Notification.Name {
    static let fridayTrigger   = Notification.Name("fridayTrigger")
    static let fridayDismiss   = Notification.Name("fridayDismiss")   // hard stop — Gemini goodbye
    static let fridayCollapse  = Notification.Name("fridayCollapse")  // user dismiss — smart (mini if active)
    static let fridayExpand    = Notification.Name("fridayExpand")
    static let fridayWakeWord  = Notification.Name("fridayWakeWord")
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
    case miniExpanded    // Horizontal expansion, based on activity
    case open        // Full vertical expansion, user-initiated
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
    private init() {
        // Observe activity status and transition to miniExpanded if active
        $isListening
            .combineLatest($isThinking, $isSpeaking, $isDevTaskRunning)
            .map { listening, thinking, speaking, devTask in
                listening || thinking || speaking || devTask
            }
            .combineLatest($isPlayingMusic)
            .sink { [weak self] (isActive, isPlayingMusic) in
                self?.handleActivityChange(isActive || isPlayingMusic)
            }
            .store(in: &cancellables)
        setupPeripheralObservation()
    }

    private var cancellables = Set<AnyCancellable>()
    private var dismissTimer: Timer?

    // MARK: AI
    @Published var isListening  = false { didSet { recordActivity() } }
    @Published var isThinking   = false { didSet { recordActivity() } }
    @Published var isSpeaking   = false { didSet { recordActivity() } }
    @Published var isError      = false
    @Published var isConnected  = false
    @Published var isDevTaskRunning = false { didSet { recordActivity() } }
    @Published var transcript   = ""
    @Published var volume: Float = 0.0
    @Published var modelName    = "Gemini 2.5 Flash"
    @Published var hasGreetedThisSession = false
    @Published var lastActivityTime = Date()
    @Published var activityFeed: [ActivityItem] = []
    @Published var longTermMemoryContext: String = ""

    // MARK: Window
    @Published var displayState: NotchDisplayState = .dismissed {
        didSet {
            if displayState == .dismissed || displayState == .miniExpanded {
                isUserInitiatedExpansion = false
            }
            if displayState != .dismissed {
                startDismissTimer()
            } else {
                dismissTimer?.invalidate()
            }
        }
    }
    @Published var closedNotchSize: CGSize = CGSize(width: 200, height: 32)
    @Published var standardWidth: CGFloat = 440 // Width for miniExpanded
    @Published var isUserInitiatedExpansion = false // New flag for explicit click

    // MARK: Alerts
    @Published var activeAlert: SystemAlert? = nil
    private var preAlertState: NotchDisplayState = .dismissed
    private var alertTimer: Timer?
    private var alertForcedStandard = false

    // MARK: Navigation
    @Published var activeTab: NotchTab = .home

    // MARK: Music
    @Published var isPlayingMusic    = false { didSet { recordActivity() } }
    @Published var isMusicPaused     = false { didSet { recordActivity() } }
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
    var isActive: Bool { isListening || isThinking || isSpeaking || isDevTaskRunning }
    var isExpanded: Bool { displayState == .open }

    private func handleActivityChange(_ isActiveOrMusic: Bool) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            if isActiveOrMusic {
                // When active, transition to miniExpanded if not already open by user
                if displayState == .dismissed {
                    displayState = .miniExpanded
                }
            } else {
                // When inactive, start timer to collapse to miniExpanded or dismissed
                startDismissTimer()
            }
        }
    }

    private func startDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) {
                    // Collapse to miniExpanded if not active and not user expanded
                    if !(self?.isActive ?? false) && !(self?.hasMusicTrack ?? false) && !(self?.isUserInitiatedExpansion ?? false) {
                        self?.displayState = .dismissed // Changed to dismissed based on consolidated logic
                    } else if !(self?.isUserInitiatedExpansion ?? false) {
                         self?.displayState = .miniExpanded // Stay in miniExpanded if active or music, but not user expanded
                    }
                }
            }
        }
    }

    func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<FridayState, T>, to value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    func recordActivity() { lastActivityTime = Date(); lastMusicActivity = Date(); startDismissTimer() }

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

    // MARK: Peripherals
    @Published var peripheralManager = PeripheralManager()
    @Published var airPodsConnectionState: AirPodsConnectionState = .disconnected

    private func setupPeripheralObservation() {
        peripheralManager.$airPodsState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.airPodsConnectionState = state
                if case .connected(let name, let status) = state {
                    let avgBattery = ((status.left ?? 0) + (status.right ?? 0)) / 2
                    self?.postAlert(SystemAlert.airpods(name: name, level: avgBattery))
                }
            }
            .store(in: &cancellables)
    }
}
