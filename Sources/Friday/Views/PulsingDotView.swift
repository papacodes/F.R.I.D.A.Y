import SwiftUI

struct PulsingDotView: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 18, height: 18)
                .scaleEffect(pulsing ? 1.0 : 0.6)
                .opacity(pulsing ? 0.0 : 0.5)
                .animation(
                    .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                    value: pulsing
                )

            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
        }
        .onAppear { pulsing = true }
    }
}
