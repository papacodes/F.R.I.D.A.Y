import SwiftUI

struct WaveformView: View {
    var isActive: Bool
    var color: Color = .white

    @State private var animating = false

    private let barCount = 20
    private let barHeights: [CGFloat] = [
        6, 14, 22, 32, 26, 40, 18, 44, 30, 38,
        42, 28, 36, 20, 38, 32, 24, 16, 10, 6
    ]
    private let barWidth: CGFloat = 3.5
    private let barSpacing: CGFloat = 3.5

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(animating ? 0.9 : 0.25))
                    .frame(width: barWidth)
                    .frame(height: animating ? barHeights[index] : 3)
                    .animation(
                        .easeInOut(duration: animationDuration(for: index))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.04),
                        value: animating
                    )
            }
        }
        .onAppear { animating = isActive }
        .onChange(of: isActive) { active in animating = active }
    }

    private func animationDuration(for index: Int) -> Double {
        0.45 + Double(index % 5) * 0.08
    }
}
