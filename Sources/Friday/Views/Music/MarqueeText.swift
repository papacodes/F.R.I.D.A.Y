import SwiftUI

/// Scrolling marquee text. Static when text fits; scrolls continuously when it overflows.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var speed: CGFloat = 28  // points per second

    @State private var textWidth: CGFloat = 0
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            let overflows = textWidth > geo.size.width

            ZStack(alignment: .leading) {
                // Invisible measurer — always rendered so textWidth stays current
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(key: MarqueeWidthKey.self, value: inner.size.width)
                        }
                    )

                if overflows {
                    HStack(spacing: 32) {
                        Text(text).font(font).foregroundColor(color).fixedSize()
                        Text(text).font(font).foregroundColor(color).fixedSize()
                    }
                    .offset(x: animate ? -(textWidth + 32) : 0)
                    .animation(
                        animate
                            ? .linear(duration: Double(textWidth + 32) / speed)
                                .repeatForever(autoreverses: false)
                            : .none,
                        value: animate
                    )
                } else {
                    Text(text)
                        .font(font)
                        .foregroundColor(color)
                        .lineLimit(1)
                }
            }
            .clipped()
        }
        .clipped()
        .onPreferenceChange(MarqueeWidthKey.self) { width in
            textWidth = width
        }
        .onAppear { scheduleScroll() }
        .onChange(of: text) {
            animate = false
            scheduleScroll()
        }
    }

    private func scheduleScroll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            animate = true
        }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
