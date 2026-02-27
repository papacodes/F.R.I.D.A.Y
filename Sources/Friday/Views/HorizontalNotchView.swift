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
                .frame(width: 64)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left: album art thumbnail or orb

    @ViewBuilder
    private var leftSection: some View {
        if state.hasMusicTrack && !state.isActive {
            AlbumArtThumbnail(size: 20)
                .transition(.opacity.combined(with: .scale))
        } else {
            MiniOrbView(isActive: state.isActive)
        }
    }

    // MARK: - Center

    @ViewBuilder
    private var centerSection: some View {
        HStack(spacing: 10) {
            if state.isActive {
                activeContent
            } else if state.hasMusicTrack {
                musicContent
            } else {
                idleContent
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.isActive)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.hasMusicTrack)
    }

    private var activeContent: some View {
        HStack(spacing: 8) {
            MiniWaveform(isActive: true, color: .cyan)
                .frame(width: 36, height: 14)

            Text(activeLabel.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .tracking(0.5)

            if !state.transcript.isEmpty {
                Text(state.transcript)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var musicContent: some View {
        HStack(spacing: 10) {
            if state.isPlayingMusic {
                MiniWaveform(isActive: true, color: state.albumAccentColor)
                    .frame(width: 24, height: 12)
            } else {
                Image(systemName: "pause.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(state.nowPlayingTitle)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(state.nowPlayingArtist)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(state.albumAccentColor.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var idleContent: some View {
        HStack(spacing: 8) {
            Text("F·R·I·D·A·Y")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1.5)
            
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 3, height: 3)

            Text("READY")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.15))
                .tracking(1.0)
        }
        .transition(.opacity)
    }

    // MARK: - Right: compact clock

    private var rightSection: some View {
        TimelineView(.animation(minimumInterval: 30)) { _ in
            Text(Date(), format: .dateTime.hour().minute())
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
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
            .fill(Color.white.opacity(0.12))
            .frame(width: 0.5, height: 14)
            .padding(.horizontal, 8)
    }
}

// MARK: - Mini orb (revamped for Liquid style)

private struct MiniOrbView: View {
    let isActive: Bool
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(Color.cyan.opacity(isActive ? 0.3 : 0.1))
                .frame(width: 24, height: 24)
                .blur(radius: 4)

            // Core
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.cyan.opacity(0.8), .clear], center: .center, startRadius: 0, endRadius: 10))
                
                Circle()
                    .fill(RadialGradient(colors: [.purple.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 8))
                    .offset(x: isActive ? 4 : 0)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 18, height: 18)
            .blendMode(.screen)
        }
        .scaleEffect(isActive ? 1.1 : 0.9)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActive)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}
