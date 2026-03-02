import SwiftUI

struct ExpandedViewActivity: View {
    @ObservedObject private var state = FridayState.shared
    var namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("ACTIVITY")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(2.5)

                Spacer()

                if !state.activityHistory.isEmpty {
                    Text("\(state.activityHistory.count) events")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.18))
                }
            }
            .padding(.bottom, 14)

            if state.activityHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.1))
                    Text("No recent activity")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(state.activityHistory) { item in
                            ActivityRowView(item: item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 52)
        .padding(.top, 68)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ActivityRowView: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(item.type.color)
                .frame(width: 28, height: 28)
                .background(item.type.color.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(item.timestamp, style: .relative)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.18))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
