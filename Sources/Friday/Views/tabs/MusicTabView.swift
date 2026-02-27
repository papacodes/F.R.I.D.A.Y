import SwiftUI

struct MusicTabView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        Group {
            if state.hasMusicTrack {
                playerView
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                emptyView
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Full player (Liquid Glass Style)

    private var playerView: some View {
        ZStack {
            // Blurred album art backdrop - More vibrant and high-end
            if let art = state.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(1.4)
                    .blur(radius: 60)
                    .opacity(state.isPlayingMusic ? 0.45 : 0.2)
                    .clipped()
                    .animation(.easeInOut(duration: 0.8), value: state.isPlayingMusic)
            }

            // High-contrast overlay
            Color.black.opacity(0.35)

            HStack(alignment: .center, spacing: 28) {
                // Album art with a crisp edge
                AlbumArtView(size: 110, cornerRadius: 18, showBackdrop: true)
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)

                // Track info + controls
                VStack(alignment: .leading, spacing: 0) {
                    // Title - Pure White, Heavy Weight
                    MarqueeText(
                        text: state.nowPlayingTitle.isEmpty ? "NOTHING PLAYING" : state.nowPlayingTitle.uppercased(),
                        font: .system(size: 14, weight: .black, design: .rounded),
                        color: .white // Pure White
                    )
                    .tracking(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 20)

                    // Artist - Strong semi-white
                    MarqueeText(
                        text: state.nowPlayingArtist.isEmpty ? "Ready to play" : state.nowPlayingArtist,
                        font: .system(size: 12, weight: .bold, design: .rounded),
                        color: .white.opacity(0.6) // Pure White translucent
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 18)
                    .padding(.top, 2)

                    Spacer(minLength: 12)

                    // Progress
                    MusicProgressSlider()
                        .padding(.vertical, 4)

                    // Controls row
                    HStack {
                        MusicControlsView()
                            .scaleEffect(0.9)
                        
                        Spacer()
                        
                        // Active Waveform
                        if state.isPlayingMusic {
                            MiniWaveform(isActive: true, color: .white.opacity(0.8))
                                .frame(width: 32, height: 16)
                                .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: state.nowPlayingTitle)
    }

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 64, height: 64)
                Image(systemName: "music.note.list")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.white.opacity(0.12))
            }
            
            VStack(spacing: 4) {
                Text("READY TO PLAY")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(1.0)
                
                Text("Ask Friday to play your favorites")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.15))
            }
        }
    }
}
