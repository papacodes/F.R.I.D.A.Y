import SwiftUI

/// State 2 — the horizontal alive bar.
/// Same height as the physical notch, expanded horizontally.
/// Shows: left indicator | status / track info | right indicator
struct HorizontalNotchView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        // Measure content and update state.standardWidth
        ZStack {
            HStack(spacing: 0) {
                leftSection
                    .frame(width: 80, alignment: .leading)
                
                centerSection
                    .frame(maxWidth: .infinity)
                
                rightSection
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            updateWidth(geo.size.width)
                        }
                        .onChange(of: geo.size.width) { newWidth in
                            updateWidth(newWidth)
                        }
                }
            )
        }
        .frame(maxHeight: .infinity)
    }
    
    private func updateWidth(_ w: CGFloat) {
        let minW: CGFloat = 520
        let target = max(minW, w)
        if abs(state.standardWidth - target) > 1 {
            DispatchQueue.main.async {
                state.standardWidth = target
            }
        }
    }

    // MARK: - Left: Orb or Music Waveform

    @ViewBuilder
    private var leftSection: some View {
        if state.isPlayingMusic && !state.isActive {
            // Music Mode
            MiniWaveform(isActive: true, color: state.albumAccentColor)
                .frame(width: 32, height: 14)
                .transition(.opacity.combined(with: .scale))
        } else {
            // AI / System Mode
            HStack(spacing: 10) {
                MiniOrbView(
                    isActive: state.isActive,
                    isError: state.isError,
                    isDevTask: state.isDevTaskRunning,
                    isConnected: state.isConnected
                )
                .padding(.leading, -4)
                
                if state.isActive {
                    MiniWaveform(isActive: true, color: activeColor)
                        .frame(width: 24, height: 12)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }

    // MARK: - Center: Status or Track Title

    @ViewBuilder
    private var centerSection: some View {
        HStack(spacing: 12) {
            if state.isError {
                errorContent
            } else if state.isDevTaskRunning {
                devTaskContent
            } else if state.isActive {
                activeContent
            } else if state.hasMusicTrack {
                musicContent
            } else {
                idleContent
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.isActive)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.isError)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.isDevTaskRunning)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.hasMusicTrack)
    }
    
    private var errorContent: some View {
        Text("CONNECTION ERROR")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundColor(.red)
            .tracking(1.0)
            .transition(.opacity)
    }
    
    private var devTaskContent: some View {
        HStack(spacing: 8) {
            Text("RUNNING TASK")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.orange)
                .tracking(1.0)
            
            ProgressView()
                .controlSize(.mini)
                .tint(.orange)
        }
        .transition(.opacity)
    }

    private var activeContent: some View {
        HStack(spacing: 8) {
            Text(activeLabel.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .tracking(1.0)

            if !state.transcript.isEmpty {
                Text(state.transcript)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var musicContent: some View {
        VStack(alignment: .center, spacing: 0) {
            Text(state.nowPlayingTitle.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .tracking(0.5)
            
            if !state.nowPlayingArtist.isEmpty {
                Text(state.nowPlayingArtist)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(state.albumAccentColor.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var idleContent: some View {
        Text("FRIDAY IS READY")
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundColor(.white.opacity(0.3))
            .tracking(1.5)
            .transition(.opacity)
    }

    // MARK: - Right: Battery or Album Art

    @ViewBuilder
    private var rightSection: some View {
        if state.hasMusicTrack && !state.isActive {
            AlbumArtThumbnail(size: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                .transition(.opacity.combined(with: .scale))
        } else {
            BatteryIndicator()
        }
    }

    // MARK: - Helpers

    private var activeLabel: String {
        if state.isListening { return "Listening" }
        if state.isThinking  { return "Thinking"  }
        if state.isSpeaking  { return "Speaking"  }
        return "Friday"
    }
    
    private var activeColor: Color {
        if state.isError { return .red }
        if state.isDevTaskRunning { return .orange }
        return .cyan
    }
}

// MARK: - Battery Indicator (Boring Notch style)

struct BatteryIndicator: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        HStack(spacing: 6) {
            Text("\(Int(state.batteryLevel))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()

            ZStack(alignment: .leading) {
                // Outer shell
                Image(systemName: "battery.0")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.white.opacity(0.25))
                    .frame(width: 24)

                // Fill
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(batteryColor)
                    .frame(width: CGFloat(state.batteryLevel / 100.0 * 18), height: 7)
                    .padding(.leading, 2)
                
                // Bolt if charging
                if state.isCharging || state.isPluggedIn {
                    Image(systemName: "bolt.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(width: 8, height: 8)
                        .offset(x: 8)
                }
            }
        }
    }

    private var batteryColor: Color {
        if state.isInLowPowerMode { return .yellow }
        if state.batteryLevel <= 20 { return .red }
        if state.isCharging || state.isPluggedIn { return .green }
        return .white.opacity(0.8)
    }
}

// MARK: - Mini orb (revamped for Liquid style)

private struct MiniOrbView: View {
    let isActive: Bool
    let isError: Bool
    let isDevTask: Bool
    let isConnected: Bool
    
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(glowColor.opacity(isActive ? 0.6 : (isConnected ? 0.25 : 0.1)))
                .frame(width: 28, height: 28)
                .blur(radius: 6)

            // Core
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [primaryColor.opacity(0.9), .clear], center: .center, startRadius: 0, endRadius: 10))
                
                Circle()
                    .fill(RadialGradient(colors: [secondaryColor.opacity(0.8), .clear], center: .center, startRadius: 0, endRadius: 8))
                    .offset(x: isActive ? 4 : 0)
                    .rotationEffect(.degrees(rotation))
                
                // White Center Shine
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(isActive ? 0.8 : (isConnected ? 0.4 : 0.2)), .clear], center: .center, startRadius: 0, endRadius: 6))
                    .frame(width: 12, height: 12)
                    .blur(radius: 1)
            }
            .frame(width: 18, height: 18)
            .offset(y: 2)
            .blendMode(.screen)
        }
        .scaleEffect(isActive ? 1.25 : 1.0)
        .saturation(isConnected ? 1.0 : 0.0)
        .opacity(isConnected ? 1.0 : 0.6)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActive)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isConnected)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
    
    private var glowColor: Color {
        if isError { return .red }
        if isDevTask { return .orange }
        return .cyan
    }
    
    private var primaryColor: Color {
        if isError { return Color(red: 1.0, green: 0, blue: 0) }
        if isDevTask { return .orange }
        return .cyan
    }
    
    private var secondaryColor: Color {
        if isError { return .red }
        if isDevTask { return .yellow }
        return Color(red: 0.7, green: 0.3, blue: 1.0)
    }
}
