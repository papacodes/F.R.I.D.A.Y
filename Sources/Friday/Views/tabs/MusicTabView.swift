import SwiftUI

struct MusicTabView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(spacing: 16) {
            if state.isPlayingMusic {
                nowPlayingView
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nowPlayingView: some View {
        HStack(spacing: 20) {
            // Album art
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 80, height: 80)
                Image(systemName: "music.note")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.3))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(state.nowPlayingTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(state.nowPlayingArtist)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))

                WaveformView(isActive: true, color: .cyan)
                    .frame(height: 24)
            }
        }
        .padding(.horizontal, 8)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.12))
            Text("Nothing playing")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.25))
            Text("Ask Friday to play something")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.15))
        }
    }
}
