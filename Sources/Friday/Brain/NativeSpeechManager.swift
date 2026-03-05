import Foundation
import Observation
import AVFoundation

@MainActor
final class NativeSpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = NativeSpeechManager()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    
    @Published var isSpeaking = false
    private var completionHandler: (@Sendable () -> Void)?
    
    private override init() {
        super.init()
        synthesizer.delegate = self
        setupVoice()
    }
    
    private func setupVoice() {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        // Prioritize Zoe (Premium), then Zoe (Enhanced), then any Premium voice, then fallback
        self.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Zoe") ?? allVoices.first { $0.quality == .premium } ?? AVSpeechSynthesisVoice(language: "en-US")
        
        print("Friday: Native voice selected -> \(self.voice?.name ?? "Default")")
    }
    
    func speak(_ text: String, completion: (@Sendable () -> Void)? = nil) {
        // Shield: Never speak JSON or empty strings
        if text.contains("{") || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion?()
            return
        }
        
        // Stop any current speech before starting new one (Barge-in foundation)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        self.completionHandler = completion
        self.isSpeaking = true
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = self.voice
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.05 // Slightly faster than default for that 'smart' feel
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        completionHandler?()
        completionHandler = nil
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.completionHandler?()
            self.completionHandler = nil
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.completionHandler?()
            self.completionHandler = nil
        }
    }
}
