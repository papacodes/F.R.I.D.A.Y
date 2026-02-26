import SwiftUI

struct ThinkingView: View {
    var color: Color = .white
    @State private var animating = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color.opacity(0.85))
                    .frame(width: 7, height: 7)
                    .offset(y: animating ? -8 : 0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
