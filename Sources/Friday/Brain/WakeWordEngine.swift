import Foundation
import Speech
import AVFoundation

/// Always-on, on-device wake word listener.
///
/// Runs only when Friday is idle (dismissed or standard state).
/// Stops before GeminiVoicePipeline takes the mic and restarts after it releases.
/// Uses SFSpeechRecognizer with on-device recognition — no audio leaves the device.
@MainActor
final class WakeWordEngine {
    static let shared = WakeWordEngine()

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionRestartTimer: Timer?

    private(set) var isRunning = false

    // Phrases that trigger Friday. "hey" prefix dramatically reduces false positives
    // from everyday speech ("on Friday", "next Friday", etc.)
    private let wakePhrases = ["hey friday", "hey iris", "friday", "yo friday", "iris"]

    private init() {}

    // MARK: - Public

    /// Request speech recognition permission early so the dialog doesn't appear
    /// mid-hover. Does NOT start listening — that happens on goStandard().
    func requestPermission() {
        let callback: @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void = { status in
            if status == .denied || status == .restricted {
                print("[WakeWord] Speech recognition not authorized — hotkey still works")
            }
        }
        SFSpeechRecognizer.requestAuthorization(callback)
    }

    func start() {
        guard !isRunning else { return }
        guard speechRecognizer?.isAvailable == true else {
            // Recognizer not ready yet — retry shortly
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.start() }
            return
        }
        isRunning = true
        FridayState.shared.addActivity(type: .info, title: "Wake Word Active", subtitle: "Say \"Hey Friday\" to summon")
        beginSession()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        sessionRestartTimer?.invalidate()
        sessionRestartTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }

    // MARK: - Private

    private func beginSession() {
        // Clean up any previous session before starting a new one
        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Use a nonisolated factory so the returned closure has no @MainActor isolation.
        // Closures defined inside @MainActor functions inherit actor isolation even without
        // capturing self — the factory breaks that inference at the call site.
        let tapBlock = WakeWordEngine.makeTapBlock(for: request)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: tapBlock)

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("[WakeWord] Audio engine failed to start: \(error)")
            isRunning = false
            return
        }

        // Explicit @Sendable typing so SFSpeechRecognizer's background thread can call
        // this without hitting a @MainActor isolation check on the outer closure.
        let resultHandler: @Sendable (SFSpeechRecognitionResult?, Error?) -> Void = { [weak self] result, error in
            // Extract Sendable values before crossing into @MainActor — SFSpeechRecognitionResult is not Sendable
            let text = result?.bestTranscription.formattedString.lowercased()
            let isFinal = result?.isFinal ?? false

            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }

                if let text, self.wakePhrases.contains(where: { text.contains($0) }) {
                    self.triggered()
                    return
                }

                // Session ended (error or isFinal) — restart if still supposed to be running
                if error != nil || isFinal {
                    if self.isRunning { self.beginSession() }
                }
            }
        }
        recognitionTask = speechRecognizer?.recognitionTask(with: request, resultHandler: resultHandler)

        // SFSpeechRecognizer tasks have a ~1 min OS limit — restart proactively at 50s
        sessionRestartTimer?.invalidate()
        sessionRestartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                self.beginSession()
            }
        }
    }

    private func triggered() {
        stop()
        NotificationCenter.default.post(name: .fridayWakeWord, object: nil)
    }

    /// Produces an audio tap block with no @MainActor isolation.
    /// Must be nonisolated static — closures inherit actor isolation from their
    /// defining scope, so any closure created inside a @MainActor method is implicitly
    /// @MainActor, even without a self capture. A nonisolated context breaks that.
    private nonisolated static func makeTapBlock(
        for request: SFSpeechAudioBufferRecognitionRequest
    ) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in request.append(buffer) }
    }
}
