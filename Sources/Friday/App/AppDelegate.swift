import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = NotchWindowController()

        hotkeyManager = HotkeyManager {
            Task { @MainActor in
                self.windowController?.toggle()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
