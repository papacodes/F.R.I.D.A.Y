import Foundation
import SwiftUI
import Combine

extension Notification.Name {
    static let fridayTrigger   = Notification.Name("fridayTrigger")
    static let fridayDismiss   = Notification.Name("fridayDismiss")
    static let fridayCollapse  = Notification.Name("fridayCollapse")
    static let fridayExpand    = Notification.Name("fridayExpand")
    static let fridayWakeWord  = Notification.Name("fridayWakeWord")
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

enum NotchDisplayState: Equatable {
    case dismissed, mini, miniExpanded, open
}

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
            case .done: return "checkmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
        var color: Color {
            switch self {
            case .toolCall: return .blue
            case .done: return .green
            case .info: return .cyan
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
}

enum NotchTab: CaseIterable, Identifiable {
    case home, music, calendar, reminders, notes
    var id: Self { self }
    var icon: String {
        switch self {
        case .home: return "sparkle"
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .reminders: return "bell"
        case .notes: return "note.text"
        }
    }
    var label: String {
        switch self {
        case .home: return "Home"
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .notes: return "Notes"
        }
    }
}

@MainActor
final class FridayState: ObservableObject {
    static let shared = FridayState()
    private init() {
        $isListening.combineLatest($isThinking, $isSpeaking, $isDevTaskRunning)
            .map { $0 || $1 || $2 || $3 }
            .combineLatest($isPlayingMusic)
            .sink { [weak self] (isActive, isPlayingMusic) in
                self?.handleActivityChange(isActive: isActive, isPlayingMusic: isPlayingMusic)
            }
            .store(in: &cancellables)
        setupPeripheralObservation()
    }

    private var cancellables = Set<AnyCancellable>()
    private var dismissTimer: Timer?
    private var alertTimer: Timer?
    private var alertQueue: [SystemAlert] = []

    @Published var isListening = false { didSet { recordActivity() } }
    @Published var isThinking = false { didSet { recordActivity() } }
    @Published var isSpeaking = false { didSet { recordActivity() } }
    @Published var isError = false
    @Published var isConnected = false
    @Published var isDevTaskRunning = false { didSet { recordActivity() } }
    @Published var transcript = ""
    @Published var volume: Float = 0.0
    @Published var modelName = "Gemini 2.5 Flash"
    @Published var hasGreetedThisSession = false
    @Published var lastActivityTime = Date()
    @Published var activityFeed: [ActivityItem] = []
    @Published var longTermMemoryContext: String = ""

    @Published var displayState: NotchDisplayState = .dismissed {
        didSet {
            guard displayState != oldValue else { return }
            print("[State] displayState: \(oldValue) -> \(displayState)") 
            
            if (displayState == .mini || displayState == .miniExpanded) && !isUserInitiatedExpansion {
                let hasReason = activeAlert != nil || isHovering || isPlayingMusic || isActive
                if !hasReason {
                    print("[State] Blocked empty transition. Reverting to dismissed.")
                    displayState = .dismissed
                    return
                }
            }

            if displayState != .open { isUserInitiatedExpansion = false }
            if displayState == .dismissed { dismissTimer?.invalidate() }
        }
    }
    @Published var closedNotchSize: CGSize = CGSize(width: 200, height: 32)
    @Published var standardWidth: CGFloat = 440
    @Published var isUserInitiatedExpansion = false
    
    @Published var isHovering = false {
        didSet {
            if !isHovering && oldValue {
                showNextAlert() 
            }
        }
    }

    @Published var activeAlert: SystemAlert? = nil
    @Published var activeTab: NotchTab = .home

    @Published var isPlayingMusic = false { didSet { recordActivity() } }
    @Published var isMusicPaused = false { didSet { recordActivity() } }
    @Published var nowPlayingTitle = ""
    @Published var nowPlayingArtist = ""
    @Published var albumArt: NSImage? = nil
    @Published var albumAccentColor: Color = .cyan
    @Published var playbackPosition: TimeInterval = 0
    @Published var playbackDuration: TimeInterval = 0

    @Published var batteryLevel: Float = 0.0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var isInLowPowerMode: Bool = false
    @Published var lastMusicActivity: Date = Date()

    var hasMusicTrack: Bool { isPlayingMusic || isMusicPaused }
    var isActive: Bool { isListening || isThinking || isSpeaking || isDevTaskRunning }
    var isExpanded: Bool { displayState == .open }

    private var lastIsActive = false
    private var lastIsPlayingMusic = false

    private func handleActivityChange(isActive: Bool, isPlayingMusic: Bool) {
        guard isActive != lastIsActive || isPlayingMusic != lastIsPlayingMusic else { return }
        lastIsActive = isActive
        lastIsPlayingMusic = isPlayingMusic

        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            if isActive {
                if displayState == .dismissed || displayState == .mini {
                    displayState = .miniExpanded
                }
            } else if isPlayingMusic {
                if displayState == .dismissed {
                    displayState = .mini
                }
            } else {
                if displayState != .dismissed && activeAlert == nil && !isHovering {
                    startDismissTimer()
                }
            }
        }
    }

    private func startDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !self.isActive && !self.isUserInitiatedExpansion && self.activeAlert == nil && !self.isHovering {
                    withAnimation(.interactiveSpring(response: 0.8, dampingFraction: 0.9)) {
                        self.displayState = self.isPlayingMusic ? .mini : .dismissed
                    }
                }
            }
        }
    }

    private func showNextAlert() {
        guard !alertQueue.isEmpty else {
            if !self.isPlayingMusic && !self.isActive && (self.displayState == .mini || self.displayState == .miniExpanded) {
                if self.isHovering { return }
                withAnimation(.interactiveSpring(response: 0.8, dampingFraction: 0.9)) {
                    self.displayState = .dismissed
                }
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if self.alertQueue.isEmpty && !self.isHovering { self.activeAlert = nil }
                }
            } else if !self.isPlayingMusic && !self.isActive && !self.isHovering {
                self.activeAlert = nil
            }
            return
        }

        let alert = alertQueue.removeFirst()
        alertTimer?.invalidate()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            self.activeAlert = alert
            if displayState == .dismissed { displayState = .mini }
        }

        alertTimer = Timer.scheduledTimer(withTimeInterval: alert.duration, repeats: false) { [weak self] _ in
            Task { @MainActor in 
                guard let self = self else { return }
                if self.isHovering { return }
                self.showNextAlert() 
            }
        }
    }

    func postAlert(_ alert: SystemAlert) {
        Task { @MainActor in
            if activeAlert?.id == alert.id {
                activeAlert = alert
                alertTimer?.invalidate()
                alertTimer = Timer.scheduledTimer(withTimeInterval: alert.duration, repeats: false) { [weak self] _ in
                    Task { @MainActor in 
                        guard let self = self else { return }
                        if self.isHovering { return }
                        self.showNextAlert() 
                    }
                }
                return
            }
            alertQueue.append(alert)
            if activeAlert == nil { showNextAlert() }
        }
    }

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
