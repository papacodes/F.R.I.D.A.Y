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

// MARK: - Active Task (per execute_dev_task invocation)

struct ActiveTask: Identifiable, Equatable {
    let id: String          // project key — e.g. "friday", "oats", "default"
    var label: String       // short display name derived from path
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
        // Panel visibility is driven by session state and dev tasks — not per-turn flags.
        // Per-turn flags (isListening, isThinking, isSpeaking) only drive UI content within the session.
        $isFridaySessionActive
            .combineLatest($isDevTaskRunning)
            .map { $0 || $1 }
            .combineLatest($isPlayingMusic)
            .sink { [weak self] (isActive, isPlayingMusic) in
                self?.handleActivityChange(isActive: isActive, isPlayingMusic: isPlayingMusic)
            }
            .store(in: &cancellables)
        setupPeripheralObservation()
    }

    private var cancellables = Set<AnyCancellable>()
    private var dismissTimer: Timer?

    // MARK: - Friday session state (per-turn)

    @Published var isListening = false { didSet { recordActivity() } }
    @Published var isThinking = false { didSet { recordActivity() } }
    @Published var isSpeaking = false { didSet { recordActivity() } }
    @Published var isError = false
    @Published var isConnected = false
    @Published var isDevTaskRunning = false { didSet { recordActivity() } }
    private var devTaskCount = 0
    @Published var transcript = ""
    @Published var volume: Float = 0.0
    @Published var modelName = "Gemini 2.5 Flash"
    @Published var hasGreetedThisSession = false
    @Published var lastActivityTime = Date()
    @Published var activityFeed: [ActivityItem] = []
    @Published var activeTasks: [ActiveTask] = []
    @Published var longTermMemoryContext: String = ""

    // MARK: - Friday session lifecycle

    /// True from the moment Friday wakes until she is explicitly dismissed.
    /// This is the authoritative flag for panel persistence — completely independent
    /// of per-turn processing state. The panel stays up as long as this is true.
    @Published var isFridaySessionActive = false

    // MARK: - Display state

    @Published var displayState: NotchDisplayState = .dismissed {
        didSet {
            guard displayState != oldValue else { return }
            print("[State] displayState: \(oldValue) -> \(displayState)")

            // isActive is the absolute override — no timer or guard may dismiss while active
            if isActive && (displayState == .mini || displayState == .dismissed) {
                print("[State] Active — blocked \(displayState). Holding at .miniExpanded.")
                displayState = .miniExpanded
                return
            }

            // Notification guard — block empty transitions when not active
            if (displayState == .mini || displayState == .miniExpanded) && !isUserInitiatedExpansion && !isActive {
                let hasReason = activeAlert != nil || isHovering || isPlayingMusic
                if !hasReason {
                    print("[State] Blocked empty transition to \(displayState). Reverting to dismissed.")
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
            // Hover exit — let the alert engine decide what to do next
            if !isHovering && oldValue {
                NotchAlertEngine.shared.showNextAlert()
            }
        }
    }

    // Owned by FridayState as a published property so views can observe it.
    // Written by NotchAlertEngine, never by Friday's session logic.
    @Published var activeAlert: SystemAlert? = nil
    @Published var activeTab: NotchTab = .home

    // MARK: - Music state

    @Published var isPlayingMusic = false { didSet { recordActivity() } }
    @Published var isMusicPaused = false { didSet { recordActivity() } }
    @Published var nowPlayingTitle = ""
    @Published var nowPlayingArtist = ""
    @Published var albumArt: NSImage? = nil
    @Published var albumAccentColor: Color = .cyan
    @Published var playbackPosition: TimeInterval = 0
    @Published var playbackDuration: TimeInterval = 0

    // MARK: - System state

    @Published var batteryLevel: Float = 0.0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var isInLowPowerMode: Bool = false
    @Published var lastMusicActivity: Date = Date()

    // MARK: - Computed

    var hasMusicTrack: Bool { isPlayingMusic || isMusicPaused }

    /// True when a Friday session is live or a dev task is running.
    /// Per-turn flags (isListening, isThinking, isSpeaking) do NOT contribute here —
    /// they drive UI content only. Panel persistence is governed by isFridaySessionActive.
    var isActive: Bool { isFridaySessionActive || isDevTaskRunning }

    var isExpanded: Bool { displayState == .open }

    // MARK: - Activity

    private var lastIsActive = false
    private var lastIsPlayingMusic = false

    private func handleActivityChange(isActive: Bool, isPlayingMusic: Bool) {
        guard isActive != lastIsActive || isPlayingMusic != lastIsPlayingMusic else { return }
        lastIsActive = isActive
        lastIsPlayingMusic = isPlayingMusic

        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            if isActive {
                // Session started — hold in assistant view but never close the open panel
                if self.displayState != .open {
                    self.displayState = .miniExpanded
                }
                self.dismissTimer?.invalidate()
                self.dismissTimer = nil
            } else {
                // Session ended
                if isPlayingMusic {
                    if displayState == .dismissed { self.displayState = .mini }
                } else {
                    if displayState != .dismissed && activeAlert == nil && !isHovering {
                        startDismissTimer()
                    }
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

    // MARK: - Helpers

    func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<FridayState, T>, to value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    func recordActivity() { lastActivityTime = Date(); lastMusicActivity = Date() }

    /// Increment the running task counter. Sets isDevTaskRunning when the first task starts.
    func beginDevTask() {
        devTaskCount += 1
        isDevTaskRunning = true
    }

    /// Decrement the running task counter. Clears isDevTaskRunning only when the last task finishes.
    func endDevTask() {
        devTaskCount = max(0, devTaskCount - 1)
        isDevTaskRunning = devTaskCount > 0
    }

    // MARK: - Active task management

    func startTask(id: String, label: String) {
        let task = ActiveTask(id: id, label: label, status: .running, currentStep: "Starting...", log: [])
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeTasks.removeAll { $0.id == id }
            activeTasks.append(task)
        }
        beginDevTask()
    }

    func updateTask(id: String, step: String, isError: Bool = false) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        let entry = ActiveTask.LogEntry(text: step, isError: isError)
        activeTasks[idx].currentStep = step
        activeTasks[idx].log.append(entry)
        if activeTasks[idx].log.count > 60 { activeTasks[idx].log.removeFirst() }
    }

    func completeTask(id: String) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeTasks[idx].status = .done
            activeTasks[idx].currentStep = "Done"
        }
        endDevTask()
    }

    func errorTask(id: String, message: String) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeTasks[idx].status = .error
            activeTasks[idx].currentStep = message
            activeTasks[idx].log.append(.init(text: message, isError: true))
        }
        endDevTask()
    }

    func dismissTask(id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeTasks.removeAll { $0.id == id }
        }
    }

    func dismissCompletedTasks() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeTasks.removeAll { $0.status == .done || $0.status == .error }
        }
    }

    func addActivity(type: ActivityItem.ActivityType, title: String, subtitle: String? = nil) {
        let item = ActivityItem(type: type, title: title, subtitle: subtitle)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            activityFeed.insert(item, at: 0)
            if activityFeed.count > 10 { activityFeed.removeLast() }
        }
    }

    // MARK: - Peripherals

    @Published var peripheralManager = PeripheralManager()
    @Published var airPodsConnectionState: AirPodsConnectionState = .disconnected

    private func setupPeripheralObservation() {
        peripheralManager.$airPodsState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.airPodsConnectionState = state
                if case .connected(let name, let status) = state {
                    let avgBattery = ((status.left ?? 0) + (status.right ?? 0)) / 2
                    NotchAlertEngine.shared.postAlert(SystemAlert.airpods(name: name, level: avgBattery))
                }
            }
            .store(in: &cancellables)
    }
}
