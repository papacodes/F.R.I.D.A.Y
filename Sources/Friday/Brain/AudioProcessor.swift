@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AudioProcessor {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    var isMuted = true
    var wsTask: URLSessionWebSocketTask? = nil
    var onActivity: ((Bool) -> Void)? = nil

    private let processingQueue = DispatchQueue(label: "com.friday.audio.processing", qos: .userInitiated)

    func start(ws: URLSessionWebSocketTask?, onActivity: @escaping (Bool) -> Void) {
        self.wsTask = ws
        self.onActivity = onActivity

        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)

        let hwFormat = inputNode.inputFormat(forBus: 0)
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )

        guard let target = targetFormat else { return }
        converter = AVAudioConverter(from: hwFormat, to: target)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            // Fast RMS calculation on the audio thread
            var rms: Float = 0
            if let ch = buffer.floatChannelData {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { let s = ch[0][i]; sum += s * s }
                rms = sqrt(sum / Float(max(n, 1)))
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let muted = self.isMuted
                let isActive = rms > 0.01 && !muted
                self.onActivity?(isActive)

                if muted { return }

                let currentWs = self.wsTask
                let conv = self.converter

                // Offload heavy conversion and JSON work to a background queue
                self.processingQueue.async { [weak self] in
                    guard let conv = conv, let ws = currentWs, let target = self?.targetFormat else { return }

                    let ratio = 16000.0 / hwFormat.sampleRate
                    let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                    guard outFrames > 0, let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else { return }

                    var error: NSError?
                    let status = conv.convert(to: outBuf, error: &error) { _, outStatus in
                        outStatus.pointee = .haveData
                        return buffer
                    }

                    if status == .haveData, outBuf.frameLength > 0, let int16Data = outBuf.int16ChannelData {
                        let pcmData = Data(bytes: int16Data[0], count: Int(outBuf.frameLength) * 2)
                        let b64 = pcmData.base64EncodedString()
                        let msg = #"{"realtime_input":{"media_chunks":[{"mime_type":"audio/pcm;rate=16000","data":""# + b64 + #""}]}}"#
                        ws.send(.string(msg)) { _ in }
                    }
                }
            }
        }

        engine.prepare()
        try? engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        wsTask = nil
        onActivity = nil
    }
}
