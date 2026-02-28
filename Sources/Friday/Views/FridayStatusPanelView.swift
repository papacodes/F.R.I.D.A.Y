import SwiftUI

struct FridayStatusPanelView: View {
    @ObservedObject private var state = FridayState.shared
    var namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 12) {
            // Orb Container - constrained to prevent clipping
            ZStack {
                SiriOrbView(
                    volume: state.volume,
                    isThinking: state.isThinking,
                    isError: state.isError,
                    isDevTask: state.isDevTaskRunning,
                    isConnected: state.isConnected
                )
                .frame(width: 100, height: 100)
                .matchedGeometryEffect(id: "orb_view", in: namespace)
                .shadow(color: statusColor.opacity(0.3), radius: 15)
            }
            .frame(height: 110)
            .padding(.top, 4)

            // Status label
            Text(statusText.uppercased())
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .tracking(1.5)
                .matchedGeometryEffect(id: "orb_text", in: namespace)
                .shadow(color: .black.opacity(0.5), radius: 2)

            // Transcript - Limited height and line limit to stay in bounds
            if !state.transcript.isEmpty {
                Text("\u{201C}\(state.transcript)\u{201D}")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 40)
                    .frame(height: 40)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                // Spacer to keep layout stable when transcript is empty
                Spacer().frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            Color.clear
                .matchedGeometryEffect(id: "orb_bg", in: namespace)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: statusText)
    }

    private var statusText: String {
        if state.isListening { return "Listening" }
        if state.isThinking  { return "Thinking" }
        if state.isSpeaking  { return "Speaking" }
        if state.isError     { return "Error" }
        return "Friday." // Modified
    }

    private var statusColor: Color {
        if state.isListening { return .cyan }
        if state.isThinking  { return .purple }
        if state.isSpeaking  { return .cyan }
        if state.isError     { return .red }
        return .white.opacity(0.1)
    }
}
