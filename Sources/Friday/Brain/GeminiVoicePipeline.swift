@preconcurrency import AVFoundation
import Foundation

@MainActor
final class GeminiVoicePipeline: NSObject, URLSessionWebSocketDelegate {

    private let state: FridayState
    private let devBrain = ClaudeProcess()
    private let audioProcessor = AudioProcessor()

    private var wsTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var connectionContinuation: CheckedContinuation<Void, Never>?
    private var isConnecting = false

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

    func start() {
        stop()
        state.isThinking = false
        state.isSpeaking = false
        state.isListening = false
        state.isError = false
        Task { await connect() }
    }

    func stop() {
        isConnecting = false
        let task = wsTask
        wsTask = nil
        audioProcessor.wsTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        
        audioProcessor.isMuted = true
        audioProcessor.stop()
        playerNode.stop()
        outputEngine.stop()
        
        state.isListening = false
        state.isThinking = false
        state.isSpeaking = false
    }

    private func connect() async {
        guard !isConnecting else { return }
        guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !apiKey.isEmpty else {
            state.isError = true
            return
        }

        isConnecting = true
        let endpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else { isConnecting = false; return }

        let request = URLRequest(url: url)
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let ws = urlSession!.webSocketTask(with: request)
        ws.resume()
        wsTask = ws
        audioProcessor.wsTask = ws

        setupOutputAudio()

        await withCheckedContinuation { cont in
            self.connectionContinuation = cont
        }
        self.connectionContinuation = nil

        await sendSetup()
        Task { await receiveLoop() }
        isConnecting = false
        print("Friday: Gemini WebSocket open")
    }

    private func sendSetup() async {
        let msg = SetupMessage(
            setup: SetupPayload(
                model: "models/gemini-2.5-flash-native-audio-preview-12-2025",
                generationConfig: GenerationConfig(
                    responseModalities: ["audio"],
                    speechConfig: nil,
                    inputAudioTranscription: nil,
                    outputAudioTranscription: nil
                ),
                systemInstruction: nil,
                tools: nil
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
                @unknown default:
                    break
                }
            } catch {
                if wsTask != nil {
                    print("Friday: WebSocket receive error — \(error)")
                }
                break
            }
        }
        
        if wsTask != nil && !isConnecting {
            print("Friday: Reconnecting in 3s...")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if wsTask != nil { await connect() }
        }
    }

    private func handleServer(_ data: Data) async {
        if let raw = String(data: data, encoding: .utf8) {
            if !raw.contains("inline_data") { 
                print("Friday received: \(raw)") 
            }
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let msg = try decoder.decode(ServerMessage.self, from: data)
            
            if let err = msg.error {
                print("Friday: Gemini API error — \(err.message ?? "no message")")
                state.isError = true
                return
            }

            if msg.setupComplete != nil {
                print("Friday: Gemini ready")
                audioProcessor.start(ws: wsTask) { [weak self] active in
                    DispatchQueue.main.async { self?.state.isListening = active }
                }
                audioProcessor.isMuted = false
                await sendGreeting()
            }

            if let content = msg.serverContent {
                if let turn = content.modelTurn {
                    for part in turn.parts {
                        if let inline = part.inlineData, let audioData = Data(base64Encoded: inline.data) {
                            if !state.isSpeaking {
                                state.isSpeaking = true
                                audioProcessor.isMuted = true
                            }
                            playPCMChunk(audioData)
                        }
                    }
                }
                if let t = content.outputTranscription { state.transcript = t.text }
                if content.turnComplete == true { 
                    self.state.isSpeaking = false
                    self.audioProcessor.isMuted = false 
                }
                if content.interrupted == true {
                    playerNode.stop(); playerNode.play()
                    state.isSpeaking = false
                    audioProcessor.isMuted = false
                }
            }

            if let toolCall = msg.toolCall {
                for call in toolCall.functionCalls {
                    Task { await handleToolCall(call) }
                }
            }
        } catch {
            // Ignore decoding noise
        }
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
        data.withUnsafeBytes { raw in
            let int16s = raw.bindMemory(to: Int16.self)
            for i in 0..<frameCount { floats[i] = Float(int16s[i]) / 32768.0 }
        }
        playerNode.scheduleBuffer(buffer)
    }

    private func handleToolCall(_ call: FunctionCall) async {
        state.isThinking = true
        var result = "Task complete."
        if call.name == "execute_dev_task", let prompt = call.args["prompt"] {
            result = (try? await devBrain.ask(prompt)) ?? "Error running task."
        }
        state.isThinking = false
        let response = ToolResponseMessage(toolResponse: ToolResponseBody(functionResponses: [
            FunctionResponseItem(id: call.id, name: call.name, response: ["output": result])
        ]))
        await sendEncoded(response)
    }

    private func sendGreeting() async {
        let msg = ClientContentMessage(clientContent: ClientContent(turns: [
            ContentTurn(role: "user", parts: [TextPart(text: "System: You are now active. Greet Papa and ask how you can help.")])
        ], turnComplete: true))
        await sendEncoded(msg)
    }

    private func sendEncoded<T: Encodable>(_ value: T) async {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) {
            print("Friday sending: \(str)")
            try? await wsTask?.send(.string(str))
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("Friday: WebSocket connected")
        Task { @MainActor in self.connectionContinuation?.resume() }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error = error {
            print("Friday: WebSocket task completed with error — \(error)")
        }
        Task { @MainActor in 
            FridayState.shared.isError = true
            self.isConnecting = false
        }
    }

    private static let devTaskTool = FunctionDecl(
        name: "execute_dev_task",
        description: "Run a dev task with Claude Code.",
        parameters: FunctionParams(
            type: "object",
            properties: ["prompt": ParamProperty(type: "STRING", description: "The task description")],
            required: ["prompt"]
        )
    )
}
