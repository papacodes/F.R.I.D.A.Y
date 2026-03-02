import SwiftUI

struct MusicTabView: View {
    @ObservedObject private var state = FridayState.shared
    var namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            // Player Stage
            HStack(spacing: 24) {
                // Symmetrical, centered music view
                AlbumArtView(size: 80, cornerRadius: 14, showBackdrop: false)
                    .matchedGeometryEffect(id: "music_art", in: namespace)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
                
                // Track Info & Controls
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        MarqueeText(
                            text: state.nowPlayingTitle.isEmpty ? "NOTHING PLAYING" : state.nowPlayingTitle.uppercased(),
                            font: .system(size: 13, weight: .black, design: .rounded),
                            color: .white
                        )
                        .frame(height: 18)

                        Text(state.nowPlayingArtist.isEmpty ? "Idle" : state.nowPlayingArtist)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }

                    MusicControlsView()
                        .padding(.top, 4)

                    MusicProgressSlider()
                }
                .frame(width: 200, alignment: .leading)
                .matchedGeometryEffect(id: "music_info", in: namespace)
            }
        }
        .frame(height: 140)
        .background(
            Color.white.opacity(0.01)
                .cornerRadius(20)
                .matchedGeometryEffect(id: "music_bg", in: namespace)
        )
        .padding(.horizontal, 40)
    }
}
