import SwiftUI

struct AlertNotchView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        Group {
            if let alert = state.activeAlert {
                HStack(spacing: 0) {
                    // LEFT SIDE: Icon
                    HStack {
                        Image(systemName: alert.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(alert.color)
                    }
                    .frame(width: 60, alignment: .leading)
                    
                    Spacer()
                    
                    // CENTER: Title/ID
                    Text(alert.id.uppercased())
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1.0)
                    
                    Spacer()
                    
                    // RIGHT SIDE: Visual Indicator (Bar, Ring, or Battery)
                    HStack {
                        if alert.style == .bar {
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 60, height: 4)
                                Capsule()
                                    .fill(alert.color)
                                    .frame(width: CGFloat(alert.value * 60.0), height: 4)
                            }
                        } else if alert.style == .ring {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 3)
                                Circle()
                                    .trim(from: 0, to: CGFloat(alert.value))
                                    .stroke(alert.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 20, height: 20)
                        } else if alert.style == .battery {
                            HStack(spacing: 4) {
                                Text("\(Int(alert.value * 100))\u{25}")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(alert.color)
                                Image(systemName: alert.isCharging ? "battery.100.bolt" : "battery.100")
                                    .foregroundColor(alert.color)
                            }
                        }
                    }
                    .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 24)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
