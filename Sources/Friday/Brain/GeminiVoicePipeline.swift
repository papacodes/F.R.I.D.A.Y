@preconcurrency import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class GeminiVoicePipeline: NSObject, URLSessionWebSocketDelegate {

    private let state: FridayState
    private let audioProcessor = AudioProcessor()
    /// Per-project ClaudeProcess instances. Keyed by project path (or "default" for path-less tasks).
    /// Each instance maintains its own session continuity, allowing concurrent tasks across projects.
    private var claudeByProject: [String: ClaudeProcess] = [:]

    private var wsTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    /// Resumed with `true` on open, `false` on handshake failure — prevents connect() hanging forever.
    private var connectionContinuation: CheckedContinuation<Bool, Never>?
    private var isConnecting = false
    private var isReconnecting = false
    private var reconnectAttempts = 0
    /// Set before any intentional disconnect — prevents receiveLoop from triggering reconnect.
    private var intentionalStop = false

    // Audio state watchdog — detects stuck isSpeaking/isThinking after engine failures or missed turnComplete.
    private var lastAudioTime = Date.distantPast
    private var stateWatchdog: Task<Void, Never>?
    /// Debounces isThinking=false across back-to-back tool calls.
    /// Without this, the brief gap between sequential tool calls flashes the orb back to idle.
    private var thinkingClearTask: Task<Void, Never>?

    // Each receiveLoop captures its own ID at launch. When refreshSession invalidates the socket,
    // it stamps a new ID — stale loops see the mismatch and exit without triggering reconnect.
    private var receiveLoopId = UUID()

    // Set by refreshSession() so setupComplete knows to send a greeting after the clean reconnect.
    private var pendingRefreshGreeting = false

    // Session health — proactive context limit awareness.
    // Gemini Live sessions drop at ~15 min or after heavy context use (long tool results).
    // We warn at 10 min or 20 turns and offer a graceful refresh.
    private var sessionStartTime: Date?
    private var turnCount = 0
    private var hasWarnedAboutContext = false
    private let sessionWarnMinutes: TimeInterval = 10 * 60
    private let sessionWarnTurns = 15

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
        stateWatchdog?.cancel()
        stateWatchdog = nil
        isAudioSetup = false   // reset so setupOutputAudio() re-runs on next connect()
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

        // Hard cap — after 5 failed attempts give up rather than hammering the API.
        // Rapid reconnect storms can trigger Google rate limits that block subsequent sessions.
        guard reconnectAttempts <= 5 else {
            print("Friday: reconnect limit reached — giving up after 5 attempts")
            state.update(\.isError, to: true)
            wsTask = nil
            return
        }

        // Start at 3s (not 1s) to reduce rate-limit risk from rapid storm reconnects.
        // Cap at 60s so we don't wait forever when the API is temporarily unavailable.
        let delay = min(3.0 * pow(2.0, Double(reconnectAttempts - 1)), 60.0) // 3, 6, 12, 24, 48…
        print("Friday: reconnect attempt \(reconnectAttempts) in \(Int(delay))s")
        state.update(\.isConnected, to: false)
        state.update(\.isError, to: true)
        // Clear stuck visual states — dropped connection means nothing is playing or thinking
        state.update(\.isSpeaking, to: false)
        state.update(\.isThinking, to: false)
        state.update(\.isListening, to: false)
        state.update(\.volume, to: 0.0)
        audioProcessor.isMuted = false

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
        You are Friday, Papa's macOS AI assistant in his MacBook notch. Be concise, natural, direct — no filler.

        DEV: Use execute_dev_task for code work — always pass project_path, scope to one specific task. Use read_file/write_file for notes only. Use run_shell for grep/find one-liners. Never list or read entire project directories through file tools — use execute_dev_task with a specific question instead.
        KNOWLEDGE: Use retrieve_knowledge instead of read_file whenever looking up past decisions, project context, session history, standards, or anything stored in notes. retrieve_knowledge is faster, token-efficient, and returns only the relevant excerpt.
        Before execute_dev_task, speak a brief line ("On it", "Let me check"). When it returns, summarise in 1-2 sentences.

        Code: ~/projects/ — Notes: ~/Documents/notes/
        Project paths: friday → ~/projects/friday | oats → ~/projects/telesure/oats/
        Call disconnect_session when Papa says goodbye. Call refresh_session only when Papa explicitly asks — always save notes with manage_notes first.

        UI: Use get_ui_state before acting. Use control_ui to expand/collapse/switch tabs/dismiss tasks. Switch to the relevant tab when Papa asks about music, calendar, reminders, or notes. If a skill fails, say so and suggest the relevant app.
        \(knowledgeBase)
        """

        let msg = SetupMessage(
            setup: SetupPayload(
                model: "models/gemini-2.5-flash-native-audio-preview-12-2025",
                generationConfig: GenerationConfig(
                    responseModalities: ["AUDIO"],
                    speechConfig: nil,
                    inputAudioTranscription: nil,
                    outputAudioTranscription: nil
                ),
                systemInstruction: SystemInstruction(parts: [TextPart(text: instructions)]),
                tools: [ToolsList(functionDeclarations: [
                    Self.ragTool, Self.executeDevTaskTool,
                    Self.readFileTool, Self.writeFileTool, Self.listDirectoryTool, Self.runShellTool,
                    Self.weatherTool, Self.timeTool, Self.batteryTool,
                    Self.mapTool, Self.searchTool, Self.musicTool,
                    Self.playlistTool, Self.notesTool, Self.remindersTool,
                    Self.calendarTool, Self.disconnectTool, Self.refreshSessionTool,
                    Self.getUiStateTool, Self.controlUiTool
                ])]
            )
        )
        await sendEncoded(msg)
    }

    private func receiveLoop() async {
        let myId = receiveLoopId  // stale loops see ID mismatch and bail cleanly
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
                if myId == receiveLoopId { print("Friday: WebSocket receive error — \(error)") }
                break
            }
        }

        // Reconnect only if this is the current loop (not a stale one from a prior session)
        if myId == receiveLoopId && !isConnecting && !intentionalStop { await reconnect() }
    }

    private func handleServer(_ data: Data) async {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let msg = try decoder.decode(ServerMessage.self, from: data)
            
            if let err = msg.error {
                print("Friday: Server error — [\(err.code ?? 0)] \(err.status ?? "UNKNOWN"): \(err.message ?? "No message")")
                state.update(\.isError, to: true)
                return
            }

            if msg.setupComplete != nil {
                // Stable session confirmed — check before resetting so we know if this is a reconnect
                let wasReconnect = reconnectAttempts > 0
                reconnectAttempts = 0
                sessionStartTime = Date()
                turnCount = 0
                hasWarnedAboutContext = false
                state.update(\.isContextWarning, to: false)
                audioProcessor.start(ws: wsTask) { [weak self] active, rms in
                    DispatchQueue.main.async {
                        self?.state.update(\.isListening, to: active)
                        if active { self?.state.update(\.volume, to: rms) }
                        else if self?.state.isSpeaking == false { self?.state.update(\.volume, to: 0.0) }
                    }
                }
                if pendingRefreshGreeting {
                    pendingRefreshGreeting = false
                    Task { await self.sendRefreshGreeting() }
                } else if wasReconnect {
                    Task { await self.sendReconnectNotice() }
                }
            }

            if let content = msg.serverContent {
                if content.turnComplete == true {
                    turnCount += 1
                    state.update(\.volume, to: 0.0)
                    // Delay isSpeaking clear — playerNode still has buffered audio queued when
                    // turnComplete arrives. Clearing immediately causes the orb to snap back to
                    // idle while audio is still audibly playing. 1.2s covers typical buffer drain.
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        self?.state.update(\.isSpeaking, to: false)
                    }
                    checkSessionHealth()
                    // Delay mic unmute — playerNode still has buffered audio queued after turnComplete arrives.
                    // Unmuting immediately causes the mic to pick up playback tail and falsely trigger VAD,
                    // which interrupts Friday mid-sentence. 600ms gives the buffer time to drain.
                    let proc = audioProcessor
                    Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        proc.isMuted = false
                    }
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
                for call in toolCall.functionCalls {
                    Task { await handleToolCall(call) }
                }
            }
        } catch {
            // Most failures here are binary audio frames that aren't JSON — expected, ignore.
            // Log only if the data looks like it should have been JSON (starts with '{').
            if data.first == UInt8(ascii: "{") {
                print("Friday: failed to decode server message — \(error)")
            }
        }
    }

    private var isAudioSetup = false
    private func setupOutputAudio() {
        guard !isAudioSetup else { return }
        isAudioSetup = true

        outputEngine.attach(playerNode)
        outputEngine.connect(playerNode, to: outputEngine.mainMixerNode, format: playbackFormat)
        outputEngine.prepare()
        try? outputEngine.start()
        playerNode.play()
        startStateWatchdog()

        // Restart engine automatically when macOS changes audio routing (headphones in/out, sleep, etc.)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: outputEngine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recoverAudioEngine() }
        }
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
        lastAudioTime = Date()

        // Restart engine if macOS interrupted it (route change, sleep, long tool call, etc.)
        if !outputEngine.isRunning {
            do { try outputEngine.start() } catch {
                print("Friday: audio engine restart failed — \(error). Attempting full recovery.")
                recoverAudioEngine()
                return  // drop this chunk — next chunk will arrive if Gemini is still speaking
            }
        }
        if !playerNode.isPlaying { playerNode.play() }

        playerNode.scheduleBuffer(buffer)
    }

    private func handleToolCall(_ call: FunctionCall) async {
        print("Friday: tool call → \(call.name) args=\(call.args.keys.sorted().joined(separator: ","))")
        // Cancel any pending clear — a new tool call is starting, keep isThinking true.
        thinkingClearTask?.cancel()
        state.update(\.isThinking, to: true)
        var result = "Task complete."
        
        switch call.name {
        case "read_file":
            if let path = call.args["path"] {
                state.beginDevTask()
                result = FileSystemSkill.readFile(path: path)
                state.endDevTask()
            }

        case "write_file":
            if let path = call.args["path"], let content = call.args["content"] {
                state.beginDevTask()
                result = FileSystemSkill.writeFile(path: path, content: content)
                state.endDevTask()
            }

        case "list_directory":
            if let path = call.args["path"] {
                result = FileSystemSkill.listDirectory(path: path)
            }

        case "run_shell":
            if let command = call.args["command"] {
                state.beginDevTask()
                result = await ShellSkill.run(command, directory: call.args["directory"])
                state.endDevTask()
            }

        case "get_weather":
            result = await WeatherSkill.fetchWeather()
        case "get_time":
            result = "It is currently \(TimeSkill.getCurrentTime()) on \(TimeSkill.getCurrentDate())."
        case "get_battery_status":
            result = BatterySkill.getBatteryStatus()
        case "find_nearby_places":
            if let q = call.args["query"] { result = await MapsSkill.findNearby(q) }
        case "retrieve_knowledge":
            if let q = call.args["query"] { result = await RAGSkill.retrieve(query: q) }

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
        case "execute_dev_task":
            guard let task = call.args["task"] else {
                result = "[TASK_ERROR] execute_dev_task called without a task argument. Args received: \(call.args)"
                print("Friday: execute_dev_task missing 'task' arg — args=\(call.args)")
                break
            }
            let projectPath = call.args["project_path"]
            let projectKey = projectPath ?? "default"
            let taskLabel = projectPath
                .map { URL(fileURLWithPath: $0.replacingOccurrences(of: "~", with: "")).lastPathComponent }
                ?? "task"
            let claude = claudeForProject(projectKey)

            state.startTask(id: projectKey, label: taskLabel)
            state.addActivity(type: .info, title: "Claude Code", subtitle: task)

            let maxTurns = call.args["max_turns"].flatMap { Int($0) } ?? 15
            do {
                result = try await claude.ask(task, directory: projectPath, maxTurns: maxTurns) { progress in
                    Task { @MainActor in
                        FridayState.shared.updateTask(id: projectKey, step: progress)
                    }
                }
                // [TASK_DONE] is the source of truth — Claude appends it only when fully complete.
                // If absent, the process exited without confirming (turn limit hit, silent fail, etc.).
                if result.contains("[TASK_DONE]") {
                    result = result.replacingOccurrences(of: "[TASK_DONE]", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    state.completeTask(id: projectKey)
                } else {
                    state.errorTask(id: projectKey, message: "Ended without confirmation — may be incomplete")
                }
                state.update(\.transcript, to: "")
                // Truncate before sending back — long results burn context fast and cause disconnects.
                // Keep head (context) + tail (spoken summary the preamble asks Claude to put last).
                let limit = 1500
                if result.count > limit {
                    let head = String(result.prefix(400))
                    let tail = String(result.suffix(1000))
                    result = "\(head)\n…[truncated]\n\(tail)"
                }
            } catch {
                state.errorTask(id: projectKey, message: error.localizedDescription)
                result = "Claude Code failed: \(error.localizedDescription)"
            }

        case "control_ui":
            if let action = call.args["action"] {
                switch action {
                case "expand":
                    if state.displayState == .open {
                        result = "Already fully expanded."
                    } else {
                        NotificationCenter.default.post(name: .fridayExpand, object: nil)
                        result = "Expanded."
                    }
                case "collapse":
                    if state.displayState == .miniExpanded {
                        result = "Already in compact view."
                    } else {
                        NotificationCenter.default.post(name: .fridayCollapse, object: nil)
                        result = "Collapsed."
                    }
                case "switch_tab":
                    let tab = call.args["tab"] ?? "home"
                    switch tab {
                    case "music":     state.update(\.activeTab, to: .music)
                    case "calendar":  state.update(\.activeTab, to: .calendar)
                    case "reminders": state.update(\.activeTab, to: .reminders)
                    case "notes":     state.update(\.activeTab, to: .notes)
                    default:          state.update(\.activeTab, to: .home)
                    }
                    if state.displayState != .open {
                        NotificationCenter.default.post(name: .fridayExpand, object: nil)
                    }
                    result = "Switched to \(tab) tab."
                case "dismiss_task":
                    if let taskId = call.args["task_id"] {
                        state.dismissTask(id: taskId)
                        result = "Task '\(taskId)' dismissed."
                    } else {
                        state.dismissCompletedTasks()
                        result = "Completed tasks cleared."
                    }
                default:
                    result = "Unknown UI action: \(action)"
                }
            }

        case "get_ui_state":
            let panelDesc: String
            switch state.displayState {
            case .open:         panelDesc = "fully expanded"
            case .miniExpanded: panelDesc = "compact (mini-expanded)"
            case .mini:         panelDesc = "mini pill"
            case .dismissed:    panelDesc = "dormant"
            }
            let taskDesc = state.activeTasks.isEmpty ? "none" :
                state.activeTasks.map { "\($0.label) (\($0.status == .running ? "running" : $0.status == .done ? "done" : "error"))" }
                    .joined(separator: ", ")
            result = "Panel: \(panelDesc). Tab: \(state.activeTab.label). Tasks: \(taskDesc)."

        case "refresh_session":
            // Save notes, then reconnect cleanly — panel stays up, context resets
            result = "Reconnecting now. I'll be right back."
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.refreshSession()
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

        let response = ToolResponseMessage(toolResponse: ToolResponseBody(functionResponses: [
            FunctionResponseItem(id: call.id, name: call.name, response: ["output": result])
        ]))
        await sendEncoded(response)
        turnCount += 1
        checkSessionHealth()

        // Debounced clear — wait 400ms before dropping isThinking.
        // If another tool call starts within that window, it cancels this task and
        // isThinking never drops, preventing the orb from flashing idle between calls.
        thinkingClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.state.update(\.isThinking, to: false)
        }
    }

    /// Periodic watchdog that clears stuck isSpeaking after 4s of no audio chunks.
    /// Guards against: engine dying mid-stream, missed turnComplete, WebSocket disconnect mid-speech.
    private func startStateWatchdog() {
        stateWatchdog?.cancel()
        stateWatchdog = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                if self.state.isSpeaking && Date().timeIntervalSince(self.lastAudioTime) > 8 {
                    print("Friday: watchdog — clearing stuck isSpeaking (no audio for 8s)")
                    self.state.update(\.isSpeaking, to: false)
                    self.audioProcessor.isMuted = false
                    self.state.update(\.volume, to: 0.0)
                }
            }
        }
    }

    /// Full audio engine recovery — called after configurationChange or failed restart.
    private func recoverAudioEngine() {
        print("Friday: recovering audio engine")
        playerNode.stop()
        outputEngine.stop()
        do {
            try outputEngine.start()
            playerNode.play()
            print("Friday: audio engine recovered")
        } catch {
            print("Friday: audio engine recovery failed — \(error)")
        }
    }

    private func sendReconnectNotice() async {
        // Fresh session after a drop — session context was lost, keep it honest and brief
        let msg = ClientContentMessage(clientContent: ClientContent(turns: [
            ContentTurn(role: "user", parts: [TextPart(text: "System: Connection was interrupted and just restored. Tell Papa you're back — one sentence, no apology.")])
        ], turnComplete: true))
        await sendEncoded(msg)
    }

    private func sendRefreshGreeting() async {
        // Session was intentionally refreshed (context limit) — acknowledge cleanly and resume
        let msg = ClientContentMessage(clientContent: ClientContent(turns: [
            ContentTurn(role: "user", parts: [TextPart(text: "System: Session was refreshed for a clean context. Tell Papa you're back and ready — one sentence.")])
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
        // Skip if session had no meaningful activity — avoids burning a turn on empty open/close cycles.
        guard turnCount > 2 else { return }
        let msg = ClientContentMessage(clientContent: ClientContent(turns: [
            ContentTurn(role: "user", parts: [TextPart(text: "System: User dismissed notch. Use manage_notes tool to summarize today's progress in the current project note.")])
        ], turnComplete: true))
        await sendEncoded(msg)
    }

    /// Fires after each turn to warn Papa if we're approaching Gemini's session limits.
    /// Injects a system prompt — Friday handles the warning and can call refresh_session.
    private func checkSessionHealth() {
        guard !hasWarnedAboutContext, !intentionalStop else { return }
        let elapsed = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
        guard elapsed >= sessionWarnMinutes || turnCount >= sessionWarnTurns else { return }
        hasWarnedAboutContext = true
        state.update(\.isContextWarning, to: true)
        print("Friday: nearing context limit (\(turnCount) turns, \(Int(elapsed/60))m). Warning Papa.")

        let mins = Int(elapsed / 60)
        // Passive warning only — do NOT suggest or offer a reconnect. Papa decides when to reconnect.
        // Gemini should NOT call refresh_session proactively; only when Papa explicitly asks.
        let prompt = "System: \(mins)min / \(turnCount) turns in — context window is getting full. Mention this briefly to Papa in one sentence. Do not offer to reconnect or suggest refresh_session."
        Task { await sendSystemMessage(prompt) }
    }

    /// Injects a system-only message into the conversation without user attribution.
    private func sendSystemMessage(_ text: String) async {
        let msg = ClientContentMessage(clientContent: ClientContent(turns: [
            ContentTurn(role: "user", parts: [TextPart(text: text)])
        ], turnComplete: true))
        await sendEncoded(msg)
    }

    /// Disconnects and immediately reconnects with a clean context.
    /// Unlike stop()/intentionalStop, this does not dismiss the panel — Friday stays visible.
    private func refreshSession() async {
        print("Friday: refreshing session — clean reconnect")
        playerNode.stop()

        // Stamp new loop ID BEFORE cancelling — stale receiveLoop sees mismatch and won't reconnect.
        // Also set intentionalStop so any still-running loop exits the reconnect guard cleanly.
        receiveLoopId = UUID()
        intentionalStop = true

        let stale = urlSession
        wsTask = nil
        audioProcessor.wsTask = nil
        urlSession = nil
        stale?.invalidateAndCancel()
        isConnecting = false
        isReconnecting = false
        reconnectAttempts = 0

        // Reset session metrics so health check starts fresh
        sessionStartTime = nil
        turnCount = 0
        hasWarnedAboutContext = false
        state.update(\.isContextWarning, to: false)
        isAudioSetup = false   // reset so setupOutputAudio() re-runs on reconnect

        // Drop all ClaudeProcess sessions — fresh Gemini context should pair with fresh Claude context.
        // New instances are created on demand when the next execute_dev_task arrives.
        claudeByProject.removeAll()

        state.update(\.isConnected, to: false)
        state.update(\.isSpeaking, to: false)
        state.update(\.isThinking, to: false)

        // Ensure mic is live after reconnect — it may have been muted while Gemini was speaking.
        audioProcessor.isMuted = false
        pendingRefreshGreeting = true

        // Brief pause so the stale session's delegate callbacks fire before we open the new one.
        // Without this, the delegate's didCompleteWithError can reset isConnecting on the new session.
        try? await Task.sleep(nanoseconds: 300_000_000)

        intentionalStop = false
        await connect()
    }

    /// Returns the ClaudeProcess bound to a project key, creating one on first use.
    /// Isolation: called on @MainActor — dictionary access is safe.
    private func claudeForProject(_ key: String) -> ClaudeProcess {
        if let existing = claudeByProject[key] { return existing }
        let instance = ClaudeProcess()
        claudeByProject[key] = instance
        return instance
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
            // Ignore callbacks from stale sessions (e.g. after refreshSession tears down the old one)
            guard session === self.urlSession else { return }
            FridayState.shared.update(\.isConnected, to: true)
            FridayState.shared.update(\.isError, to: false)
            self.connectionContinuation?.resume(returning: true)
            self.connectionContinuation = nil
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "no reason"
        print("Friday: WebSocket closed — code=\(closeCode.rawValue) reason=\(reasonStr)")
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        if let err = error as NSError?,
           err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled { return }

        Task { @MainActor in
            // Ignore errors from stale sessions — they must not interfere with the new connection
            guard session === self.urlSession else { return }
            print("Friday: session error — \(error)")
            self.isConnecting = false
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

    private static let executeDevTaskTool = FunctionDecl(
        name: "execute_dev_task",
        description: "Execute a development task using Claude Code. Use for code analysis, making changes, debugging, or any task requiring understanding of a code project. Always pass project_path. Keep the task tightly scoped — one specific question or change, not 'look at everything'. Pass max_turns=5 for read-only questions, 15 for changes.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "task":         ParamProperty(type: "STRING", description: "The specific task or question for Claude Code. Be precise and scoped."),
                "project_path": ParamProperty(type: "STRING", description: "Absolute path to the project (e.g. ~/projects/friday, ~/projects/oats). Required for code projects."),
                "max_turns":    ParamProperty(type: "STRING", description: "Turn budget for Claude Code. Pass \"5\" for lookups/reads, \"15\" for edits. Default 15.")
            ],
            required: ["task"]
        )
    )

    private static let ragTool = FunctionDecl(
        name: "retrieve_knowledge",
        description: "Search Papa's notes for relevant information — past decisions, project context, session history, standards, lessons learned. Use this instead of read_file when looking up knowledge from notes. Returns the most relevant excerpts only.",
        parameters: FunctionParams(
            type: "object",
            properties: ["query": ParamProperty(type: "STRING", description: "Natural language description of what you're looking for")],
            required: ["query"]
        )
    )

    private static let disconnectTool = FunctionDecl(
        name: "disconnect_session",
        description: "Immediately disconnect the live session and go to sleep. Use this when the user says goodbye or tells you to stop listening.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    private static let refreshSessionTool = FunctionDecl(
        name: "refresh_session",
        description: "Reconnect with a fresh context window. Call this when approaching session limits or when Papa asks to reconnect. Always save session notes with manage_notes BEFORE calling this.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    private static let getUiStateTool = FunctionDecl(
        name: "get_ui_state",
        description: "Get the current state of the Friday UI — panel size, active tab, running tasks. Call this before taking UI actions so you know what's already showing.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    private static let controlUiTool = FunctionDecl(
        name: "control_ui",
        description: "Control the Friday UI. Use get_ui_state first to know what's already showing before acting.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "action":  ParamProperty(type: "STRING", description: "expand, collapse, switch_tab, or dismiss_task"),
                "tab":     ParamProperty(type: "STRING", description: "For switch_tab: home, music, calendar, reminders, notes"),
                "task_id": ParamProperty(type: "STRING", description: "For dismiss_task: the project key (e.g. 'friday', 'oats'). Omit to dismiss all completed tasks.")
            ],
            required: ["action"]
        )
    )
}
