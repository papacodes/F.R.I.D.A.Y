import SwiftUI

/// Music-tab: Mimics the Hero structure of Home but with the player as the focus.
struct MusicTabView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(spacing: 0) {
            // HERO AREA: Full Player
            ZStack {
                if let art = state.albumArt {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .blur(radius: 40)
                        .opacity(0.3)
                        .clipped()
                }
                
                HStack(spacing: 20) {
                    AlbumArtView(size: 80, cornerRadius: 12, showBackdrop: false)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(
                            text: state.nowPlayingTitle.isEmpty ? "NOTHING PLAYING" : state.nowPlayingTitle.uppercased(),
                            font: .system(size: 13, weight: .black, design: .rounded),
                            color: .white
                        )
                        .frame(height: 18)
                        
                        Text(state.nowPlayingArtist.isEmpty ? "Idle" : state.nowPlayingArtist)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                        
                        MusicProgressSlider()
                            .padding(.top, 4)
                        
                        MusicControlsView()
                            .scaleEffect(0.8)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(height: 160)
            .background(Color.white.opacity(0.03))
            .cornerRadius(20)
            .padding(.top, 10)

            Spacer()

            // BOTTOM ROW: Persistent System Pill for balance
            HStack {
                Spacer()
                MiniSystemPill() // Re-using local version or proxy
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

// Small Proxy for symmetry
private struct MiniSystemPill: View {
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(Date(), format: .dateTime.hour().minute())
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                
                Text(Date(), format: .dateTime.weekday(.wide).day())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
                .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
        )
    }
}
