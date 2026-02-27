import SwiftUI

/// Home-tab: Focused Siri-style experience with a giant orb.
/// Replaces the messy three-column layout with a focused, future-facing design.
struct NotchHomeView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        ZStack {
            // Background Liquid Glow (Fills the island for depth)
            Circle()
                .fill(RadialGradient(
                    colors: [Color.cyan.opacity(0.12), .clear],
                    center: .center, startRadius: 0, endRadius: 200
                ))
                .frame(width: 400, height: 400)
                .offset(y: 20)
                .blur(radius: 40)

            VStack(spacing: 28) {
                // Focus: Large Siri Orb with status and transcript
                FridayStatusPanelView()
                    .padding(.top, 12)

                // Secondary Row: Floating Pills (Inspired by boring.notch's clean HUDs)
                HStack(alignment: .bottom, spacing: 14) {
                    if state.hasMusicTrack {
                        MiniMusicPill()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)).combined(with: .move(edge: .leading)))
                    } else {
                        Spacer()
                    }

                    Spacer()

                    MiniSystemPill()
                        .transition(.opacity.combined(with: .scale(scale: 0.9)).combined(with: .move(edge: .trailing)))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MiniMusicPill: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        HStack(spacing: 12) {
            // Small Artwork with subtle border
            AlbumArtThumbnail(size: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(state.nowPlayingTitle)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .tracking(0.5)
                Text(state.nowPlayingArtist)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
                .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
        )
        .shadow(color: .black.opacity(0.2), radius: 10)
    }
}

private struct MiniSystemPill: View {
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(Date(), format: .dateTime.hour().minute())
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .shadow(color: .white.opacity(0.1), radius: 4)
                
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
        .shadow(color: .black.opacity(0.2), radius: 10)
    }
}
