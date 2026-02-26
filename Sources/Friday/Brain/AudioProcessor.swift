@preconcurrency import AVFoundation
import Foundation

final class AudioProcessor {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    
    nonisolated(unsafe) var isMuted = true
    nonisolated(unsafe) var wsTask: URLSessionWebSocketTask?
    nonisolated(unsafe) var onActivity: ((Bool) -> Void)?
    private var chunkCount = 0

    func start(ws: URLSessionWebSocketTask?, onActivity: @escaping (Bool) -> Void) {
        self.wsTask = ws
        self.onActivity = onActivity
        
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        
        let hwFormat = inputNode.inputFormat(forBus: 0)
        // Gemini requires 16kHz mono Int16 PCM. Interleaved must be false for non-planar mono.
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )
        
        guard let target = targetFormat else { return }
        converter = AVAudioConverter(from: hwFormat, to: target)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            var rms: Float = 0
            if let ch = buffer.floatChannelData {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { let s = ch[0][i]; sum += s * s }
                rms = sqrt(sum / Float(max(n, 1)))
            }
            
            let isActive = rms > 0.01 && !self.isMuted
            self.onActivity?(isActive)
            
            if self.chunkCount % 500 == 0 {
                print(String(format: "Friday VAD: RMS=%.4f (Active=%@, Muted=%@)", rms, String(isActive), String(self.isMuted)))
            }

            if self.isMuted { return }
            
            guard let conv = self.converter, let ws = self.wsTask else { return }
            
            // Calculate output frames based on sample rate ratio
            let ratio = 16000.0 / hwFormat.sampleRate
            let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard outFrames > 0, let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else { return }
            
            var error: NSError?
            let status = conv.convert(to: outBuf, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if let err = error {
                if self.chunkCount % 100 == 0 { print("Friday: conversion error - " + err.localizedDescription) }
                return
            }

            if status == .haveData, outBuf.frameLength > 0, let int16Data = outBuf.int16ChannelData {
                let pcmData = Data(bytes: int16Data[0], count: Int(outBuf.frameLength) * 2)
                let b64 = pcmData.base64EncodedString()
                let msg = "{\"realtime_input\":{\"media_chunks\":[{\"mime_type\":\"audio/pcm;rate=16000\",\"data\":\"" + b64 + "\"}]}}"
                
                self.chunkCount += 1
                if self.chunkCount % 50 == 0 {
                    print("Friday: sent " + String(self.chunkCount) + " audio chunks")
                }
                
                ws.send(.string(msg)) { sendErr in
                    if let sendErr = sendErr { print("Friday: send error - " + sendErr.localizedDescription) }
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
