import SwiftUI

struct MusicTabView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        Group {
            if state.hasMusicTrack {
                playerView
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Full player

    private var playerView: some View {
        ZStack {
            // Blurred album art backdrop
            if let art = state.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1.5)
                    .blur(radius: 48)
                    .opacity(state.isPlayingMusic ? 0.5 : 0.22)
                    .clipped()
                    .animation(.easeInOut(duration: 0.6), value: state.isPlayingMusic)
            }

            // Darkening overlay
            Color.black.opacity(0.52)

            HStack(alignment: .center, spacing: 22) {
                // Album art
                AlbumArtView(size: 90, cornerRadius: 13)

                // Track info + controls
                VStack(alignment: .leading, spacing: 0) {
                    MarqueeText(
                        text: state.nowPlayingTitle.isEmpty ? "Unknown Track" : state.nowPlayingTitle,
                        font: .system(size: 14, weight: .semibold),
                        color: .white
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 22)

                    MarqueeText(
                        text: state.nowPlayingArtist.isEmpty ? "Unknown Artist" : state.nowPlayingArtist,
                        font: .system(size: 12, weight: .regular),
                        color: state.albumAccentColor
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 18)

                    Spacer(minLength: 8)

                    MusicProgressSlider()

                    HStack {
                        MusicControlsView()
                        Spacer()
                        // Subtle waveform when playing
                        if state.isPlayingMusic {
                            MiniWaveform(isActive: true, color: state.albumAccentColor.opacity(0.7))
                                .frame(width: 28, height: 14)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
    }

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white.opacity(0.12))
            Text("Nothing playing")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.25))
            Text("Ask Friday to play something")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.14))
        }
    }
}
