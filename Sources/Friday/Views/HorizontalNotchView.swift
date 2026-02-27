import SwiftUI

/// State 2 — the horizontal alive bar.
/// Same height as the physical notch, expanded to 440pt.
/// Shows: left indicator | status / track info | clock
struct HorizontalNotchView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        HStack(spacing: 0) {
            leftSection
                .frame(width: 52)

            divider

            centerSection
                .frame(maxWidth: .infinity)

            divider

            rightSection
                .frame(width: 60)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left: album art thumbnail or orb

    @ViewBuilder
    private var leftSection: some View {
        if state.hasMusicTrack && !state.isActive {
            AlbumArtThumbnail(size: 20)
                .transition(.opacity)
        } else {
            MiniOrbView(isActive: state.isActive)
        }
    }

    // MARK: - Center

    @ViewBuilder
    private var centerSection: some View {
        if state.isActive {
            HStack(spacing: 8) {
                MiniWaveform(isActive: true, color: .cyan)
                    .frame(width: 40, height: 14)

                Text(activeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)

                if !state.transcript.isEmpty {
                    Text("· \(state.transcript)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        } else if state.hasMusicTrack {
            HStack(spacing: 8) {
                if state.isPlayingMusic {
                    MiniWaveform(isActive: true, color: state.albumAccentColor)
                        .frame(width: 28, height: 14)
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(state.nowPlayingTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(state.nowPlayingArtist)
                        .font(.system(size: 10))
                        .foregroundColor(state.albumAccentColor.opacity(0.75))
                        .lineLimit(1)
                }
            }
        } else {
            HStack(spacing: 6) {
                Text("F·R·I·D·A·Y")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(2)
                Text("·")
                    .foregroundColor(.white.opacity(0.15))
                Text("Ready")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
    }

    // MARK: - Right: compact clock

    private var rightSection: some View {
        TimelineView(.animation(minimumInterval: 30)) { _ in
            Text(Date(), format: .dateTime.hour().minute())
                .font(.system(size: 12, weight: .light, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .monospacedDigit()
        }
    }

    // MARK: - Helpers

    private var activeLabel: String {
        if state.isListening { return "Listening" }
        if state.isThinking  { return "Thinking"  }
        if state.isSpeaking  { return "Speaking"  }
        return "Working"
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 10)
    }
}

// MARK: - Mini orb

private struct MiniOrbView: View {
    let isActive: Bool
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.cyan.opacity(isActive ? 0.9 : 0.4), .clear],
                        center: .center, startRadius: 0, endRadius: 11
                    )
                )
                .frame(width: 22, height: 22)
                .blur(radius: 2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.purple.opacity(0.6), .clear],
                        center: .center, startRadius: 0, endRadius: 8
                    )
                )
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(rotation))
                .blur(radius: 3)
        }
        .blendMode(.screen)
        .scaleEffect(isActive ? 1.15 : 0.85)
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isActive)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}
