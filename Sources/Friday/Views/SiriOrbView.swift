import SwiftUI

struct SiriOrbView: View {
    let volume: Float
    let isThinking: Bool

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Background Shadow/Glow for Circular Definition
            Circle()
                .fill(Color.black.opacity(0.4))
                .frame(width: 80, height: 80)
                .blur(radius: 15)
                .scaleEffect(1.0 + CGFloat(volume) * 0.5)

            // Layer 1: Core glow
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [Color(red: 0, green: 0.8, blue: 1), Color.blue.opacity(0)]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 40
                ))
                .frame(width: 80, height: 80)
                .scaleEffect(1.0 + CGFloat(volume) * 2.5)
                .blur(radius: 8)

            // Layer 2: Secondary purple glow
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [Color.purple, Color.purple.opacity(0)]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 35
                ))
                .frame(width: 70, height: 70)
                .offset(x: isThinking ? 10 : 0)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(1.1 + CGFloat(volume) * 1.5)
                .blur(radius: 12)

            // Layer 3: Accent cyan
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [Color.cyan, Color.cyan.opacity(0)]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 30
                ))
                .frame(width: 60, height: 60)
                .offset(x: isThinking ? -10 : 0)
                .rotationEffect(.degrees(-rotation))
                .scaleEffect(1.0 + CGFloat(volume) * 3.0)
                .blur(radius: 10)
        }
        .opacity(0.9)
        .blendMode(.screen)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}
