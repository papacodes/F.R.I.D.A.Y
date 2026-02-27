import SwiftUI

/// 5-bar mini equalizer shown inside the physical notch when Friday is collapsed.
/// Breathes slowly at idle; reacts to listening / thinking / speaking states.
struct NotchIdleIndicator: View {
    @ObservedObject private var state = FridayState.shared
    @State private var tick = false

    private let barCount  = 5
    private let barWidth: CGFloat  = 3.5
    private let barSpacing: CGFloat = 3.5

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.75)
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
        if state.isListening || state.isSpeaking { return Color.cyan.opacity(0.8) }
        if state.isThinking                      { return .white.opacity(0.65) }
        return .white.opacity(0.2)
    }

    private func targetHeight(for i: Int) -> CGFloat {
        if !tick { return 4 }
        let pattern: [CGFloat]
        if state.isListening {
            pattern = [12, 22, 16, 24, 14]
        } else if state.isSpeaking {
            let vol = CGFloat(state.volume)
            pattern = [8 + vol*14, 10 + vol*18, 12 + vol*24, 10 + vol*16, 8 + vol*20]
        } else if state.isThinking {
            pattern = [8, 10, 16, 10, 8]
        } else {
            // Idle: breathing
            pattern = [4, 7, 9, 7, 4]
        }
        return pattern[i]
    }

    private func duration(for i: Int) -> Double {
        if state.isListening { return 0.22 + Double(i) * 0.03 }
        if state.isSpeaking  { return 0.18 + Double(i) * 0.02 }
        if state.isThinking  { return 0.55 + Double(i) * 0.08 }
        return 1.2 + Double(i) * 0.15  // idle
    }

    private func delay(for i: Int) -> Double {
        if state.isActive { return Double(i) * 0.05 }
        return Double(i) * 0.12
    }
}
