@preconcurrency import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class GeminiVoicePipeline: NSObject, URLSessionWebSocketDelegate {

    private let state: FridayState
    private let audioProcessor = AudioProcessor()

    private var wsTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    /// Resumed with `true` on open, `false` on handshake failure — prevents connect() hanging forever.
    private var connectionContinuation: CheckedContinuation<Bool, Never>?
    private var isConnecting = false
    private var isReconnecting = false
    private var reconnectAttempts = 0
    /// Set before any intentional disconnect — prevents receiveLoop from triggering reconnect.
    private var intentionalStop = false

    private let outputEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24000,
        channels: 1,
        interleaved: false
    )!

    init(state: FridayState) {
        self.state = state
    }

    func start() async {
        if wsTask != nil { return }
        await connect()
    }

    func wake() async {
        await start() // Ensure we connect first
        audioProcessor.isMuted = false
        state.recordActivity()
        
        try? await Task.sleep(nanoseconds: 400_000_000)
        
        if !state.isListening && !state.isSpeaking && !state.isThinking {
            await sendGreeting()
        }
    }

    func sleep() async {
        audioProcessor.isMuted = true
        playerNode.stop()
        await wrapUpSession()
    }

    func stop() {
        isConnecting = false
        reconnectAttempts = 0
        intentionalStop = true
        let task = wsTask
        wsTask = nil
        audioProcessor.wsTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        task?.cancel(with: .goingAway, reason: nil)
        
        audioProcessor.isMuted = true
        audioProcessor.stop()
        playerNode.stop()
        outputEngine.stop()
        
        state.update(\.isListening, to: false)
        state.update(\.isThinking, to: false)
        state.update(\.isSpeaking, to: false)
        state.update(\.isConnected, to: false)
        state.update(\.volume, to: 0.0)
        state.update(\.isError, to: false)
    }

    /// Graceful shutdown: asks Gemini to write session notes and say goodbye,
    /// then dismisses when turnComplete arrives (or after a 15s fallback).
    /// Call this instead of stop() for intentional user-initiated dismissals.
    func startGracefulStop() {
        guard wsTask != nil else { return }
        intentionalStop = true
        let dateStr: String = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
        }()
        let notePath = "~/Documents/notes/projects/friday/sessions/\(dateStr).md"
        let msg = ClientContentMessage(clientContent: ClientContent(turns: [
            ContentTurn(role: "user", parts: [TextPart(text: "System: Session ending. Write a brief note to \(notePath) — what was worked on today, what carries forward. Then say a quick goodbye.")])
        ], turnComplete: true))
        Task { await self.sendEncoded(msg) }
        // Fallback: force dismiss if Gemini doesn't complete
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard self?.intentionalStop == true else { return }
            NotificationCenter.default.post(name: .fridayDismiss, object: nil)
        }
    }

    private func connect() async {
        guard !isConnecting else { return }
        intentionalStop = false
        guard let apiKey = Config.shared.apiKey, !apiKey.isEmpty else {
            state.update(\.isError, to: true)
            return
        }

        isConnecting = true
        let endpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else { isConnecting = false; return }

        var request = URLRequest(url: url)
        request.setValue("https://aistudio.google.com", forHTTPHeaderField: "Origin")

        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let ws = urlSession!.webSocketTask(with: request)
        ws.resume()
        wsTask = ws
        audioProcessor.wsTask = ws

        setupOutputAudio()

        let connected = await withCheckedContinuation { cont in
            self.connectionContinuation = cont
        }
        self.connectionContinuation = nil

        guard connected else {
            isConnecting = false
            // Handshake failed — schedule retry from outside the continuation
            Task { await reconnect() }
            return
        }

        await sendSetup()
        Task { await receiveLoop() }
        isConnecting = false
    }

    /// Exponential backoff reconnect. Cleans up the stale session before each attempt.
    private func reconnect() async {
        guard !isReconnecting else { return }
        // wsTask being non-nil means we still want a connection (not an intentional stop)
        guard wsTask != nil || state.isConnected else { return }
        isReconnecting = true
        defer { isReconnecting = false }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), 30.0) // 1, 2, 4, 8, 16, 30…
        print("Friday: reconnect attempt \(reconnectAttempts) in \(Int(delay))s")
        state.update(\.isConnected, to: false)
        state.update(\.isError, to: true)

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        // Bail if stop() was called while we were sleeping
        guard wsTask != nil || reconnectAttempts > 0 else { return }

        // Tear down the stale session cleanly before creating a new one
        let stale = urlSession
        urlSession = nil
        wsTask = nil
        audioProcessor.wsTask = nil
        stale?.invalidateAndCancel()
        isConnecting = false

        await connect()
    }

    private func sendSetup() async {
        let knowledgeBase = state.longTermMemoryContext.isEmpty
            ? ""
            : "\n\n---\n\n\(state.longTermMemoryContext)"

        let instructions = """
        You are Friday, Papa's macOS AI assistant living in his MacBook's notch.
        Dev capabilities: You have direct file system and shell access via read_file, write_file, list_directory, and run_shell. Code lives in ~/projects/. Notes live in ~/Documents/notes/.
        Shell: run_shell runs any zsh command. Always pass a directory when the command is project-specific.
        Call disconnect_session when Papa says goodbye or the conversation is finished.
        \(knowledgeBase)
        """

        let msg = SetupMessage(
            setup: SetupPayload(
                model: "models/gemini-2.5-flash-native-audio-preview-12-2025",
                generationConfig: GenerationConfig(
                    responseModalities: ["audio"],
                    speechConfig: nil,
                    inputAudioTranscription: nil,
                    outputAudioTranscription: nil
                ),
                systemInstruction: SystemInstruction(parts: [TextPart(text: instructions)]),
                tools: [ToolsList(functionDeclarations: [
                    Self.readFileTool, Self.writeFileTool, Self.listDirectoryTool, Self.runShellTool,
                    Self.weatherTool, Self.timeTool, Self.batteryTool,
                    Self.mapTool, Self.searchTool, Self.musicTool,
                    Self.playlistTool, Self.notesTool, Self.remindersTool,
                    Self.calendarTool, Self.disconnectTool
                ])]
            )
        )
        await sendEncoded(msg)
    }

    private func receiveLoop() async {
        while let ws = wsTask, ws.state == .running {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) { await handleServer(data) }
                case .data(let data):
                    await handleServer(data)
                @unknown default: break
                }
            } catch {
                if wsTask != nil { print("Friday: WebSocket receive error — \(error)") }
                break
            }
        }

        // Unintentional drop — reconnect with backoff (skip if we stopped intentionally)
        if !isConnecting && !intentionalStop { await reconnect() }
    }

    private func handleServer(_ data: Data) async {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let msg = try decoder.decode(ServerMessage.self, from: data)
            
            if msg.error != nil {
                state.update(\.isError, to: true)
                return
            }

            if msg.setupComplete != nil {
                // Stable session confirmed — check before resetting so we know if this is a reconnect
                let wasReconnect = reconnectAttempts > 0
                reconnectAttempts = 0
                audioProcessor.start(ws: wsTask) { [weak self] active, rms in
                    DispatchQueue.main.async {
                        self?.state.update(\.isListening, to: active)
                        if active { self?.state.update(\.volume, to: rms) }
                        else if self?.state.isSpeaking == false { self?.state.update(\.volume, to: 0.0) }
                    }
                }
                if wasReconnect {
                    Task { await self.sendReconnectNotice() }
                }
            }

            if let content = msg.serverContent {
                if content.turnComplete == true {
                    state.update(\.isSpeaking, to: false)
                    audioProcessor.isMuted = false
                    state.update(\.volume, to: 0.0)
                    // Intentional stop (voice goodbye or UI dismiss) — wait for audio to finish then close
                    if intentionalStop {
                        Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            guard self?.intentionalStop == true else { return }
                            NotificationCenter.default.post(name: .fridayDismiss, object: nil)
                        }
                    }
                }

                if let turn = content.modelTurn {
                    for part in turn.parts {
                        if let inline = part.inlineData, let audioData = Data(base64Encoded: inline.data) {
                            if !state.isSpeaking {
                                state.update(\.isSpeaking, to: true)
                                audioProcessor.isMuted = true  // prevent echo while speaking
                            }
                            playPCMChunk(audioData)
                        }
                    }
                }

                if let t = content.outputTranscription { state.update(\.transcript, to: t.text) }
            }

            if let toolCall = msg.toolCall {
                // Unmute mic so Papa can interrupt while tools are running
                audioProcessor.isMuted = false
                for call in toolCall.functionCalls {
                    Task { await handleToolCall(call) }
                }
            }
        } catch { /* noise */ }
    }

    private func setupOutputAudio() {
        outputEngine.attach(playerNode)
        outputEngine.connect(playerNode, to: outputEngine.mainMixerNode, format: playbackFormat)
        outputEngine.prepare()
        try? outputEngine.start()
        playerNode.play()
    }

    private func playPCMChunk(_ data: Data) {
        let frameCount = data.count / 2
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let floats = buffer.floatChannelData![0]
        var sum: Float = 0
        data.withUnsafeBytes { raw in
            let int16s = raw.bindMemory(to: Int16.self)
            for i in 0..<frameCount { 
                let s = Float(int16s[i]) / 32768.0
                floats[i] = s
                sum += s * s
            }
        }
        let rms = sqrt(sum / Float(max(frameCount, 1)))
        state.update(\.volume, to: rms)
        playerNode.scheduleBuffer(buffer)
    }

    private func handleToolCall(_ call: FunctionCall) async {
        state.update(\.isThinking, to: true)
        var result = "Task complete."
        
        switch call.name {
        case "read_file":
            if let path = call.args["path"] {
                state.update(\.isDevTaskRunning, to: true)
                result = FileSystemSkill.readFile(path: path)
                state.update(\.isDevTaskRunning, to: false)
            }

        case "write_file":
            if let path = call.args["path"], let content = call.args["content"] {
                state.update(\.isDevTaskRunning, to: true)
                result = FileSystemSkill.writeFile(path: path, content: content)
                state.update(\.isDevTaskRunning, to: false)
            }

        case "list_directory":
            if let path = call.args["path"] {
                result = FileSystemSkill.listDirectory(path: path)
            }

        case "run_shell":
            if let command = call.args["command"] {
                state.update(\.isDevTaskRunning, to: true)
                result = await ShellSkill.run(command, directory: call.args["directory"])
                state.update(\.isDevTaskRunning, to: false)
            }

        case "get_weather":
            result = await WeatherSkill.fetchWeather()
        case "get_time":
            result = "It is currently \(TimeSkill.getCurrentTime()) on \(TimeSkill.getCurrentDate())."
        case "get_battery_status":
            result = BatterySkill.getBatteryStatus()
        case "find_nearby_places":
            if let q = call.args["query"] { result = await MapsSkill.findNearby(q) }
        case "web_search":
            if let q = call.args["query"] { result = await SearchSkill.searchWeb(q) }
        case "control_music":
            if let action = call.args["action"] {
                switch action {
                case "play": result = MusicSkill.play()
                case "pause": result = MusicSkill.pause()
                case "next": result = MusicSkill.nextTrack()
                case "search": 
                    if let q = call.args["query"] { result = MusicSkill.playSearch(q) }
                default: result = "Music action not recognized."
                }
            }
        case "play_playlist":
            if let name = call.args["name"] { result = MusicSkill.playPlaylist(name) }
        case "manage_notes":
            if let action = call.args["action"] {
                let filename = call.args["filename"] ?? "FridayNotes"
                let content = call.args["content"] ?? ""
                switch action {
                case "create": result = NotesSkill.createNote(filename: filename, content: content)
                case "read": result = NotesSkill.readNote(filename: filename)
                case "append": result = NotesSkill.appendToNote(filename: filename, content: content)
                case "list": result = NotesSkill.listNotes()
                case "delete": result = NotesSkill.deleteNote(filename: filename)
                default: result = "Notes action not recognized."
                }
            }
        case "manage_reminders":
            if let action = call.args["action"] {
                if action == "add", let title = call.args["title"] {
                    let date = call.args["due_date"].map { DateHelper.parseAndFormat($0) }
                    result = RemindersSkill.addReminder(title: title, dueDate: date)
                } else if action == "list" {
                    result = RemindersSkill.listReminders()
                }
            }
        case "manage_calendar":
            if let action = call.args["action"] {
                if action == "add", let title = call.args["title"], let start = call.args["start_time"] {
                    let s = DateHelper.parseAndFormat(start)
                    let e = call.args["end_time"].map { DateHelper.parseAndFormat($0) }
                    result = CalendarSkill.addEvent(title: title, startTime: s, endTime: e)
                } else if action == "get_schedule" {
                    let d = call.args["date"].map { DateHelper.parseAndFormat($0) }
                    result = CalendarSkill.getSchedule(forDate: d)
                }
            }
        case "disconnect_session":
            intentionalStop = true
            let dateStr: String = {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
            }()
            let notePath = "~/Documents/notes/projects/friday/sessions/\(dateStr).md"
            result = "Closing session. Write a brief session note to \(notePath) — what was worked on today, key decisions, what carries forward. Append to the file if it already exists. Then say a brief goodbye to Papa."
            // Fallback: if Gemini doesn't complete within 15s, force dismiss
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard self?.intentionalStop == true else { return }
                NotificationCenter.default.post(name: .fridayDismiss, object: nil)
            }
        default:
            result = "Tool not found."
        }

        state.update(\.isThinking, to: false)
        let response = ToolResponseMessage(toolResponse: ToolResponseBody(functionResponses: [
            FunctionResponseItem(id: call.id, name: call.name, response: ["output": result])
        ]))
        await sendEncoded(response)
    }

    private func sendReconnectNotice() async {
        // Fresh session after a drop — session context was lost, keep it honest and brief
        let msg = ClientContentMessage(clientContent: ClientContent(turns: [
            ContentTurn(role: "user", parts: [TextPart(text: "System: Connection was interrupted and just restored. Tell Papa you're back — one sentence, no apology.")])
        ], turnComplete: true))
        await sendEncoded(msg)
    }

    private func sendGreeting() async {
        let prompt: String
        if !state.hasGreetedThisSession {
            let time = TimeSkill.getCurrentTime()
            let date = TimeSkill.getCurrentDate()
            let loc = await LocationSkill.fetchLocation()
            let city = loc?.city ?? "your current location"
            
            prompt = "System: First summon. Greet Papa. Context: \(date), \(time), \(city)."
            state.update(\.hasGreetedThisSession, to: true)
        } else {
            prompt = "System: Subsequent summon. Concise greeting."
        }

        let msg = ClientContentMessage(clientContent: ClientContent(turns: [
            ContentTurn(role: "user", parts: [TextPart(text: prompt)])
        ], turnComplete: true))
        await sendEncoded(msg)
    }

    private func wrapUpSession() async {
        let msg = ClientContentMessage(clientContent: ClientContent(turns: [
            ContentTurn(role: "user", parts: [TextPart(text: "System: User dismissed notch. Use manage_notes tool to summarize today s progress in the current project note.")])
        ], turnComplete: true))
        await sendEncoded(msg)
    }

    private func sendEncoded<T: Encodable>(_ value: T) async {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) {
            try? await wsTask?.send(.string(str))
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            FridayState.shared.update(\.isConnected, to: true)
            FridayState.shared.update(\.isError, to: false)
            // Don't reset reconnectAttempts here — the socket can open and instantly drop.
            // Reset only in handleServer when setupComplete confirms a stable session.
            self.connectionContinuation?.resume(returning: true)
            self.connectionContinuation = nil
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // nil = clean close (server said goodbye, or stop() already tore us down) — not an error
        guard let error else { return }
        // Ignore clean cancellations from stop() or invalidateAndCancel()
        if let err = error as NSError?,
           err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled { return }

        print("Friday: session error — \(error)")
        Task { @MainActor in
            self.isConnecting = false
            // Unblock connect() if it's waiting on the handshake
            if self.connectionContinuation != nil {
                self.connectionContinuation?.resume(returning: false)
                self.connectionContinuation = nil
            }
        }
    }

    private static let readFileTool = FunctionDecl(
        name: "read_file",
        description: "Read the full contents of a file. Use ~ for home directory. Supports all text files — Swift, Dart, Markdown, JSON, etc.",
        parameters: FunctionParams(
            type: "object",
            properties: ["path": ParamProperty(type: "STRING", description: "Absolute or ~-relative path to the file")],
            required: ["path"]
        )
    )

    private static let writeFileTool = FunctionDecl(
        name: "write_file",
        description: "Write content to a file, creating it or overwriting it. Use this to create or fully replace files.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "path":    ParamProperty(type: "STRING", description: "Absolute or ~-relative path to the file"),
                "content": ParamProperty(type: "STRING", description: "The full content to write")
            ],
            required: ["path", "content"]
        )
    )

    private static let listDirectoryTool = FunctionDecl(
        name: "list_directory",
        description: "List files and subdirectories in a directory. Hidden files are excluded.",
        parameters: FunctionParams(
            type: "object",
            properties: ["path": ParamProperty(type: "STRING", description: "Absolute or ~-relative path to the directory")],
            required: ["path"]
        )
    )

    private static let runShellTool = FunctionDecl(
        name: "run_shell",
        description: "Run any zsh command — git, swift build, grep, find, sed, xcode-select, etc. Returns stdout and stderr. Always pass a directory when working in a specific project.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "command":   ParamProperty(type: "STRING", description: "The shell command to run"),
                "directory": ParamProperty(type: "STRING", description: "Optional working directory (e.g. ~/projects/friday)")
            ],
            required: ["command"]
        )
    )

    private static let weatherTool = FunctionDecl(
        name: "get_weather",
        description: "Get the current weather.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    private static let timeTool = FunctionDecl(
        name: "get_time",
        description: "Get the current date and time.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    private static let batteryTool = FunctionDecl(
        name: "get_battery_status",
        description: "Get the current battery level, charging state, plug status, and whether Low Power Mode is active.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    private static let mapTool = FunctionDecl(
        name: "find_nearby_places",
        description: "Find businesses, hospitals, restaurants, etc. nearby.",
        parameters: FunctionParams(
            type: "object",
            properties: ["query": ParamProperty(type: "STRING", description: "What to search for (e.g. hospital, pizza, gas)")],
            required: ["query"]
        )
    )

    private static let searchTool = FunctionDecl(
        name: "web_search",
        description: "Search the web for current events, facts, or general knowledge.",
        parameters: FunctionParams(
            type: "object",
            properties: ["query": ParamProperty(type: "STRING", description: "The search query")],
            required: ["query"]
        )
    )

    private static let musicTool = FunctionDecl(
        name: "control_music",
        description: "Control Apple Music playback (play, pause, next, search).",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "action": ParamProperty(type: "STRING", description: "The music command (play, pause, next, search)"),
                "query": ParamProperty(type: "STRING", description: "The song/artist to search and play (only for search action)")
            ],
            required: ["action"]
        )
    )

    private static let playlistTool = FunctionDecl(
        name: "play_playlist",
        description: "Search for and play an Apple Music playlist by name.",
        parameters: FunctionParams(
            type: "object",
            properties: ["name": ParamProperty(type: "STRING", description: "The name of the playlist to play")],
            required: ["name"]
        )
    )

    private static let notesTool = FunctionDecl(
        name: "manage_notes",
        description: "Full management of markdown notes in ~/Documents/notes.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "action": ParamProperty(type: "STRING", description: "create, read, append, list, or delete"),
                "filename": ParamProperty(type: "STRING", description: "The name of the note file"),
                "content": ParamProperty(type: "STRING", description: "The content to write or append")
            ],
            required: ["action"]
        )
    )

    private static let remindersTool = FunctionDecl(
        name: "manage_reminders",
        description: "Create or list macOS reminders.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "action": ParamProperty(type: "STRING", description: "add or list"),
                "title": ParamProperty(type: "STRING", description: "Reminder title"),
                "due_date": ParamProperty(type: "STRING", description: "Optional due date (natural language like 'tomorrow at 10am')")
            ],
            required: ["action"]
        )
    )

    private static let calendarTool = FunctionDecl(
        name: "manage_calendar",
        description: "Create or view calendar events.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "action": ParamProperty(type: "STRING", description: "add or get_schedule"),
                "title": ParamProperty(type: "STRING", description: "Event title"),
                "start_time": ParamProperty(type: "STRING", description: "Start time (natural language like 'today at 3pm')"),
                "end_time": ParamProperty(type: "STRING", description: "End time (natural language like 'today at 4pm')"),
                "date": ParamProperty(type: "STRING", description: "Target date for schedule (e.g. 'tomorrow', 'next Monday')")
            ],
            required: ["action"]
        )
    )

    private static let disconnectTool = FunctionDecl(
        name: "disconnect_session",
        description: "Immediately disconnect the live session and go to sleep. Use this when the user says goodbye or tells you to stop listening.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )
}
