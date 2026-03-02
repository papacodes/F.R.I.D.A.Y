import SwiftUI

struct ActivityFeedView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if state.activityHistory.isEmpty {
                Text("NO RECENT ACTIVITY")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.15))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 10)
            } else {
                // Show 4 most recent — oldest auto-drop as new ones arrive
                ForEach(state.activityHistory.prefix(4)) { item in
                    ActivityCard(item: item)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.activityHistory)
    }
}

private struct ActivityCard: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: item.type.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(item.type.color)
                .frame(width: 20, height: 20)
                .background(item.type.color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
        .frame(maxWidth: 180, alignment: .trailing)
    }
}
