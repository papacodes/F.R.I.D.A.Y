import Foundation
import Observation
import AVFoundation

@MainActor
final class NativeSpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = NativeSpeechManager()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    
    @Published var isSpeaking = false
    private var currentCompletion: (@Sendable () -> Void)?
    
    private override init() {
        super.init()
        synthesizer.delegate = self
        setupVoice()
    }
    
    private func setupVoice() {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        self.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Zoe") 
                  ?? allVoices.first { $0.quality == .premium } 
                  ?? AVSpeechSynthesisVoice(language: "en-US")
        print("Friday: Native voice selected -> \(self.voice?.name ?? "Default")")
    }
    
    func speak(_ text: String, completion: (@Sendable () -> Void)? = nil) {
        if text.contains("{") || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion?()
            return
        }
        
        // CRITICAL: Always resume previous before starting new
        if let oldHandler = currentCompletion {
            oldHandler()
            currentCompletion = nil
        }
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        self.currentCompletion = completion
        self.isSpeaking = true
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = self.voice
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
        
        // Safety timeout: If delegate fails, resume after 15s anyway
        let timeoutHandler = completion
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await MainActor.run {
                if self.currentCompletion != nil && timeoutHandler != nil {
                    print("Friday: Speech safety timeout triggered.")
                    self.currentCompletion?()
                    self.currentCompletion = nil
                    self.isSpeaking = false
                }
            }
        }
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        if let handler = currentCompletion {
            handler()
            currentCompletion = nil
        }
        isSpeaking = false
    }
    
    // MARK: - Delegate
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentCompletion?()
            self.currentCompletion = nil
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentCompletion?()
            self.currentCompletion = nil
        }
    }
}
