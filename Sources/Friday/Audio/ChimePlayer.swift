import AVFoundation
import Foundation

// Plays short programmatic tones for audio feedback.
// Generates sine wave PCM in memory — no bundled audio files needed.
@MainActor
final class ChimePlayer {

    static let shared = ChimePlayer()
    private init() {}

    private var player: AVAudioPlayer?

    // Soft descending ding — played when Friday finishes hearing you.
    // Signals: "got it, processing now."
    func playListenEnd() {
        play(frequency: 880, overtone: 1320, duration: 0.14, volume: 0.30)
    }

    // Quieter, lower tone — played just before Claude is called.
    // Signals: "thinking."
    func playThinking() {
        play(frequency: 528, overtone: 0, duration: 0.10, volume: 0.18)
    }

    // MARK: - Private

    private func play(frequency: Double, overtone: Double, duration: Double, volume: Float) {
        let sampleRate = 44100.0
        let frameCount = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            // Smooth fade-out using cosine envelope
            let envelope = Float(0.5 * (1.0 + cos(.pi * Double(i) / Double(frameCount))))
            var s = Float(sin(2.0 * .pi * frequency * t))
            if overtone > 0 {
                s += Float(sin(2.0 * .pi * overtone * t)) * 0.25
            }
            samples[i] = s * volume * envelope
        }

        guard let data = makeWav(samples: samples, sampleRate: sampleRate) else { return }
        player = try? AVAudioPlayer(data: data)
        player?.play()
    }

    private func makeWav(samples: [Float], sampleRate: Double) -> Data? {
        let byteCount = samples.count * 2
        var d = Data(count: 44 + byteCount)
        d.withUnsafeMutableBytes { p in
            func u32(_ v: UInt32, _ o: Int) {
                p[o] = UInt8(v & 0xFF); p[o+1] = UInt8(v >> 8 & 0xFF)
                p[o+2] = UInt8(v >> 16 & 0xFF); p[o+3] = UInt8(v >> 24 & 0xFF)
            }
            func u16(_ v: UInt16, _ o: Int) {
                p[o] = UInt8(v & 0xFF); p[o+1] = UInt8(v >> 8 & 0xFF)
            }
            let sr = UInt32(sampleRate)
            p[0]=0x52; p[1]=0x49; p[2]=0x46; p[3]=0x46  // "RIFF"
            u32(UInt32(36 + byteCount), 4)
            p[8]=0x57; p[9]=0x41; p[10]=0x56; p[11]=0x45   // "WAVE"
            p[12]=0x66; p[13]=0x6D; p[14]=0x74; p[15]=0x20 // "fmt "
            u32(16, 16); u16(1, 20); u16(1, 22)             // chunk, PCM, mono
            u32(sr, 24); u32(sr * 2, 28)                    // sampleRate, byteRate
            u16(2, 32); u16(16, 34)                         // blockAlign, bitsPerSample
            p[36]=0x64; p[37]=0x61; p[38]=0x74; p[39]=0x61 // "data"
            u32(UInt32(byteCount), 40)
            for (i, s) in samples.enumerated() {
                let v = UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))
                let o = 44 + i * 2
                p[o] = UInt8(v & 0xFF); p[o+1] = UInt8(v >> 8)
            }
        }
        return d
    }
}
