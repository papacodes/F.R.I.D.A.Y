import Foundation

struct ScreenCaptureSkill {
    static func captureAndAnalyze(prompt: String) async -> String {
        let tempPath = "/tmp/friday-screen.png"
        
        // 1. Capture screen
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", tempPath]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Error: Failed to run screencapture: \(error.localizedDescription)"
        }
        
        // 2. Resize to 1280px wide using sips (keeps payload manageable)
        let sips = Process()
        sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        sips.arguments = ["-Z", "1280", tempPath]
        
        do {
            try sips.run()
            sips.waitUntilExit()
        } catch {
            return "Error: Failed to resize screenshot: \(error.localizedDescription)"
        }
        
        // 3. Encode to base64
        if let imageData = try? Data(contentsOf: URL(fileURLWithPath: tempPath)) {
            let base64 = imageData.base64EncodedString()
            try? FileManager.default.removeItem(atPath: tempPath)
            return "[SCREENSHOT_CAPTURED]\(base64)"
        }
        
        return "Error: Failed to read captured screenshot."
    }
}
