import AppKit
import SwiftUI

@MainActor
final class MediaRemoteManager {
    static let shared = MediaRemoteManager()
    private init() {}

    private typealias GetNowPlayingInfoFn     = @convention(c) (DispatchQueue, @escaping (NSDictionary?) -> Void) -> Void
    private typealias RegisterNotificationsFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn           = @convention(c) (UInt32, NSDictionary?) -> Bool

    private var _getNowPlayingInfo: GetNowPlayingInfoFn?
    private var _sendCommand: SendCommandFn?

    private let kTitle       = "kMRMediaRemoteNowPlayingInfoTitle"
    private let kArtist      = "kMRMediaRemoteNowPlayingInfoArtist"
    private let kArtwork     = "kMRMediaRemoteNowPlayingInfoArtworkData"
    private let kDuration    = "kMRMediaRemoteNowPlayingInfoDuration"
    private let kElapsed     = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    private let kRate        = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    private let kAppBundle   = "kMRMediaRemoteNowPlayingApplicationBundleIdentifier"
    private let kInfoChanged = "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
    private let kAppChanged  = "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"

    private var positionAtFetch: TimeInterval = 0
    private var fetchDate: Date = Date()
    private var playbackRate: Double = 0
    private var positionTimer: Timer?
    private var lastArtworkData: Data?
    private var lastTrackTitle: String = ""

    func start() {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")) else { return }

        func load<T>(_ name: String) -> T? {
            guard let ptr = CFBundleGetFunctionPointerForName(bundle, name as CFString) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        _getNowPlayingInfo = load("MRMediaRemoteGetNowPlayingInfo")
        _sendCommand       = load("MRMediaRemoteSendCommand")

        if let register: RegisterNotificationsFn = load("MRMediaRemoteRegisterForNowPlayingNotifications") {
            register(.main)
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name(kInfoChanged), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.fetch() } }
        NotificationCenter.default.addObserver(forName: NSNotification.Name(kAppChanged), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.fetch() } }

        fetch()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetch()
                self?.interpolatePosition()
            }
        }
    }

    func fetch() {
        _getNowPlayingInfo?(.main) { [weak self] dict in
            let info = dict as? [String: Any] ?? [:]
            if (info[self?.kTitle ?? ""] as? String ?? "").isEmpty {
                self?.osascriptFallback()
            } else {
                self?.processInfo(info)
            }
        }
    }

    private func osascriptFallback() {
        Task {
            let script = """
            tell application "System Events"
                if (name of processes) contains "Music" then
                    tell application "Music"
                        if player state is playing or player state is paused then
                            return (name of current track) & "|||" & (artist of current track) & "|||" & (player state as string)
                        end if
                    end tell
                end if
            end tell
            return ""
            """
            let out = try? await runAppleScript(script)
            let parts = out?.components(separatedBy: "|||") ?? []
            
            if parts.count >= 2 {
                let s = FridayState.shared
                s.nowPlayingTitle  = parts[0]
                s.nowPlayingArtist = parts[1]
                s.isPlayingMusic   = parts.count > 2 && parts[2] == "playing"
                s.isMusicPaused    = parts.count > 2 && parts[2] == "paused"
                
                if s.albumArt == nil { fetchAppleMusicArtwork() }
            }
        }
    }

    private func fetchAppleMusicArtwork() {
        let tempPath = "/tmp/friday_art.jpg"
        Task.detached(priority: .utility) {
            let script = """
            try
                tell application "Music"
                    if (count of artworks of current track) > 0 then
                        set artData to raw data of artwork 1 of current track
                        set artFile to open for access POSIX file "\(tempPath)" with write permission
                        set eof artFile to 0
                        write artData to artFile
                        close access artFile
                        return "success"
                    end if
                end tell
            end try
            return "fail"
            """
            let p = Process()
            p.launchPath = "/usr/bin/osascript"
            p.arguments = ["-e", script]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
            
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if out == "success" {
                if let image = NSImage(contentsOfFile: tempPath) {
                    await MainActor.run {
                        FridayState.shared.albumArt = image
                        FridayState.shared.albumAccentColor = image.averageColor()
                    }
                }
            }
        }
    }

    private func fetchSpotifyArtwork(url: String) {
        guard let url = URL(string: url) else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let image = NSImage(data: data) {
                FridayState.shared.albumArt = image
                FridayState.shared.albumAccentColor = image.averageColor()
            }
        }
    }

    private func processInfo(_ info: [String: Any]) {
        let title    = info[kTitle]    as? String ?? ""
        let artist   = info[kArtist]   as? String ?? ""
        let duration = info[kDuration] as? TimeInterval ?? 0
        let elapsed  = info[kElapsed]  as? TimeInterval ?? 0
        let rate     = info[kRate]     as? Double ?? 0
        let bundle   = info[kAppBundle] as? String ?? ""

        let isPlaying = rate > 0
        let hasTrack  = !title.isEmpty

        let s = FridayState.shared
        s.isPlayingMusic   = isPlaying
        s.isMusicPaused    = hasTrack && !isPlaying
        s.nowPlayingTitle  = title
        s.nowPlayingArtist = artist
        s.playbackDuration = duration
        s.playbackPosition = elapsed

        if isPlaying {  }

        if title != lastTrackTitle {
            lastTrackTitle = title
            s.albumArt = nil // Clear for new track
            lastArtworkData = nil
        }

        positionAtFetch = elapsed
        fetchDate       = Date()
        playbackRate    = rate

        if let artData = info[kArtwork] as? Data {
            if artData != lastArtworkData {
                lastArtworkData = artData
                if let image = NSImage(data: artData) {
                    s.albumArt = image
                    s.albumAccentColor = image.averageColor()
                }
            }
        } else if hasTrack {
            if bundle.contains("spotify") {
                // Spotify uses a different key for URL
                if let url = info["kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] as? String {
                    fetchSpotifyArtwork(url: url)
                }
            } else if bundle.contains("apple.Music") || bundle.isEmpty {
                fetchAppleMusicArtwork()
            }
        }
    }

    private func interpolatePosition() {
        guard playbackRate > 0 else { return }
        let interpolated = positionAtFetch + Date().timeIntervalSince(fetchDate) * playbackRate
        FridayState.shared.playbackPosition = min(interpolated, FridayState.shared.playbackDuration)
    }

    private func runAppleScript(_ script: String) async throws -> String {
        let p = Process()
        p.launchPath = "/usr/bin/osascript"
        p.arguments = ["-e", script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Media Controls (Reliable osascript implementation)

    private func sendMediaCommand(osascriptAction: String) {
        Task {
            let script = """
            tell application "System Events"
                set musicRunning to (name of processes) contains "Music"
                set spotifyRunning to (name of processes) contains "Spotify"
                
                if musicRunning then
                    tell application "Music" to \(osascriptAction)
                else if spotifyRunning then
                    tell application "Spotify" to \(osascriptAction)
                end if
            end tell
            """
            _ = try? await runAppleScript(script)
        }
    }

    func togglePlayPause() {
        sendMediaCommand(osascriptAction: "playpause")
    }

    func nextTrack() {
        sendMediaCommand(osascriptAction: "next track")
    }

    func previousTrack() {
        sendMediaCommand(osascriptAction: "previous track")
    }

    func seek(to position: TimeInterval) {
        FridayState.shared.playbackPosition = position
        positionAtFetch = position
        fetchDate = Date()
        Task {
            let script = """
            tell application "System Events"
                if (name of processes) contains "Music" then
                    tell application "Music" to set player position to \(position)
                -- Reliable seek for Spotify is not feasible via simple AppleScript
                end if
            end tell
            """
            _ = try? await runAppleScript(script)
        }
    }
}
