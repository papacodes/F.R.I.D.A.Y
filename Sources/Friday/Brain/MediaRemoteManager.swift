import AppKit
import SwiftUI

/// Bridges the macOS private MediaRemote framework.
/// Provides real-time now-playing info, artwork, and playback commands
/// for any media app — Apple Music, Spotify, YouTube Music, etc.
@MainActor
final class MediaRemoteManager {
    static let shared = MediaRemoteManager()
    private init() {}

    // MARK: - Private API types

    private typealias GetNowPlayingInfoFn     = @convention(c) (DispatchQueue, @escaping (NSDictionary?) -> Void) -> Void
    private typealias RegisterNotificationsFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn           = @convention(c) (UInt32, NSDictionary?) -> Bool

    private var _getNowPlayingInfo: GetNowPlayingInfoFn?
    private var _sendCommand: SendCommandFn?

    // MARK: - Keys (string literals avoid the Obj-C global constant concurrency issue)

    private let kTitle       = "kMRMediaRemoteNowPlayingInfoTitle"
    private let kArtist      = "kMRMediaRemoteNowPlayingInfoArtist"
    private let kArtwork     = "kMRMediaRemoteNowPlayingInfoArtworkData"
    private let kDuration    = "kMRMediaRemoteNowPlayingInfoDuration"
    private let kElapsed     = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    private let kRate        = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    private let kInfoChanged = "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
    private let kAppChanged  = "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"

    // MARK: - Position interpolation

    private var positionAtFetch: TimeInterval = 0
    private var fetchDate: Date = Date()
    private var playbackRate: Double = 0
    private var positionTimer: Timer?
    private var lastArtworkData: Data?

    // MARK: - Start

    func start() {
        guard let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        ) else {
            print("[MediaRemote] Framework not found — now-playing unavailable")
            return
        }

        func load<T>(_ name: String) -> T? {
            guard let ptr = CFBundleGetFunctionPointerForName(bundle, name as CFString) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        _getNowPlayingInfo = load("MRMediaRemoteGetNowPlayingInfo")
        _sendCommand       = load("MRMediaRemoteSendCommand")

        if let register: RegisterNotificationsFn = load("MRMediaRemoteRegisterForNowPlayingNotifications") {
            register(.main)
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(kInfoChanged), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.fetch() } }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(kAppChanged), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.fetch() } }

        fetch()

        // Poll every 2s as a safety net in case notifications don't fire
        positionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetch()
                self?.interpolatePosition()
            }
        }
    }

    // MARK: - Fetch

    func fetch() {
        if let fn = _getNowPlayingInfo {
            fn(.main) { [weak self] dict in
                let info = dict as? [String: Any] ?? [:]
                // If MediaRemote returned nothing useful, fall back to osascript
                if (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? "").isEmpty {
                    self?.osascriptFallback()
                } else {
                    self?.processInfo(info)
                }
            }
        } else {
            osascriptFallback()
        }
    }

    private func osascriptFallback() {
        Task.detached(priority: .background) {
            let script = """
            tell application "System Events"
                if (name of processes) contains "Music" then
                    tell application "Music"
                        if player state is playing then
                            return (name of current track) & "|||" & (artist of current track) & "|||playing"
                        else if player state is paused then
                            return (name of current track) & "|||" & (artist of current track) & "|||paused"
                        end if
                    end tell
                end if
            end tell
            """
            let p = Process()
            p.launchPath = "/usr/bin/osascript"
            p.arguments  = ["-e", script]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError  = Pipe()
            try? p.run(); p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = out.components(separatedBy: "|||")
            await MainActor.run {
                let s = FridayState.shared
                guard parts.count >= 2 else {
                    s.isPlayingMusic = false; s.isMusicPaused = false
                    s.nowPlayingTitle = ""; s.nowPlayingArtist = ""; return
                }
                s.nowPlayingTitle  = parts[0]
                s.nowPlayingArtist = parts[1]
                s.isPlayingMusic   = parts.count > 2 && parts[2] == "playing"
                s.isMusicPaused    = parts.count > 2 && parts[2] == "paused"
                s.recordActivity()
            }
        }
    }

    private func processInfo(_ info: [String: Any]) {
        let title    = info[kTitle]    as? String       ?? ""
        let artist   = info[kArtist]   as? String       ?? ""
        let duration = info[kDuration] as? TimeInterval ?? 0
        let elapsed  = info[kElapsed]  as? TimeInterval ?? 0
        let rate     = info[kRate]     as? Double       ?? 0

        let isPlaying = rate > 0
        let hasTrack  = !title.isEmpty

        let s = FridayState.shared
        s.isPlayingMusic   = isPlaying
        s.isMusicPaused    = hasTrack && !isPlaying
        s.recordActivity()
        s.nowPlayingTitle  = title
        s.nowPlayingArtist = artist
        s.playbackDuration = duration
        s.playbackPosition = elapsed

        positionAtFetch = elapsed
        fetchDate       = Date()
        playbackRate    = rate

        if let artData = info[kArtwork] as? Data, artData != lastArtworkData {
            lastArtworkData = artData
            Task.detached(priority: .utility) {
                let image = NSImage(data: artData)
                let color = image?.averageColor() ?? Color.cyan
                await MainActor.run {
                    FridayState.shared.albumArt          = image
                    FridayState.shared.albumAccentColor  = color
                }
            }
        } else if !hasTrack {
            s.albumArt         = nil
            s.albumAccentColor = .cyan
            lastArtworkData    = nil
        }
    }

    private func interpolatePosition() {
        guard playbackRate > 0 else { return }
        let interpolated = positionAtFetch + Date().timeIntervalSince(fetchDate) * playbackRate
        FridayState.shared.playbackPosition = min(interpolated, FridayState.shared.playbackDuration)
    }

    // MARK: - Commands
    // MRMediaRemoteCommand values: toggle=2, next=4, previous=5

    func togglePlayPause() { _ = _sendCommand?(2, nil) }
    func nextTrack()        { _ = _sendCommand?(4, nil) }
    func previousTrack()    { _ = _sendCommand?(5, nil) }

    func seek(to position: TimeInterval) {
        FridayState.shared.playbackPosition = position
        positionAtFetch = position
        fetchDate = Date()
        Task.detached {
            let p = Process()
            p.launchPath = "/usr/bin/osascript"
            p.arguments  = ["-e", "tell application \"Music\" to set player position to \(position)"]
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
        }
    }
}
