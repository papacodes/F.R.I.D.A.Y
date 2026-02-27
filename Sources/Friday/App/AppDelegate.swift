import AppKit
import ApplicationServices

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?
    private var hotkeyManager: HotkeyManager?
    private var accessibilityCheckTimer: Timer?

    static let pipeline = GeminiVoicePipeline(state: FridayState.shared)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AXIsProcessTrusted() {
            launch()
        } else {
            requestAccessibilityAndWait()
        }
    }

    // MARK: - Private

    private func launch() {
        windowController = NotchWindowController()

        hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in
                self?.windowController?.toggle()
            }
        }

        Task { await AppDelegate.pipeline.start() }
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
}
