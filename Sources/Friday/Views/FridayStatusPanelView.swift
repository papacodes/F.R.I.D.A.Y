import SwiftUI

struct FridayStatusPanelView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(spacing: 20) { // Increased spacing
            // Orb — Focused and Liquid
            SiriOrbView(volume: state.volume, isThinking: state.isThinking, isError: state.isError, isDevTask: state.isDevTaskRunning)
                .frame(width: 80, height: 80)
                .scaleEffect(1.4)
                .shadow(color: statusColor.opacity(0.3), radius: 20)
                .padding(.top, 12) // PUSH IT DOWN to avoid clipping

            // Status label — Pure White, Rounded, Strong Tracking
            Text(statusText.uppercased())
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(.white) // Pure White
                .tracking(1.5)
                .shadow(color: .black.opacity(0.5), radius: 2)

            // Transcript — Pure White but translucent for clarity, beautiful typeset
            if !state.transcript.isEmpty {
                Text("\u{201C}\(state.transcript)\u{201D}")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85)) // Pure White but readable
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 32)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .shadow(color: .black.opacity(0.3), radius: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: statusText)
    }

    private var statusText: String {
        if state.isListening { return "Listening" }
        if state.isThinking  { return "Thinking" }
        if state.isSpeaking  { return "Speaking" }
        if state.isError     { return "Error" }
        return "Friday"
    }

    private var statusColor: Color {
        if state.isListening { return .cyan }
        if state.isThinking  { return .purple }
        if state.isSpeaking  { return .cyan }
        if state.isError     { return .red }
        return .white.opacity(0.1)
    }
}
