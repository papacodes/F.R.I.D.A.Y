import SwiftUI

struct MusicProgressSlider: View {
    @ObservedObject private var state = FridayState.shared
    @State private var isDragging = false
    @State private var dragPosition: Double = 0

    private var displayPosition: Double {
        isDragging ? dragPosition : state.playbackPosition
    }

    private var progress: Double {
        guard state.playbackDuration > 0 else { return 0 }
        return min(max(displayPosition / state.playbackDuration, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.12))

                    // Fill
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(state.albumAccentColor)
                        .frame(width: geo.size.width * progress)
                }
                .frame(height: isDragging ? 9 : 5)
                .frame(maxHeight: .infinity, alignment: .center)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isDragging)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging { isDragging = true }
                            let ratio = value.location.x / geo.size.width
                            dragPosition = max(0, min(ratio * state.playbackDuration, state.playbackDuration))
                        }
                        .onEnded { _ in
                            MediaRemoteManager.shared.seek(to: dragPosition)
                            isDragging = false
                        }
                )
            }
            .frame(height: 14)

            // Time labels
            HStack {
                Text(formatTime(displayPosition))
                    .font(.system(size: 10, weight: .light, design: .rounded))
                    .foregroundColor(state.albumAccentColor.opacity(0.75))
                    .monospacedDigit()
                Spacer()
                Text(formatTime(state.playbackDuration))
                    .font(.system(size: 10, weight: .light, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .monospacedDigit()
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
