import SwiftUI

struct FridayView: View {
    @ObservedObject private var state = FridayState.shared

    private let openSize = CGSize(width: 420, height: 280)
    private let openAnimation = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8)
    private let closeAnimation = Animation.interactiveSpring(response: 0.3, dampingFraction: 0.9)

    private var currentAnimation: Animation {
        state.isExpanded ? openAnimation : closeAnimation
    }

    // Animates between actual notch dimensions (collapsed) and open size (expanded)
    private var notchSize: CGSize {
        state.isExpanded ? openSize : state.closedNotchSize
    }

    private var topCornerRadius: CGFloat { state.isExpanded ? 19 : 6 }
    private var bottomCornerRadius: CGFloat { state.isExpanded ? 24 : 14 }

    var body: some View {
        // Top-aligned ZStack: content is anchored to the top of the fixed window,
        // which means it sits right at the top of the screen — in the notch.
        ZStack(alignment: .top) {
            // Black notch shape — always visible, grows on expand
            Color.black
                .clipShape(
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                )
                .frame(width: notchSize.width, height: notchSize.height)
                .animation(currentAnimation, value: state.isExpanded)

            // Content — renders inside the expanded notch shape
            if state.isExpanded {
                VStack(spacing: 20) {
                    SiriOrbView(volume: state.volume, isThinking: state.isThinking)
                        .scaleEffect(0.8)
                        .frame(width: 100, height: 100)
                        .padding(.top, 24)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                state.showInfoCard.toggle()
                            }
                        }

                    if state.showInfoCard {
                        InfoCardView(state: state)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(width: openSize.width)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(currentAnimation, value: state.isExpanded)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
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
