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
        state.update(\.isThinking, to: false)
        state.update(\.isSpeaking, to: false)
        state.update(\.isListening, to: false)
        state.update(\.isError, to: false)
        state.update(\.volume, to: 0.0)
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
        
        state.update(\.isListening, to: false)
        state.update(\.isThinking, to: false)
        state.update(\.isSpeaking, to: false)
        state.update(\.volume, to: 0.0)
    }

    private func connect() async {
        guard !isConnecting else { return }
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

        await withCheckedContinuation { cont in
            self.connectionContinuation = cont
        }
        self.connectionContinuation = nil

        await sendSetup()
        Task { await receiveLoop() }
        isConnecting = false
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
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if wsTask != nil { await connect() }
        }
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
                audioProcessor.start(ws: wsTask) { [weak self] active, rms in
                    DispatchQueue.main.async { 
                        self?.state.update(\.isListening, to: active)
                        if active { self?.state.update(\.volume, to: rms) }
                        else if self?.state.isSpeaking == false { self?.state.update(\.volume, to: 0.0) }
                    }
                }
                audioProcessor.isMuted = false
                await sendGreeting()
            }

            if let content = msg.serverContent {
                if let turn = content.modelTurn {
                    for part in turn.parts {
                        if let inline = part.inlineData, let audioData = Data(base64Encoded: inline.data) {
                            if !state.isSpeaking {
                                state.update(\.isSpeaking, to: true)
                                audioProcessor.isMuted = true
                            }
                            playPCMChunk(audioData)
                        }
                    }
                }
                if let t = content.outputTranscription { state.update(\.transcript, to: t.text) }
                if content.turnComplete == true { 
                    self.state.update(\.isSpeaking, to: false)
                    self.audioProcessor.isMuted = false 
                    self.state.update(\.volume, to: 0.0)
                }
                if content.interrupted == true {
                    playerNode.stop(); playerNode.play()
                    state.update(\.isSpeaking, to: false)
                    audioProcessor.isMuted = false
                    state.update(\.volume, to: 0.0)
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
        
        var sum: Float = 0
        data.withUnsafeBytes { raw in
            let int16s = raw.bindMemory(to: Int16.self)
            for i in 0..<frameCount { 
                let s = Float(int16s[i]) / 32768.0
                floats[i] = s
                sum += s * s
            }
        }
        
        // Update volume from output
        let rms = sqrt(sum / Float(max(frameCount, 1)))
        state.update(\.volume, to: rms)
        
        playerNode.scheduleBuffer(buffer)
    }

    private func handleToolCall(_ call: FunctionCall) async {
        state.update(\.isThinking, to: true)
        var result = "Task complete."
        if call.name == "execute_dev_task", let prompt = call.args["prompt"] {
            result = (try? await devBrain.ask(prompt)) ?? "Error running task."
        }
        state.update(\.isThinking, to: false)
        let response = ToolResponseMessage(toolResponse: ToolResponseBody(functionResponses: [
            FunctionResponseItem(id: call.id, name: call.name, response: ["output": result])
        ]))
        await sendEncoded(response)
    }

    private func sendGreeting() async {
        let msg = ClientContentMessage(clientContent: ClientContent(turns: [
            ContentTurn(role: "user", parts: [TextPart(text: "System: You are now active. Greet Papa.")])
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
        Task { @MainActor in self.connectionContinuation?.resume() }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        Task { @MainActor in 
            FridayState.shared.update(\.isError, to: true)
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
