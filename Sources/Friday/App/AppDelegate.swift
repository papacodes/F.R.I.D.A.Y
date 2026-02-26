import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?
    private var hotkeyManager: HotkeyManager?
    
    static let pipeline = GeminiVoicePipeline(state: FridayState.shared)

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = NotchWindowController()
        
        // HotkeyManager requires the toggle action on init
        hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in
                self?.windowController?.toggle()
            }
        }
        
        Task { await AppDelegate.pipeline.start() }
    }
}
