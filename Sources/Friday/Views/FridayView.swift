import SwiftUI

struct FridayView: View {
    @ObservedObject private var state = FridayState.shared

    // Cyan used when Friday is speaking
    private let speakingColor = Color(red: 0, green: 0.85, blue: 1.0)

    var body: some View {
        ZStack {
            // Pill shape with soft drop shadow
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 6)

            // State-driven center content
            Group {
                if state.isError {
                    ThinkingView(color: .orange)
                } else if state.isThinking {
                    ThinkingView()
                } else if state.isSpeaking {
                    WaveformView(isActive: true, color: speakingColor)
                        .padding(.horizontal, 32)
                } else {
                    WaveformView(isActive: state.isListening, color: .white)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}
