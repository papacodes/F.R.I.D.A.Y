import SwiftUI

/// Dynamic-island-style transient alert view.
/// Left side: icon representing the event.
/// Right side: visual indicator — bar (volume/brightness), ring (AirPods), battery (charging).
struct AlertNotchView: View {
    let alert: SystemAlert

    var body: some View {
        HStack(spacing: 0) {
            leftIcon
                .frame(width: 48, alignment: .leading)

            Spacer()

            rightIndicator
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Left

    private var leftIcon: some View {
        ZStack {
            Circle()
                .fill(alert.color.opacity(0.15))
                .frame(width: 26, height: 26)
            Image(systemName: alert.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(alert.color)
        }
    }

    // MARK: - Right

    @ViewBuilder
    private var rightIndicator: some View {
        switch alert.style {
        case .bar:
            BarIndicator(value: alert.value, color: alert.color)
        case .ring:
            RingIndicator(value: alert.value, color: alert.color)
        case .battery:
            BatteryLevelIndicator(value: alert.value, color: alert.color, charging: alert.isCharging)
        }
    }
}

// MARK: - Bar (volume / brightness)

private struct BarIndicator: View {
    let value: Float
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, geo.size.width * CGFloat(value)))
            }
        }
        .frame(height: 4)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: value)
    }
}

// MARK: - Ring (AirPods battery)

private struct RingIndicator: View {
    let value: Float
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(value))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value * 100))")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(width: 24, height: 24)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
    }
}

// MARK: - Battery (charging / battery level)

private struct BatteryLevelIndicator: View {
    let value: Float
    let color: Color
    let charging: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Battery shell
            ZStack(alignment: .leading) {
                // Outer shell
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color.opacity(0.5), lineWidth: 1)
                    .frame(width: 28, height: 13)
                // Nub
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(0.5))
                    .frame(width: 2.5, height: 6)
                    .offset(x: 29)
                // Fill
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: max(2, CGFloat(value) * 24), height: 9)
                    .padding(.leading, 2)
                // Bolt overlay when charging
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.black.opacity(0.7))
                }
            }
            .frame(width: 34)

            Text("\(Int(value * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
    }
}
