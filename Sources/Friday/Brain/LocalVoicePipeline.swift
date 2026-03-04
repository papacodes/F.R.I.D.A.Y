import Foundation
import SwiftUI
import Combine

@MainActor
final class LocalVoicePipeline: ObservableObject {
    
    private let state: FridayState
    private let audioProcessor = AudioProcessor()
    private let brain = LocalBrainProcessor.shared
    
    // Voice activity detection
    private var isRecording = false
    private var silenceTimer: Timer?
    private var currentAudioBuffer: [Float] = []
    
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
            print("Friday: Brain not ready, waiting...")
            start()
            state.addActivity(type: .warning, title: "System", subtitle: "Please wait for models to load...")
            for i in 0..<300 {
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
                if isActive {
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
            
            // CRITICAL: Mute mic before speaking
            audioProcessor.isMuted = true
            state.update(\.isSpeaking, to: true)
            brain.speak(text: response)
            
            // Wait for speaking to finish
            try? await Task.sleep(nanoseconds: UInt64(Double(max(response.count, 15)) * 0.08 * 1_000_000_000))
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
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
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
        
        // CRITICAL: Strict muting during processing/speaking
        audioProcessor.isMuted = true
        
        let audioToProcess = currentAudioBuffer
        currentAudioBuffer = []
        
        do {
            let transcription = try await brain.transcribe(audio: audioToProcess)
            print("Friday (Local): Heard: \(transcription)")
            
            if !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.update(\.transcript, to: transcription)
                
                let response = try await brain.generate(prompt: transcription) { _ in }
                
                var textToSpeak = response
                if response.contains("```") {
                    let parts = response.components(separatedBy: "```")
                    var cleanText = ""
                    for (index, part) in parts.enumerated() {
                        if index % 2 == 0 {
                            cleanText += part
                        } else {
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
                    textToSpeak = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                if !textToSpeak.isEmpty {
                    state.update(\.isThinking, to: false)
                    state.update(\.isSpeaking, to: true)
                    brain.speak(text: textToSpeak)
                    try? await Task.sleep(nanoseconds: UInt64(Double(max(textToSpeak.count, 10)) * 0.08 * 1_000_000_000))
                }
            }
        } catch {
            print("Friday (Local): Error: \(error)")
        }
        
        state.update(\.isSpeaking, to: false)
        state.update(\.isThinking, to: false)
        
        // CRITICAL: Only unmute after everything is finished
        isRecording = true
        state.update(\.isListening, to: true)
        audioProcessor.isMuted = false
        resetSilenceTimer()
    }

    private func handleToolCall(name: String, args: [String: String]) async {
        print("Friday (Local): executing \(name)")
        var resultMessage = ""
        
        switch name {
        case "control_music":
            if let action = args["action"] {
                if action == "play" { resultMessage = MusicSkill.play() }
                else if action == "pause" { resultMessage = MusicSkill.pause() }
                else if action == "next" { resultMessage = MusicSkill.nextTrack() }
                else if action == "search", let q = args["query"] { resultMessage = MusicSkill.playSearch(q) }
            }
        case "web_search":
            if let q = args["query"] { resultMessage = await SearchSkill.searchWeb(q) }
        case "get_weather":
            if let weather = await WeatherSkill.fetchWeather() {
                state.update(\.currentWeather, to: weather)
                resultMessage = "The weather is currently \(weather.current_weather.temperature) degrees."
            } else { resultMessage = "I couldn't get the weather." }
        case "get_time":
            resultMessage = "It's exactly \(TimeSkill.getCurrentTime())."
        default:
            resultMessage = "Tool execution finished."
        }
        
        if !resultMessage.isEmpty {
            brain.speak(text: resultMessage)
            try? await Task.sleep(nanoseconds: UInt64(Double(resultMessage.count) * 0.08 * 1_000_000_000))
        }
    }
}

struct FunctionCallSimple: Decodable {
    let name: String
    let arguments: [String: String]
}
