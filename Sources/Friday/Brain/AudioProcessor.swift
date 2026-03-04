@preconcurrency import AVFoundation
import Foundation

final class AudioProcessor: @unchecked Sendable {
    let engine = AVAudioEngine()
    private var pcmBuffer = Data()
    private let maxBufferSize = 3200 // 100ms at 16kHz (2 bytes per sample)
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    private let stateLock = NSLock()
    private var _isMuted = true
    private var _wsTask: URLSessionWebSocketTask? = nil
    private var _onActivity: (@Sendable (Bool, Float) -> Void)? = nil
    private var _onLocalAudioChunk: (@Sendable ([Float]) -> Void)? = nil

    var isMuted: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isMuted }
        set { stateLock.lock(); defer { stateLock.unlock() }; _isMuted = newValue }
    }

    var wsTask: URLSessionWebSocketTask? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _wsTask }
        set { stateLock.lock(); defer { stateLock.unlock() }; _wsTask = newValue }
    }

    var onActivity: (@Sendable (Bool, Float) -> Void)? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _onActivity }
        set { stateLock.lock(); defer { stateLock.unlock() }; _onActivity = newValue }
    }
    
    var onLocalAudioChunk: (@Sendable ([Float]) -> Void)? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _onLocalAudioChunk }
        set { stateLock.lock(); defer { stateLock.unlock() }; _onLocalAudioChunk = newValue }
    }

    private let processingQueue = DispatchQueue(label: "com.friday.audio.processing", qos: .userInitiated)

    func start(ws: URLSessionWebSocketTask? = nil, onActivity: @escaping @Sendable (Bool, Float) -> Void) {
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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            var rms: Float = 0
            if let ch = buffer.floatChannelData {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { let s = ch[0][i]; sum += s * s }
                rms = sqrt(sum / Float(max(n, 1)))
            }

            let muted = self.isMuted
            let isActive = rms > 0.015 && !muted
            
            // CRITICAL: Signal activity to prevent auto-dismissal
            if isActive {
                DispatchQueue.main.async {
                    FridayState.shared.recordActivity()
                }
            }
            
            self.onActivity?(isActive, rms)

            if muted { return }

            let ws = self.wsTask
            let localCb = self.onLocalAudioChunk
            let conv = self.converter
            let target = self.targetFormat

            self.processingQueue.async {
                guard let conv = conv, let target = target else { return }
                let ratio = 16000.0 / hwFormat.sampleRate
                let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard outFrames > 0, let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else { return }

                var error: NSError?
                let status = conv.convert(to: outBuf, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .haveData, outBuf.frameLength > 0, let int16Data = outBuf.int16ChannelData {
                    let frameCount = Int(outBuf.frameLength)
                    let chunk = Data(bytes: int16Data[0], count: frameCount * 2)
                    
                    if let localCb = localCb {
                        var floatArray = [Float](repeating: 0, count: frameCount)
                        for i in 0..<frameCount {
                            floatArray[i] = Float(int16Data[0][i]) / 32768.0
                        }
                        localCb(floatArray)
                    }

                    self.stateLock.lock()
                    self.pcmBuffer.append(chunk)
                    if self.pcmBuffer.count >= self.maxBufferSize {
                        let toSend = self.pcmBuffer
                        self.pcmBuffer = Data()
                        self.stateLock.unlock()
                        if let ws = ws {
                            let b64 = toSend.base64EncodedString()
                            let msg = #"{"realtime_input":{"media_chunks":[{"mime_type":"audio/pcm;rate=16000","data":""# + b64 + #""}]}}"#
                            ws.send(.string(msg)) { _ in }
                        }
                    } else {
                        self.stateLock.unlock()
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
