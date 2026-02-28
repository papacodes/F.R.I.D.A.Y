import SwiftUI

/// State 1 — the "Mini" pill.
/// Expands the notch horizontally. Shows icon on the left, status on the right. No text.
struct MiniNotchView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: Icon / Orb
            leftSection
                .frame(width: 48, alignment: .leading)
            
            Spacer()
            
            // RIGHT: Status (Battery / Alert Indicator)
            rightSection
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var leftSection: some View {
        if let alert = state.activeAlert {
            if alert.id == "friday" {
                MiniOrbView(
                    isActive: state.isActive,
                    isError: state.isError,
                    isDevTask: state.isDevTaskRunning,
                    isConnected: state.isConnected
                )
                .scaleEffect(0.8)
                .transition(.opacity)
            } else {
                Image(systemName: alert.icon)
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(alert.color)
                    .transition(.opacity.combined(with: .scale))
            }
        } else if state.isHovering {
            // Hover-triggered presence
            MiniOrbView(
                isActive: state.isActive,
                isError: state.isError,
                isDevTask: state.isDevTaskRunning,
                isConnected: state.isConnected
            )
            .scaleEffect(0.8)
            .transition(.opacity)
        } else {
            // Dormant / No Alert: Minimal indicator if needed, but per rules, should be empty
            EmptyView()
        }
    }

    @ViewBuilder
    private var rightSection: some View {
        if let alert = state.activeAlert {
            if alert.id == "friday" {
                CompactBatteryRing()
                    .transition(.opacity)
            } else {
                alertIndicator(alert)
                    .transition(.opacity.combined(with: .scale))
            }
        } else if state.isHovering {
            CompactBatteryRing()
                .transition(.opacity)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func alertIndicator(_ alert: SystemAlert) -> some View {
        if alert.id == "volume" || alert.id == "brightness" {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 44, height: 4)
                Capsule()
                    .fill(alert.color)
                    .frame(width: CGFloat(alert.value * 44.0), height: 4)
            }
        } else {
            // Ring / Battery style
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(alert.value))
                    .stroke(alert.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
        }
    }
}

struct CompactBatteryRing: View {
    @ObservedObject private var state = FridayState.shared
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(state.batteryLevel / 100.0))
                .stroke(batteryColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            if state.isCharging || state.isPluggedIn {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.green)
            }
        }
        .frame(width: 18, height: 18)
    }

    private var batteryColor: Color {
        if state.isCharging || state.isPluggedIn { return .green }
        if state.batteryLevel <= 20 { return .orange }
        return .white.opacity(0.6)
    }
}
