import SwiftUI

/// State 2 — the horizontal alive bar.
/// Same height as the physical notch, expanded horizontally.
/// Shows: left indicator | status / track info | right indicator
struct HorizontalNotchView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
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

    // MARK: - Left Section

    @ViewBuilder
    private var leftSection: some View {
        if let alert = state.activeAlert {
            if alert.id == "friday" {
                MiniOrbView(isActive: state.isActive, isError: state.isError, isDevTask: state.isDevTaskRunning, isConnected: state.isConnected)
                    .scaleEffect(1.1)
            } else {
                Image(systemName: alert.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(alert.color)
            }
        } else if state.isPlayingMusic && !state.isActive {
            MiniWaveform(isActive: true, color: .white)
                .frame(width: 32, height: 14)
                .transition(.opacity.combined(with: .scale))
        } else {
            HStack(spacing: 10) {
                MiniOrbView(isActive: state.isActive, isError: state.isError, isDevTask: state.isDevTaskRunning, isConnected: state.isConnected)
                    .padding(.leading, -4)
                if state.isActive {
                    MiniWaveform(isActive: true, color: activeColor)
                        .frame(width: 24, height: 12)
                }
            }
        }
    }

    // MARK: - Center Section

    @ViewBuilder
    private var centerSection: some View {
        HStack(spacing: 12) {
            if let alert = state.activeAlert {
                let label: String = {
                    if alert.id == "airpods" { return state.peripheralManager.airPodsState.name?.uppercased() ?? "AIRPODS" }
                    if alert.style == .bar || alert.style == .ring || alert.style == .battery {
                        return "\(alert.id.uppercased()) \(Int(alert.value * 100))%"
                    }
                    return alert.id.uppercased()
                }()
                Text(label)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(1.0)
            } else if state.isError {
                Text("CONNECTION ERROR").font(.system(size: 10, weight: .black, design: .rounded)).foregroundColor(.red).tracking(1.0)
            } else if state.isDevTaskRunning {
                HStack(spacing: 8) {
                    Text("RUNNING TASK").font(.system(size: 10, weight: .black, design: .rounded)).foregroundColor(.orange).tracking(1.0)
                    ProgressView().controlSize(.mini).tint(.orange)
                }
            } else if state.isActive {
                HStack(spacing: 8) {
                    Text(activeLabel.uppercased()).font(.system(size: 10, weight: .black, design: .rounded)).foregroundColor(.white).tracking(1.0)
                    if !state.transcript.isEmpty {
                        Text(state.transcript).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.45)).lineLimit(1)
                    }
                }
            } else if state.isPlayingMusic {
                VStack(alignment: .center, spacing: 0) {
                    Text(state.nowPlayingTitle.uppercased()).font(.system(size: 10, weight: .black, design: .rounded)).foregroundColor(.white).lineLimit(1)
                    if !state.nowPlayingArtist.isEmpty {
                        Text(state.nowPlayingArtist).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                    }
                }
            } else {
                Text("FRIDAY IS READY").font(.system(size: 10, weight: .black, design: .rounded)).foregroundColor(.white.opacity(0.3)).tracking(1.5)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.isActive)
    }

    // MARK: - Right Section

    @ViewBuilder
    private var rightSection: some View {
        if let alert = state.activeAlert {
            if alert.style == .bar {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(width: 60, height: 4)
                    Capsule().fill(alert.color).frame(width: CGFloat(alert.value * 60.0), height: 4)
                }
            } else if alert.style == .ring {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 3)
                    Circle().trim(from: 0, to: CGFloat(alert.value)).stroke(alert.color, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                }.frame(width: 20, height: 20)
            } else {
                BatteryIndicator()
            }
        } else if state.isPlayingMusic && !state.isActive {
            AlbumArtThumbnail(size: 22).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        } else {
            BatteryIndicator()
        }
    }

    private var activeLabel: String {
        if state.isListening { return "Listening" }
        if state.isThinking  { return "Thinking" }
        if state.isSpeaking  { return "Speaking" }
        return "Friday"
    }
    
    private var activeColor: Color {
        if state.isError { return .red }
        if state.isDevTaskRunning { return .orange }
        return .cyan
    }
}

// MARK: - Battery Indicator

struct BatteryIndicator: View {
    @ObservedObject private var state = FridayState.shared
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Text("\(Int(state.batteryLevel))\u{25}")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(batteryColor)
                .monospacedDigit()
                .opacity(isCritical ? (isPulsing ? 1.0 : 0.4) : 1.0)

            ZStack(alignment: .leading) {
                Image(systemName: isCritical ? "battery.0" : "battery.100")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(batteryColor.opacity(isCritical ? (isPulsing ? 0.6 : 0.2) : 0.25))
                    .frame(width: 22)

                if !isCritical {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(batteryColor)
                        .frame(width: CGFloat(state.batteryLevel / 100.0 * 16), height: 6)
                        .padding(.leading, 2)
                } else {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(batteryColor)
                        .frame(width: 3, height: 6)
                        .padding(.leading, 2)
                        .opacity(isPulsing ? 1.0 : 0.5)
                }
                
                if state.isInLowPowerMode {
                    Image(systemName: "leaf.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.yellow)
                        .frame(width: 8, height: 8)
                        .offset(x: 25)
                }
                if state.isCharging || state.isPluggedIn {
                    Image(systemName: "bolt.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.green)
                        .frame(width: 8, height: 8)
                        .offset(x: 25)
                }
            }
        }
        .onAppear { if isCritical { startPulsing() } }
        .onChange(of: state.batteryLevel) { level in
            if level <= 10 { startPulsing() } else { isPulsing = false }
        }
    }

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }

    private var isCritical: Bool { state.batteryLevel <= 10 && !state.isCharging }

    private var batteryColor: Color {
        if state.isInLowPowerMode { return .yellow }
        if state.isCharging || state.isPluggedIn { return .green }
        if state.batteryLevel <= 10 { return .red }
        if state.batteryLevel <= 20 { return .orange }
        return .white.opacity(0.8)
    }

}

// MARK: - Mini Orb

struct MiniOrbView: View {
    let isActive: Bool
    let isError: Bool
    let isDevTask: Bool
    let isConnected: Bool
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(glowColor.opacity(isActive ? 0.6 : (isConnected ? 0.25 : 0.1)))
                .frame(width: 28, height: 28)
                .blur(radius: 6)
            ZStack {
                Circle().fill(RadialGradient(colors: [primaryColor.opacity(0.9), .clear], center: .center, startRadius: 0, endRadius: 10))
                Circle().fill(RadialGradient(colors: [secondaryColor.opacity(0.8), .clear], center: .center, startRadius: 0, endRadius: 8))
                    .offset(x: isActive ? 4 : 0).rotationEffect(.degrees(rotation))
                Circle().fill(RadialGradient(colors: [.white.opacity(isActive ? 0.8 : (isConnected ? 0.4 : 0.2)), .clear], center: .center, startRadius: 0, endRadius: 6))
                    .frame(width: 12, height: 12).blur(radius: 1)
            }
            .frame(width: 18, height: 18).offset(y: 2).blendMode(.screen)
        }
        .scaleEffect(isActive ? 1.25 : 1.0)
        .onAppear { withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { rotation = 360 } }
    }
    
    private var glowColor: Color { isError ? .red : (isDevTask ? .orange : .cyan) }
    private var primaryColor: Color { isError ? .red : (isDevTask ? .orange : .cyan) }
    private var secondaryColor: Color { isError ? .red : (isDevTask ? .yellow : Color(red: 0.7, green: 0.3, blue: 1.0)) }
}
