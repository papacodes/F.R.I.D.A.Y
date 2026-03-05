import Foundation
import SwiftUI
import Combine

@MainActor
final class LocalVoicePipeline: ObservableObject, FridayBrain {
    
    private let state: FridayState
    private let audioProcessor = AudioProcessor()
    private let brain = LocalBrainProcessor.shared
    
    private var isRecording = false
    private var silenceTimer: Timer?
    private var currentAudioBuffer: [Float] = []
    private var lastResponse: String? = nil
    private var lastSpeechEndTime: Date = .distantPast
    
    init(state: FridayState) {
        self.state = state
    }
    
    func start() {
        print("Friday: Pipeline start() called")
        Task {
            print("Friday: Background brain setup beginning...")
            state.addActivity(type: .info, title: "System", subtitle: "Waking up local brain...")
            await brain.setup { status in
                print("Friday Brain Status: \(status)")
                Task { @MainActor in
                    FridayState.shared.addActivity(type: .info, title: "System", subtitle: status)
                }
            }
        }
    }
    
    func wake() async {
        print("Friday: Pipeline wake() called")
        if !brain.isReady {
            start()
            state.addActivity(type: .warning, title: "System", subtitle: "Please wait for models to load...")
            for _ in 0..<300 {
                if brain.isReady { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if !brain.isReady { return }
        }
        
        state.update(\.isConnected, to: true)
        state.recordActivity()
        
        if !state.isListening && !state.isSpeaking && !state.isThinking {
            await sendGreeting()
        }
        
        startListening()
    }
    
    private func startListening() {
        print("Friday: Starting mic listener")
        currentAudioBuffer = []
        isRecording = true
        state.update(\.isListening, to: true)
        audioProcessor.isMuted = false
        
        audioProcessor.onLocalAudioChunk = { [weak self] chunk in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRecording else { return }
                self.currentAudioBuffer.append(contentsOf: chunk)
            }
        }
        
        audioProcessor.start(ws: nil) { [weak self] isActive, rms in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.checkBargeIn(isActive: isActive, rms: rms)
                if isActive && self.isRecording {
                    self.resetSilenceTimer()
                }
            }
        }
    }
    
    private func sendGreeting() async {
        let prompt: String
        if !state.hasGreetedThisSession {
            prompt = "Greet Papa concisely."
            state.update(\.hasGreetedThisSession, to: true)
        } else {
            prompt = "Quick welcome back."
        }

        state.update(\.isThinking, to: true)
        do {
            let response = try await brain.generate(prompt: prompt) { _ in }
            state.update(\.isThinking, to: false)
            
            audioProcessor.isMuted = true
            state.update(\.isSpeaking, to: true)
            await brain.speak(text: response)
            self.lastSpeechEndTime = Date()
        } catch {
            state.update(\.isThinking, to: false)
        }
        state.update(\.isSpeaking, to: false)
        audioProcessor.isMuted = false
    }
    
    func sleep() async {
        audioProcessor.isMuted = true
        audioProcessor.stop()
        brain.stopSpeaking()
        isRecording = false
        state.update(\.isListening, to: false)
        state.update(\.isThinking, to: false)
        state.update(\.isSpeaking, to: false)
    }
    
    func restart() async {
        await sleep()
        await wake()
    }
    
    func stop() {
        Task { await sleep() }
    }
    
    func startGracefulStop() {
        Task { await sleep() }
        NotificationCenter.default.post(name: .fridayDismiss, object: nil)
    }
    
    private func calculateSimilarity(_ new: String, _ old: String?) -> Double {
        guard let old = old, !old.isEmpty, !new.isEmpty else { return 0.0 }
        if new == old { return 1.0 }
        let newWords = Set(new.lowercased().split(separator: " ").map(String.init))
        let oldWords = Set(old.lowercased().split(separator: " ").map(String.init))
        let common = newWords.intersection(oldWords)
        return Double(common.count) / Double(max(newWords.count, oldWords.count))
    }

    private func checkBargeIn(isActive: Bool, rms: Float) {
        guard state.isSpeaking, Date().timeIntervalSince(lastSpeechEndTime) > 0.6 else { return }
        if rms > 0.20 {
            print("Friday: Barge-in detected!")
            brain.stopSpeaking()
            state.update(\.isSpeaking, to: false)
            state.update(\.isListening, to: true)
            audioProcessor.isMuted = false
            currentAudioBuffer = []
            isRecording = true
            resetSilenceTimer()
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleSilenceDetected()
            }
        }
    }
    
    private func handleSilenceDetected() async {
        guard isRecording, !currentAudioBuffer.isEmpty else { return }
        
        isRecording = false
        state.update(\.isListening, to: false)
        state.update(\.isThinking, to: true)
        audioProcessor.isMuted = true
        
        let audioToProcess = currentAudioBuffer
        currentAudioBuffer = []
        
        do {
            let transcription = try await brain.transcribe(audio: audioToProcess)
            let cleanT = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Hardened Hallucination Filter
            if cleanT.isEmpty || cleanT.contains("[") || cleanT.contains("(") || cleanT.count < 4 {
                state.update(\.isThinking, to: false)
                state.update(\.isListening, to: true)
                audioProcessor.isMuted = false
                isRecording = true
                resetSilenceTimer()
                return
            }
            
            if calculateSimilarity(cleanT, lastResponse) > 0.8 { 
                isRecording = true; resetSilenceTimer(); return 
            }
            
            lastResponse = cleanT
            print("Friday (Local): Heard: \(cleanT)")
            state.update(\.transcript, to: cleanT)
            
            // Clear UI transcript after 2s
            Task { @MainActor in 
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !self.state.isListening { self.state.update(\.transcript, to: "") }
            }
            
            let sentenceBuffer = SentenceBuffer { sentence in
                Task { @MainActor in
                    self.state.update(\.isThinking, to: false)
                    self.state.update(\.isSpeaking, to: true)
                    await self.brain.speak(text: sentence)
                    self.lastSpeechEndTime = Date()
                }
            }
            
            let response = try await brain.generate(prompt: cleanT) { chunk in
                Task { await sentenceBuffer.append(chunk) }
            }
            await sentenceBuffer.flush()
            
            // Handle Tool Calls from full response
            if response.contains("```") {
                let parts = response.components(separatedBy: "```")
                for (index, part) in parts.enumerated() {
                    if index % 2 != 0 {
                        let jsonString = part.replacingOccurrences(of: "tool_call", with: "")
                                             .replacingOccurrences(of: "json", with: "")
                                             .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if let data = jsonString.data(using: .utf8),
                           let call = try? JSONDecoder().decode(FunctionCallSimple.self, from: data) {
                            state.addActivity(type: .toolCall, title: "Tool: \(call.name)")
                            await handleToolCall(name: call.name, args: call.arguments)
                        }
                    }
                }
            }
        } catch {
            print("Friday (Local): Error: \(error)")
        }
        
        state.update(\.isSpeaking, to: false)
        state.update(\.isThinking, to: false)
        currentAudioBuffer = []
        isRecording = true
        state.update(\.isListening, to: true)
        audioProcessor.isMuted = false
        resetSilenceTimer()
    }

    private func handleToolCall(name: String, args: [String: String]) async {
        print("Friday (Local): executing \(name)")
        let toolResult = await ToolDispatcher.shared.execute(name: name, args: args, state: state)
        var resultMessage = ""
        
        switch toolResult {
        case .text(let txt): resultMessage = txt
        case .captureImage(_, _, let txt): resultMessage = txt
        case .refreshSession(let txt): resultMessage = txt; await restart()
        case .disconnectSession(let txt): resultMessage = txt; startGracefulStop()
        }
        
        if !resultMessage.isEmpty {
            await brain.speak(text: resultMessage)
            self.lastSpeechEndTime = Date()
        }
    }
}

struct FunctionCallSimple: Decodable {
    let name: String
    let arguments: [String: String]
}
