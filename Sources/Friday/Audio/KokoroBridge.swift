import AVFoundation
import Foundation

@MainActor
final class KokoroBridge {

    private var player: AVAudioPlayer?

    func speak(_ text: String) async throws {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:8880/v1/audio/speech")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "kokoro",
            "input": text,
            "voice": "af_sarah",
            "response_format": "mp3",
        ])

        let (audioData, _) = try await URLSession.shared.data(for: req)
        player = try AVAudioPlayer(data: audioData)
        player?.play()

        // Poll until playback finishes — give it 100ms to start before checking
        try await Task.sleep(nanoseconds: 100_000_000)
        while player?.isPlaying == true {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
