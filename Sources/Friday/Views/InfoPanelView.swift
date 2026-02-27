import SwiftUI

struct InfoPanelView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Header
            Label("INFO", systemImage: "clock")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1.5)

            // Clock
            TimelineView(.animation(minimumInterval: 1)) { _ in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Date(), format: .dateTime.hour().minute())
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()

                    Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                }
            }

            Spacer()

            // Model badge
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 5, height: 5)
                Text(state.modelName)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
