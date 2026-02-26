import AVFoundation
import Foundation

// @unchecked Sendable: buffer/silenceCount are accessed only from the audio tap thread.
// stop() calls removeTap(onBus:) which blocks until any in-flight callback completes,
// so state is safe to clear afterward.
final class MicrophoneCapture: @unchecked Sendable {

    // -- Audio state (tap thread only) --
    // Mute during TTS so Friday doesn't hear herself
    nonisolated(unsafe) var isMuted = false

    nonisolated(unsafe) private var buffer: [Float] = []
    nonisolated(unsafe) private var silenceCount = 0
    nonisolated(unsafe) private var capturedSampleRate: Double = 44100

    private let audioEngine = AVAudioEngine()
    private var configChangeObserver: Any?

    // VAD tuning
    private let rmsThreshold: Float = 0.015  // below this = silence
    private let silenceFramesEnd = 10        // ~930 ms at 4096/44100 per buffer

    // Callbacks — always dispatched to main queue
    var onVoiceStart: (() -> Void)?
    var onVoiceEnd: (() -> Void)?
    var onUtterance: ((Data) -> Void)?

    func start() throws {
        // When AVAudioPlayer (TTS) finishes, macOS can reconfigure the audio graph
        // which silently stops AVAudioEngine. Observe and restart when that happens.
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isMuted else { return }
            print("Friday: audio engine reconfigured — restarting")
            self.audioEngine.prepare()
            try? self.audioEngine.start()
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let hwFormat = inputNode.inputFormat(forBus: 0)
        capturedSampleRate = hwFormat.sampleRate
        let channelCount = Int(hwFormat.channelCount)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buf, _ in
            self?.process(buf, channels: channelCount)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() {
        if let obs = configChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            configChangeObserver = nil
        }
        audioEngine.inputNode.removeTap(onBus: 0)  // blocks until in-flight callback finishes
        audioEngine.stop()
        buffer.removeAll()
        silenceCount = 0
    }

    // MARK: - Audio processing (tap thread)

    private func process(_ buf: AVAudioPCMBuffer, channels: Int) {
        guard !isMuted else { return }
        guard let channelData = buf.floatChannelData else { return }
        let frameCount = Int(buf.frameLength)
        guard frameCount > 0 else { return }

        // Mix to mono and compute RMS in one pass
        var rms: Float = 0
        var monoFrames = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            var s: Float = 0
            for ch in 0..<channels { s += channelData[ch][i] }
            monoFrames[i] = s / Float(channels)
            rms += monoFrames[i] * monoFrames[i]
        }
        rms = sqrt(rms / Float(frameCount))

        if rms > rmsThreshold {
            if buffer.isEmpty {
                let cb = onVoiceStart
                DispatchQueue.main.async { cb?() }
            }
            silenceCount = 0
            buffer.append(contentsOf: monoFrames)
        } else if !buffer.isEmpty {
            buffer.append(contentsOf: monoFrames)
            silenceCount += 1

            if silenceCount >= silenceFramesEnd {
                let cb = onVoiceEnd
                DispatchQueue.main.async { cb?() }

                let samples = buffer
                let sr = capturedSampleRate
                buffer.removeAll()
                silenceCount = 0

                guard let wav = Self.makeWav(samples: samples, sampleRate: sr) else { return }
                let cb2 = onUtterance
                DispatchQueue.main.async { cb2?(wav) }
            }
        }
    }

    // MARK: - WAV packing

    private static func makeWav(samples: [Float], sampleRate: Double) -> Data? {
        let byteCount = samples.count * 2  // 16-bit PCM
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
