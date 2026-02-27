import SwiftUI

struct MusicControlsView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        HStack(spacing: 6) {
            MediaButton(icon: "backward.end.fill", size: 15) {
                MediaRemoteManager.shared.previousTrack()
            }

            MediaButton(icon: state.isPlayingMusic ? "pause.fill" : "play.fill", size: 20, isLarge: true) {
                MediaRemoteManager.shared.togglePlayPause()
            }

            MediaButton(icon: "forward.end.fill", size: 15) {
                MediaRemoteManager.shared.nextTrack()
            }
        }
    }
}

// MARK: - MediaButton

private struct MediaButton: View {
    let icon: String
    let size: CGFloat
    var isLarge: Bool = false
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed  = false

    var frameSize: CGFloat { isLarge ? 44 : 36 }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: frameSize, height: frameSize)
                .background(
                    RoundedRectangle(cornerRadius: isLarge ? 12 : 10, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.13 : 0))
                        .animation(.smooth(duration: 0.2), value: isHovering)
                )
                .scaleEffect(isPressed ? 0.88 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}
