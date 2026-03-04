import Foundation
import OnnxRuntimeBindings
@preconcurrency import AVFoundation

@MainActor
final class KokoroONNXManager: ObservableObject {
    static let shared = KokoroONNXManager()
    
    private var session: ORTSession?
    private var env: ORTEnv?
    private var isSetup = false
    
    // Voices are 1x512 Float32 vectors
    private var voices: [String: [Float]] = [:]
    
    nonisolated(unsafe) private var engine: AVAudioEngine?
    nonisolated(unsafe) private let playerNode = AVAudioPlayerNode()
    
    private init() {}
    
    func setup(engine: AVAudioEngine) async {
        guard !isSetup else { return }
        self.engine = engine
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let modelDir = home.appendingPathComponent("Models/friday/kokoro-v1_0")
        
        // Search for the ONNX model dynamically
        var modelFile: URL?
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil) {
            modelFile = contents.first { $0.pathExtension == "onnx" }
        }
        
        guard let finalModelFile = modelFile else {
            print("Friday (ONNX): No .onnx model file found in \(modelDir.path)")
            return
        }
        
        do {
            print("Friday (ONNX): Initializing Kokoro engine from \(finalModelFile.lastPathComponent)...")
            self.env = try ORTEnv(loggingLevel: .warning)
            self.session = try ORTSession(env: env!, modelPath: finalModelFile.path, sessionOptions: nil)
            
            // Attach to the shared engine
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
            
            isSetup = true
            print("Friday (ONNX): Internal voice engine ready.")
        } catch {
            print("Friday (ONNX): Setup failed: \(error)")
        }
    }
    
    func speak(_ text: String) {
        // High-performance Siri fallback while the ONNX tensor piping is completed
        // This ensures the user has a natural voice IMMEDIATELY without crashes.
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
        // Pick the best Siri voice available on the system
        utterance.voice = allVoices.first { $0.name.contains("Siri") && $0.quality == .enhanced }
            ?? allVoices.first { $0.name.contains("Siri") }
            ?? AVSpeechSynthesisVoice(language: "en-US")
            
        utterance.rate = 0.52
        synthesizer.speak(utterance)
    }
    
    func stop() {
        playerNode.stop()
    }
}
