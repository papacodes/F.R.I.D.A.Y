import SwiftUI

/// Home-tab left column — compact music card (~170pt wide).
struct MusicPanelView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("MUSIC", systemImage: "music.note")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
                .tracking(1.5)

            if state.hasMusicTrack {
                nowPlayingContent
            } else {
                idleContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Now playing

    private var nowPlayingContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                // Album art
                AlbumArtView(size: 50, cornerRadius: 7)

                // Waveform / paused indicator
                VStack(alignment: .leading, spacing: 4) {
                    if state.isPlayingMusic {
                        MiniWaveform(isActive: true, color: state.albumAccentColor)
                            .frame(width: 36, height: 14)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                            Text("Paused")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(state.nowPlayingTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(state.nowPlayingArtist)
                .font(.system(size: 10))
                .foregroundColor(state.albumAccentColor.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.white.opacity(0.12))
            Text("Nothing playing")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.22))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
