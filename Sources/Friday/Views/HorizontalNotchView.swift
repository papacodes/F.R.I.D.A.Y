import SwiftUI

// MARK: - Component 1: The Rigid Mini View (Top Row)
struct NotchMiniView<Left: View, Right: View>: View {
    let left: Left
    let right: Right
    
    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: 80, alignment: .leading)
            Spacer()
            right.frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: 32) // Fixed physical notch height
    }
}

// MARK: - Component 2: The Rigid Expanded View (Two Rows)
struct NotchExpandedMiniView<Left: View, Right: View>: View {
    let left: Left
    let right: Right
    let text: String
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            // Reuses Component 1 exactly - This MUST NOT MOVE
            NotchMiniView(left: left, right: right)
            
            // Second Row: The revealed text (Slide down)
            HStack {
                Text(text)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(1.0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Master Coordinator
struct HorizontalNotchView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        Group {
            if let alert = state.activeAlert {
                alertView(for: alert)
            } else if state.isPlayingMusic && !state.isActive {
                musicView
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - The "1 Line Change" Alert Router
    @ViewBuilder
    private func alertView(for alert: SystemAlert) -> some View {
        let left  = alertLeftWidget(alert)
        let right = alertRightWidget(alert)
        let text  = alertText(alert)

        if state.displayState == .miniExpanded {
            NotchExpandedMiniView(left: left, right: right, text: text)
        } else {
            NotchMiniView(left: left, right: right)
        }
    }

    // MARK: - Widget Definitions (Easy to change icons/widgets here)

    @ViewBuilder
    private func alertLeftWidget(_ alert: SystemAlert) -> some View {
        if alert.id == "friday" {
            MiniOrbView(isActive: state.isActive, isError: state.isError, isDevTask: state.isDevTaskRunning, isConnected: state.isConnected).scaleEffect(1.1)
        } else {
            Image(systemName: alert.icon).font(.system(size: 14, weight: .bold)).foregroundColor(alert.color)
        }
    }

    @ViewBuilder
    private func alertRightWidget(_ alert: SystemAlert) -> some View {
        if alert.id == "battery" || alert.id == "airpods" || alert.id == "friday" {
            CompactBatteryRing(value: alert.value, color: alert.color, isCharging: alert.isCharging)
        } else if alert.style == .bar {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1)).frame(width: 60, height: 4)
                Capsule().fill(alert.color).frame(width: CGFloat(alert.value * 60.0), height: 4)
            }
        } else {
            CompactBatteryRing(value: alert.value, color: alert.color, isCharging: false)
        }
    }

    private func alertText(_ alert: SystemAlert) -> String {
        if alert.id == "airpods" { return state.peripheralManager.airPodsState.name?.uppercased() ?? "AIRPODS" }
        if alert.id == "battery" { return alert.isCharging ? "CHARGING" : "BATTERY" }
        return "\(alert.id.uppercased()) \(Int(alert.value * 100))%"
    }

    private var musicView: some View {
        NotchMiniView(
            left: MiniWaveform(isActive: true, color: .white).frame(width: 32, height: 14),
            right: AlbumArtThumbnail(size: 22).clipShape(RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        )
    }

    private var idleView: some View {
        NotchMiniView(
            left: MiniOrbView(isActive: state.isActive, isError: state.isError, isDevTask: state.isDevTaskRunning, isConnected: state.isConnected).padding(.leading, -4.0),
            right: BatteryIndicator()
        )
    }
}

// MARK: - Reusable Mini Battery Widget
struct CompactBatteryRing: View {
    let value: Float
    let color: Color
    let isCharging: Bool
    
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 2.5)
            Circle().trim(from: 0, to: CGFloat(value)).stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            if isCharging {
                Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold)).foregroundColor(.green)
            }
        }
        .frame(width: 18, height: 18)
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
                    Image(systemName: "leaf.fill").resizable().aspectRatio(contentMode: .fit).foregroundColor(.yellow).frame(width: 8, height: 8).offset(x: 25)
                }
                if state.isCharging || state.isPluggedIn {
                    Image(systemName: "bolt.fill").resizable().aspectRatio(contentMode: .fit).foregroundColor(.green).frame(width: 8, height: 8).offset(x: 25)
                }
            }
        }
        .onAppear { if isCritical { startPulsing() } }
        .onChange(of: state.batteryLevel) { level in
            if level <= 10 { startPulsing() } else { isPulsing = false }
        }
    }

    private func startPulsing() { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isPulsing = true } }
    private var isCritical: Bool { state.batteryLevel <= 10 && !state.isCharging }
    private var batteryColor: Color {
        if state.isInLowPowerMode { return .yellow }
        if state.isCharging || state.isPluggedIn { return .green }
        if state.batteryLevel <= 10 { return .red }
        if state.batteryLevel <= 20 { return .orange }
        return .white.opacity(0.8)
    }
}
