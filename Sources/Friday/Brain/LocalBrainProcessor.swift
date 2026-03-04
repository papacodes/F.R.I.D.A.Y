import Foundation
import MLXLLM
import MLXLMCommon
import WhisperKit
@preconcurrency import AVFoundation

@MainActor
final class LocalBrainProcessor: ObservableObject {
    static let shared = LocalBrainProcessor()
    
    nonisolated(unsafe) var modelContainer: ModelContainer?
    nonisolated(unsafe) var whisperKit: WhisperKit?
    var isLoading = false
    @Published var isReady = false
    
    // PERSISTENT Speech Engine (Shared to prevent hardware crashes)
    nonisolated(unsafe) let sharedEngine = AVAudioEngine()
    nonisolated(unsafe) private let playerNode = AVAudioPlayerNode()
    private let synthesizer = AVSpeechSynthesizer()
    
    private init() {
        sharedEngine.attach(playerNode)
        sharedEngine.connect(playerNode, to: sharedEngine.mainMixerNode, format: nil)
        try? sharedEngine.start()
    }
    
    func setup(onStatus: @escaping @Sendable (String) -> Void) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        await scanLocalModels()
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let modelDir = home.appendingPathComponent("Models/friday")
        
        var qwenPath: URL?
        var whisperPath: URL?
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil) {
            qwenPath = contents.first { $0.lastPathComponent.lowercased().contains("qwen") }
            whisperPath = contents.first { $0.lastPathComponent.lowercased().contains("whisper") }
        }
        
        do {
            if let path = whisperPath {
                self.whisperKit = try await WhisperKit(modelFolder: path.path)
                onStatus("Whisper ready.")
            }
        } catch { onStatus("Whisper error.") }
        
        do {
            if let path = qwenPath {
                self.modelContainer = try await MLXLMCommon.loadModelContainer(directory: path)
                onStatus("Qwen ready.")
            }
        } catch { onStatus("Qwen error.") }
        
        self.isReady = true
        onStatus("Friday is online.")
    }
    
    nonisolated func transcribe(audio: [Float]) async throws -> String {
        guard let whisper = whisperKit else { return "" }
        let results = try await whisper.transcribe(audioArray: audio)
        return results.map { $0.text }.joined(separator: " ")
    }
    
    nonisolated func generate(prompt: String, onProgress: @escaping @Sendable (String) -> Void) async throws -> String {
        guard let container = modelContainer else { return "" }
        
        let systemPrompt = """
        You are Friday, Papa's advanced sentient AI.
        Tone: Very brief, conversational, and loyal.
        
        STRICT RULES:
        1. Respond with BRIEF natural text only.
        2. NO JSON for greetings.
        3. If using a tool (music, weather, search), output ONLY the tool JSON block.
        """
        
        let userInput = UserInput(chat: [.system(systemPrompt), .user(prompt)])
        let input = try await container.prepare(input: userInput)
        
        var outputText = ""
        let stream = try await container.generate(input: input, parameters: GenerateParameters(temperature: 0.2))
        
        for await generation in stream {
            if case .chunk(let text) = generation {
                outputText += text
                onProgress(text)
            }
        }
        return outputText
    }
    
    func speak(text: String) {
        // Shield: Never speak JSON
        if text.contains("{") || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        
        print("Friday: Speaking natural voice -> \(text)")
        
        // Attempt local API bridge first (highly natural)
        let url = URL(string: "http://127.0.0.1:8880/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": "kokoro", "input": text, "voice": "af_heart", "response_format": "pcm"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                await playPCMData(data)
            } catch {
                // High-quality Siri fallback if API is down
                fallbackSpeak(text)
            }
        }
    }
    
    private func playPCMData(_ data: Data) async {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let sampleSize = MemoryLayout<Float>.size
        let frameCount = UInt32(data.count / sampleSize)
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            if let dest = buffer.floatChannelData?[0] { memcpy(dest, rawBuffer.baseAddress, data.count) }
        }
        await playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        playerNode.play()
    }
    
    private func fallbackSpeak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        // Siri Neural is much better than robotic default
        utterance.voice = voices.first { $0.name.contains("Siri") && $0.quality == .enhanced } 
            ?? voices.first { $0.name.contains("Siri") }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        synthesizer.speak(utterance)
    }
    
    func stopSpeaking() {
        playerNode.stop()
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    private func scanLocalModels() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let modelDir = home.appendingPathComponent("Models/friday")
        guard let contents = try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil) else { return }
        var foundAgents: [BrainAgent] = [BrainAgent(id: "cloud-gemini-2.0", name: "Gemini 2.0 Flash", type: .gemini, isLocal: false)]
        for url in contents where url.lastPathComponent.contains("Qwen") {
            foundAgents.append(BrainAgent(id: "local-\(url.lastPathComponent)", name: url.lastPathComponent.replacingOccurrences(of: "-", with: " "), type: .qwen, isLocal: true))
        }
        await MainActor.run { FridayState.shared.availableAgents = foundAgents }
    }
}
