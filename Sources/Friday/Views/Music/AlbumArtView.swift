import SwiftUI

/// Album art image with rounded corners, playing/paused scale, and optional blur backdrop.
struct AlbumArtView: View {
    @ObservedObject private var state = FridayState.shared
    let size: CGFloat
    let cornerRadius: CGFloat
    var showBackdrop: Bool = false

    var body: some View {
        ZStack {
            if showBackdrop, let art = state.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size * 1.4, height: size * 1.4)
                    .scaleEffect(1.3)
                    .blur(radius: 40)
                    .opacity(state.isPlayingMusic ? 0.5 : 0)
                    .animation(.easeInOut(duration: 0.6), value: state.isPlayingMusic)
                    .clipped()
            }

            if let art = state.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .scaleEffect(state.isPlayingMusic ? 1.0 : 0.87)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: state.isPlayingMusic)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.32, weight: .light))
                            .foregroundColor(.white.opacity(0.2))
                    )
            }
        }
        .frame(width: size, height: size)
    }
}

/// Tiny thumbnail for the standard (horizontal) notch bar.
struct AlbumArtThumbnail: View {
    @ObservedObject private var state = FridayState.shared
    let size: CGFloat

    var body: some View {
        Group {
            if let art = state.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundColor(.cyan.opacity(0.8))
                    .frame(width: size, height: size)
            }
        }
    }
}
