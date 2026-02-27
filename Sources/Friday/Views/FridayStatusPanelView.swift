import SwiftUI

struct FridayStatusPanelView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(spacing: 10) {
            // Orb
            SiriOrbView(volume: state.volume, isThinking: state.isThinking)
                .scaleEffect(0.55)
                .frame(width: 60, height: 60)

            // Status label
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(statusColor)
                .animation(.easeInOut(duration: 0.2), value: statusText)

            // Transcript
            if !state.transcript.isEmpty {
                Text("\u{201C}\(state.transcript)\u{201D}")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        if state.isListening { return "Listening" }
        if state.isThinking  { return "Thinking" }
        if state.isSpeaking  { return "Speaking" }
        if state.isError     { return "Error" }
        return "Ready"
    }

    private var statusColor: Color {
        if state.isListening { return .cyan }
        if state.isThinking  { return .white.opacity(0.7) }
        if state.isSpeaking  { return .cyan }
        if state.isError     { return .red.opacity(0.8) }
        return .white.opacity(0.35)
    }
}
