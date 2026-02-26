import SwiftUI

struct FridayView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // The Floating Orb + Card Container
                VStack(spacing: 20) {
                    // THE ORB
                    ZStack {
                        if proxy.size.height > 40 {
                            SiriOrbView(volume: state.volume, isThinking: state.isThinking)
                                .scaleEffect(0.8)
                                .frame(width: 100, height: 100)
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        state.showInfoCard.toggle()
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .opacity
                                ))
                        } else {
                            // Resting state: a tiny glowing point (Small Dot)
                            Circle()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: 8, height: 8)
                                .shadow(color: .white.opacity(0.8), radius: 4)
                                .padding(.top, 12)
                        }
                    }
                    .frame(height: 100)

                    // INFO CARD
                    if state.showInfoCard && proxy.size.height > 100 {
                        InfoCardView(state: state)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state.volume)
        .animation(.spring(), value: state.isThinking || state.isListening || state.isSpeaking || state.showInfoCard)
        .ignoresSafeArea()
    }
}

struct InfoCardView: View {
    @ObservedObject var state: FridayState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Friday Status")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "cpu")
                    .foregroundColor(.cyan)
            }
            
            Divider().background(Color.white.opacity(0.2))
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Model: \(state.modelName)", systemImage: "brain")
                Label("Input: Microphone (16kHz)", systemImage: "mic.fill")
                Label("Tools: Claude Code, Shell, Search", systemImage: "hammer.fill")
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.8))
            
            if !state.transcript.isEmpty {
                Text("\"\(state.transcript)\"")
                    .font(.caption)
                    .italic()
                    .foregroundColor(.cyan.opacity(0.9))
                    .padding(.top, 4)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        .frame(width: 300)
    }
}
