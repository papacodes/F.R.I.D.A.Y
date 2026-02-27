import SwiftUI

/// 5-bar mini equalizer shown inside the physical notch when Friday is collapsed.
/// Breathes slowly at idle; reacts to listening / thinking / speaking states.
struct NotchIdleIndicator: View {
    @ObservedObject private var state = FridayState.shared
    @State private var tick = false

    private let barCount  = 5
    private let barWidth: CGFloat  = 3
    private let barSpacing: CGFloat = 3

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor)
                    .frame(width: barWidth, height: targetHeight(for: i))
                    .animation(
                        .easeInOut(duration: duration(for: i))
                            .repeatForever(autoreverses: true)
                            .delay(delay(for: i)),
                        value: tick
                    )
            }
        }
        .onAppear { tick = true }
        .onChange(of: state.isActive) { _ in
            // Re-trigger animation on state change
            tick = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { tick = true }
        }
    }

    // MARK: - Per-bar computed properties

    private var barColor: Color {
        if state.isListening || state.isSpeaking { return Color.cyan }
        if state.isThinking                      { return .white.opacity(0.7) }
        return .white.opacity(0.3)
    }

    private func targetHeight(for i: Int) -> CGFloat {
        if !tick { return 3 }
        let pattern: [CGFloat]
        if state.isListening {
            pattern = [10, 18, 14, 20, 12]
        } else if state.isSpeaking {
            let vol = CGFloat(state.volume)
            pattern = [6 + vol*16, 8 + vol*12, 10 + vol*20, 8 + vol*14, 6 + vol*18]
        } else if state.isThinking {
            pattern = [6, 8, 14, 8, 6]
        } else {
            // Idle: barely-there breathing
            pattern = [4, 6, 8, 6, 4]
        }
        return pattern[i]
    }

    private func duration(for i: Int) -> Double {
        if state.isListening { return 0.25 + Double(i) * 0.04 }
        if state.isSpeaking  { return 0.20 + Double(i) * 0.03 }
        if state.isThinking  { return 0.60 + Double(i) * 0.10 }
        return 1.4 + Double(i) * 0.2  // idle: slow breath
    }

    private func delay(for i: Int) -> Double {
        if state.isActive { return Double(i) * 0.06 }
        return Double(i) * 0.15
    }
}
