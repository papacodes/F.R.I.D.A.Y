import SwiftUI

/// Home-tab left column — compact music card (~170pt wide).
struct MusicPanelView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MUSIC", systemImage: "music.note")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1.2)

            if state.hasMusicTrack {
                nowPlayingContent
            } else {
                idleContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    // MARK: - Now playing

    private var nowPlayingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Album art with backdrop glow
                AlbumArtView(size: 54, cornerRadius: 10, showBackdrop: true)

                // Status Indicator
                VStack(alignment: .leading, spacing: 4) {
                    if state.isPlayingMusic {
                        MiniWaveform(isActive: true, color: state.albumAccentColor)
                            .frame(width: 38, height: 16)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4) )
                            Text("PAUSED")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Use Marquee for long titles
                MarqueeText(text: state.nowPlayingTitle, 
                           font: .system(size: 12, weight: .bold, design: .rounded), 
                           color: .white)
                    .frame(width: 160, height: 16)
                
                MarqueeText(text: state.nowPlayingArtist, 
                           font: .system(size: 11, weight: .medium, design: .rounded), 
                           color: state.albumAccentColor.opacity(0.9))
                    .frame(width: 160, height: 14)
            }
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 44, height: 44)
                Image(systemName: "music.note.list")
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(.white.opacity(0.15))
            }
            Text("NOTHING PLAYING")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.2))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 10)
    }
}
