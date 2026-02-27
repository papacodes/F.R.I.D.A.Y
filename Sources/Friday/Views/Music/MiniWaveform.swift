import SwiftUI

/// Four animated bars — used in the standard bar and home column music panel.
struct MiniWaveform: View {
    let isActive: Bool
    let color: Color
    @State private var animating = false

    private let heights: [CGFloat] = [6, 11, 8, 13]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<heights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(animating ? 0.85 : 0.3))
                    .frame(width: 2.5, height: animating ? heights[i] : 3)
                    .animation(
                        animating ? 
                        .easeInOut(duration: 0.4 + Double(i) * 0.07)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.1) :
                        .spring(response: 0.3, dampingFraction: 0.7),
                        value: animating
                    )
            }
        }
        .onAppear { animating = isActive }
        .onChange(of: isActive) { newValue in
            // Use withAnimation to ensure the state change triggers the transition back to static bars
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                animating = newValue
            }
        }
    }
}
