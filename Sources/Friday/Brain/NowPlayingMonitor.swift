import Foundation

/// Polls Music.app every 3 seconds via osascript to keep FridayState music fields current.
/// Gracefully does nothing if Music.app isn't running or automation isn't permitted.
@MainActor
final class NowPlayingMonitor {
    static let shared = NowPlayingMonitor()
    private var timer: Timer?
    private init() {}

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func poll() {
        Task.detached(priority: .background) {
            let script = """
            tell application "System Events"
                if (name of processes) contains "Music" then
                    tell application "Music"
                        if player state is playing then
                            return (name of current track) & "|||" & (artist of current track)
                        end if
                    end tell
                end if
            end tell
            """
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments  = ["-e", script]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError  = Pipe()

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                return
            }

            let data   = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            await MainActor.run {
                if output.isEmpty {
                    FridayState.shared.isPlayingMusic   = false
                    FridayState.shared.nowPlayingTitle  = ""
                    FridayState.shared.nowPlayingArtist = ""
                } else {
                    let parts = output.components(separatedBy: "|||")
                    FridayState.shared.isPlayingMusic   = true
                    FridayState.shared.nowPlayingTitle  = parts.first ?? ""
                    FridayState.shared.nowPlayingArtist = parts.count > 1 ? parts[1] : ""
                }
            }
        }
    }
}
