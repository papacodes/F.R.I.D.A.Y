import Foundation

struct MusicSkill {
    @discardableResult
    static func executeAppleScript(_ script: String) -> String {
        guard let appleScript = NSAppleScript(source: script) else { return "Error creating script" }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        if let err = error {
            return "AppleScript error: \(err)"
        }
        return result.stringValue ?? "Success"
    }

    static func play() -> String {
        executeAppleScript("tell application \"Music\" to play")
        return "Playing music."
    }

    static func pause() -> String {
        executeAppleScript("tell application \"Music\" to pause")
        return "Paused music."
    }

    static func nextTrack() -> String {
        executeAppleScript("tell application \"Music\" to next track")
        return "Skipped to the next track."
    }

    static func playSearch(_ query: String) -> String {
        let script = """
        tell application "Music"
            set foundTracks to (every track of playlist 1 whose name contains "\(query)" or artist contains "\(query)")
            if (count of foundTracks) > 0 then
                play item 1 of foundTracks
                return "Playing " & name of item 1 of foundTracks & " by " & artist of item 1 of foundTracks
            else
                return "I couldn\"t find any music matching \\"\(query)\\"."
            end if
        end tell
        """
        return executeAppleScript(script)
    }

    static func playPlaylist(_ name: String) -> String {
        let script = """
        tell application "Music"
            if exists (some playlist whose name contains "\(name)") then
                set targetPlaylist to some playlist whose name contains "\(name)"
                play targetPlaylist
                return "Playing playlist " & name of targetPlaylist
            else
                return "I couldn\"t find a playlist named \\"\(name)\\"."
            end if
        end tell
        """
        return executeAppleScript(script)
    }
}
