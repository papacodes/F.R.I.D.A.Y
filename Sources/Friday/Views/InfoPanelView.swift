import SwiftUI

struct InfoPanelView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            // Header
            Label("SYSTEM INFO", systemImage: "clock.fill")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.3))
                .tracking(1.2)

            // Clock - Beautiful Tahoe style
            TimelineView(.animation(minimumInterval: 1)) { _ in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Date(), format: .dateTime.hour().minute())
                        .font(.system(size: 32, weight: .thin, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .shadow(color: .white.opacity(0.15), radius: 5)

                    Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(0.5)
                }
            }

            Spacer().frame(height: 12)

            // Activity Feed (Live Events)
            ActivityFeedView()

            Spacer()

            // Model badge
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 4, height: 4)
                    .shadow(color: .cyan.opacity(0.5), radius: 2)
                Text(state.modelName.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(0.5)
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
