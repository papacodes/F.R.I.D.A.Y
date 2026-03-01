import SwiftUI

struct SiriOrbView: View {
    let volume: Float
    let isThinking: Bool
    let isError: Bool
    let isDevTask: Bool
    let isConnected: Bool

    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Background blur/glow
            Circle()
                .fill(glowColor.opacity(isConnected ? 0.15 : 0.05))
                .frame(width: 90, height: 90)
                .blur(radius: 20)

            // Dynamic Blobs
            ZStack {
                // Layer 1: Core
                orbBlob(color: primaryColor, 
                        scale: 1.2 + CGFloat(volume) * 1.5, 
                        offset: isThinking ? 5 : 0, 
                        rotation: rotation)
                
                // Layer 2: Highlight
                orbBlob(color: secondaryColor, 
                        scale: 1.0 + CGFloat(volume) * 2.5, 
                        offset: isThinking ? -8 : 0, 
                        rotation: -rotation * 1.2)
                
                // Layer 3: Accent
                orbBlob(color: accentColor, 
                        scale: 1.1 + CGFloat(volume) * 1.8, 
                        offset: isThinking ? 10 : 2, 
                        rotation: rotation * 0.7)
                
                // Layer 4: White (Center Shine)
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [.white.opacity(isConnected ? 0.5 : 0.2), .white.opacity(0)]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 20
                    ))
                    .frame(width: 40, height: 40)
                    .scaleEffect(0.8 + CGFloat(volume) * 1.2)
                    .blur(radius: 4)
            }
            .blendMode(.screen)
        }
        .frame(width: 100, height: 100)
        .saturation(isConnected ? 1.0 : 0.0)
        .opacity(isConnected ? 1.0 : 0.5)
        // Smoothly animate orb contraction when volume snaps to 0 (e.g. on turnComplete)
        .animation(.easeOut(duration: 0.35), value: volume)
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulse = 1.1
            }
        }
    }

    @ViewBuilder
    private func orbBlob(color: Color, scale: CGFloat, offset: CGFloat, rotation: Double) -> some View {
        Circle()
            .fill(RadialGradient(
                gradient: Gradient(colors: [color.opacity(0.7), color.opacity(0)]),
                center: .center,
                startRadius: 0,
                endRadius: 40
            ))
            .frame(width: 80, height: 80)
            .offset(x: offset, y: isThinking ? offset : 0)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale * pulse)
            .blur(radius: 10)
    }
    
    /// Waiting = connected, nothing happening. Lowest priority — checked last.
    private var isWaiting: Bool {
        isConnected && !isThinking && !isError && !isDevTask && volume < 0.01
    }

    private var glowColor: Color {
        if isError   { return .red }
        if isDevTask { return .orange }
        if isWaiting { return .green }
        return .cyan
    }

    private var primaryColor: Color {
        if isError   { return Color(red: 0.8, green: 0, blue: 0) }
        if isDevTask { return .orange }
        if isWaiting { return Color(red: 0.1, green: 0.75, blue: 0.35) }
        return Color(red: 0, green: 0.4, blue: 1)
    }

    private var secondaryColor: Color {
        if isError   { return .red }
        if isDevTask { return .yellow }
        if isWaiting { return Color(red: 0.0, green: 0.55, blue: 0.25) }
        return .cyan
    }

    private var accentColor: Color {
        if isError   { return .orange }
        if isDevTask { return .red }
        if isWaiting { return Color(red: 0.2, green: 0.9, blue: 0.5) }
        return .purple
    }
}
