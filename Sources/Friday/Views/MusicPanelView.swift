import SwiftUI

struct MusicPanelView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Label("MUSIC", systemImage: "music.note")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1.5)

            if state.isPlayingMusic {
                nowPlayingContent
            } else {
                idleContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sub-views

    private var nowPlayingContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Album art placeholder + waveform
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: "music.note")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.4))
                }

                VStack(alignment: .leading, spacing: 4) {
                    WaveformView(isActive: true, color: .cyan)
                        .frame(height: 20)
                        .clipped()
                }
            }

            Text(state.nowPlayingTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Text(state.nowPlayingArtist)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    private var idleContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.15))
            Text("Nothing playing")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
