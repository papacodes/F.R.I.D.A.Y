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

    /// Whether this alert warrants miniExpanded (shows bar/ring/text) or just mini (silent pill)
    let isInteractive: Bool

    static func volume(_ level: Float) -> SystemAlert {
        SystemAlert(id: "volume",
                    icon: level <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    value: level, color: .white, duration: 2.0, style: .bar, isCharging: false, isInteractive: true)
    }

    static func brightness(_ level: Float) -> SystemAlert {
        SystemAlert(id: "brightness", icon: "sun.max.fill",
                    value: level, color: .white, duration: 2.0, style: .bar, isCharging: false, isInteractive: true)
    }

    static func battery(_ level: Int, charging: Bool) -> SystemAlert {
        let color: Color = charging ? .green : (level <= 20 ? .orange : .white)
        return SystemAlert(id: "battery",
                           icon: charging ? "bolt.fill" : "battery.100",
                           value: Float(level) / 100.0, color: color,
                           duration: 3.0, style: .battery, isCharging: charging, isInteractive: false)
    }

    static func airpods(name: String, level: Int) -> SystemAlert {
        SystemAlert(id: "airpods", icon: "airpodspro",
                    value: Float(level) / 100.0, color: .white,
                    duration: 4.0, style: .ring, isCharging: false, isInteractive: true)
    }
}

// MARK: - Display state

enum NotchDisplayState: Equatable {
    case dismissed      // Physical notch only — wake engine active
    case mini           // Small pill, no text — hover, simple alerts, launch idle
    case miniExpanded   // Pill with content — Friday active, interactive alerts
    case open           // Full vertical panel — user-initiated
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
                self?.handleActivityChange(isActive: isActive, isPlayingMusic: isPlayingMusic)
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
            if displayState != .open {
                isUserInitiatedExpansion = false
            }
            if displayState == .dismissed {
                dismissTimer?.invalidate()
            } else {
                startDismissTimer()
            }
        }
    }
    @Published var closedNotchSize: CGSize = CGSize(width: 200, height: 32)
    @Published var standardWidth: CGFloat = 440 // Width for miniExpanded
    @Published var isUserInitiatedExpansion = false // New flag for explicit click

    // MARK: Alerts
    @Published var activeAlert: SystemAlert? = nil
    private var alertTimer: Timer?

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

    private func handleActivityChange(isActive: Bool, isPlayingMusic: Bool) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            if isActive {
                // Friday is working — show miniExpanded unless already in open
                if displayState == .dismissed || displayState == .mini {
                    displayState = .miniExpanded
                }
            } else if isPlayingMusic {
                // Music only — mini pill is enough
                if displayState == .dismissed {
                    displayState = .mini
                }
            } else {
                startDismissTimer()
            }
        }
    }

    private func startDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) {
                    guard let self else { return }
                    if self.isActive || self.isUserInitiatedExpansion { return }
                    self.displayState = self.hasMusicTrack ? .mini : .dismissed
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
            self.activeAlert = alert
            // Route based on interactivity — don't interrupt open state
            switch displayState {
            case .dismissed:
                displayState = alert.isInteractive ? .miniExpanded : .mini
            case .mini where alert.isInteractive:
                displayState = .miniExpanded
            default:
                break  // overlay alert content in current state
            }
        }
        alertTimer = Timer.scheduledTimer(withTimeInterval: alert.duration, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.activeAlert = nil
                    // Dismiss timer will handle natural collapse back
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
