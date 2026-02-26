import Foundation

@MainActor
final class VoicePipeline {

    private let mic = MicrophoneCapture()
    private let tts = KokoroBridge()
    private let brain = ClaudeProcess()
    private let chime = ChimePlayer.shared
    private let state: FridayState

    private var sentenceQueue: [String] = []
    private var isPlaying = false

    init(state: FridayState) {
        self.state = state
    }

    func start() {
        // Greet immediately — user knows Friday is alive and listening
        enqueueSentence(Phrases.randomGreeting())

        // Pre-warm the claude binary in the background (OS caches it after first launch)
        brain.preWarm()

        // Start mic after greeting so she doesn't hear herself
        // The TTS sentence queue mutes the mic during playback automatically,
        // but we still want the mic wired before the greeting finishes
        requestMicAndStart()
    }

    func stop() {
        mic.isMuted = true
        mic.stop()
        sentenceQueue.removeAll()
        isPlaying = false
        state.isListening = false
        state.isThinking = false
        state.isSpeaking = false
        state.isError = false
    }

    // MARK: - Private

    private func requestMicAndStart() {
        // AVAudioEngine handles mic access directly through the terminal's
        // inherited permission — no AVCaptureDevice check needed for CLI tools.
        do {
            try mic.start()
            wireMic()
        } catch {
            print("Friday: mic start failed — \(error)")
        }
    }

    private func wireMic() {
        mic.onVoiceStart = { [weak self] in self?.state.isListening = true }
        mic.onVoiceEnd   = { [weak self] in self?.state.isListening = false }
        mic.onUtterance  = { [weak self] wavData in
            guard let self else { return }
            // Mute immediately — chimes and processing audio must not be re-captured
            self.mic.isMuted = true
            Task { await self.handleUtterance(wavData) }
        }
    }

    private func handleUtterance(_ wavData: Data) async {
        // Chime: "I heard you" — safe now, mic is already muted
        chime.playListenEnd()

        do {
            state.isThinking = true

            let transcript = try await WhisperBridge.transcribe(wavData)
            guard !transcript.isEmpty, transcript != "[BLANK_AUDIO]", transcript.count > 3 else {
                state.isThinking = false
                mic.isMuted = false  // nothing to do — open mic again
                return
            }
            state.transcript = transcript
            print("Friday: heard — '\(transcript)'")

            // Chime: "thinking" — still safe, mic is muted
            chime.playThinking()

            let response = try await brain.ask(transcript)
            state.isThinking = false

            guard !response.isEmpty else {
                mic.isMuted = false  // nothing to say — open mic again
                return
            }
            // playNext() owns the mic from here: muted during TTS, unmuted when queue empties
            enqueueSentence(response)

        } catch {
            print("Friday: pipeline error — \(error)")
            state.isThinking = false
            mic.isMuted = false  // error path — open mic again
            showError()
        }
    }

    // Flash error state briefly — orange dots for 2s
    private func showError() {
        state.isError = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.state.isError = false
        }
    }

    // MARK: - Sentence queue (sequential TTS, mic muted during playback)

    private func enqueueSentence(_ sentence: String) {
        let clean = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        print("Friday: queuing — '\(clean.prefix(60))'")
        sentenceQueue.append(clean)
        if !isPlaying { playNext() }
    }

    private func playNext() {
        guard !sentenceQueue.isEmpty else {
            isPlaying = false
            state.isSpeaking = false
            mic.isMuted = false     // unmute now that Friday is done speaking
            return
        }
        isPlaying = true
        state.isSpeaking = true
        mic.isMuted = true          // mute mic while Friday is speaking

        let sentence = sentenceQueue.removeFirst()
        Task {
            do { try await tts.speak(sentence) }
            catch { print("Friday: TTS error — \(error)") }
            playNext()
        }
    }
}
