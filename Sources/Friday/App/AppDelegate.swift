import AppKit
import ApplicationServices
import Foundation // Import Foundation for file management

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchUIEngine?
    private var hotkeyManager: HotkeyManager?
    private var accessibilityCheckTimer: Timer?

    static let pipeline = LocalVoicePipeline(state: FridayState.shared)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.pipeline.start() // Start brain loading immediately, don't wait for AX
        
        if AXIsProcessTrusted() {
            launch()
        } else {
            requestAccessibilityAndWait()
        }
    }

    // MARK: - Private

    private func launch() {
        loadMemory() // Load long-term memory context on launch
        RAGSkill.startIndexing() // Kick off background notes indexing

        windowController = NotchUIEngine()

        hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in
                self?.windowController?.toggle()
            }
        }

        MediaRemoteManager.shared.start()
        _ = BatteryManager.shared
        SystemNotificationManager.shared.start() // Start battery monitoring
        WakeWordEngine.shared.requestPermission()
    }

    private func requestAccessibilityAndWait() {
        // Triggers the macOS "wants accessibility access" prompt
        // Using the raw string key to avoid Swift 6 concurrency issues with kAXTrustedCheckOptionPrompt
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options)

        // Poll until granted — user may take a moment in System Settings
        // Once trusted we launch and cancel the timer
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if AXIsProcessTrusted() {
                    self.accessibilityCheckTimer?.invalidate()
                    self.accessibilityCheckTimer = nil
                    self.launch()
                }
            }
        }
    }

    /// Loads Friday's operational knowledge base from the notes workspace.
    private func loadMemory() {
        let memoryPath = NSString(string: "~/Documents/notes/projects/friday/GEMINI.md").expandingTildeInPath
        do {
            let context = try String(contentsOfFile: memoryPath, encoding: .utf8)
            FridayState.shared.longTermMemoryContext = context
            FridayState.shared.addActivity(type: .info, title: "Memory Loaded", subtitle: "Context file read successfully.")
            print("Loaded long-term memory context.")
        } catch {
            FridayState.shared.addActivity(type: .error, title: "Memory Load Failed", subtitle: error.localizedDescription)
            print("Failed to load long-term memory: \(error.localizedDescription)")
        }
    }
}
