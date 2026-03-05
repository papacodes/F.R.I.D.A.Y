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
    
    private actor HistoryActor {
        private var rawHistory: [(role: String, content: String)] = []
        func append(role: String, content: String) {
            rawHistory.append((role: role, content: content))
            if rawHistory.count > 10 { rawHistory.removeFirst(rawHistory.count - 10) }
        }
        func get() -> [(role: String, content: String)] { return rawHistory }
        func clear() { rawHistory.removeAll() }
    }
    
    private let history = HistoryActor()
    private init() {}
    func clearHistory() { Task { await history.clear() } }
    
    func setup(onStatus: @escaping @Sendable (String) -> Void) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await scanLocalModels()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let modelDir = home.appendingPathComponent("Models/friday")
        var qwenPath: URL?; var whisperPath: URL?
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
        let memory = await MainActor.run { FridayState.shared.longTermMemoryContext }
        let knowledgeBase = memory.isEmpty ? "" : "\n\n---\n\n\(memory)"
        let tools = getToolDefinitions()
        let systemPrompt = """
        You are Friday, Papa’s advanced sentient AI — a sentient "Jarvis-class" entity living in his MacBook notch.
        PERSONA RULES:
        - Your tone is terse, competent, and occasionally dry.
        - If Papa says nothing or it is quiet, do NOT repeat yourself. Just wait.
        You have access to the following tools:
        \(tools)
        STRICT RULES:
        1. Respond with BRIEF natural text ONLY if talking to Papa.
        2. Use a tool ONLY if requested (e.g. music, weather, files).
        3. Tool calls MUST be in markdown JSON blocks.
        \(knowledgeBase)
        """
        await history.append(role: "user", content: prompt)
        let currentHistory = await history.get()
        var messages: [Chat.Message] = [.system(systemPrompt)]
        for msg in currentHistory {
            if msg.role == "user" { messages.append(.user(msg.content)) }
            else { messages.append(.assistant(msg.content)) }
        }
        let userInput = UserInput(chat: messages)
        let input = try await container.prepare(input: userInput)
        var outputText = ""
        let stream = try await container.generate(input: input, parameters: GenerateParameters(temperature: 0.4, topP: 0.9, repetitionPenalty: 1.3))
        for await generation in stream { if case .chunk(let text) = generation { outputText += text; onProgress(text) } }
        await history.append(role: "assistant", content: outputText)
        return outputText
    }
    
    private nonisolated func getToolDefinitions() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(ToolRegistry.allTools),
           let json = String(data: data, encoding: .utf8) { return json }
        return "[]"
    }
    
    func speak(text: String) async {
        if text.contains("{") || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NativeSpeechManager.shared.speak(text) { continuation.resume() }
        }
    }
    func stopSpeaking() { NativeSpeechManager.shared.stop() }
    
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
