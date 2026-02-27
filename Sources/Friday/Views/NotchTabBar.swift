import SwiftUI

struct NotchTabBar: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NotchTab.allCases) { tab in
                TabBarButton(tab: tab, isActive: state.activeTab == tab)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            state.activeTab = tab
                        }
                    }
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct TabBarButton: View {
    let tab: NotchTab
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: tab.icon)
                .font(.system(size: isActive ? 14 : 13, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : .white.opacity(0.3))
                .scaleEffect(isActive ? 1.05 : 1.0)

            // Active dot
            Circle()
                .fill(Color.cyan)
                .frame(width: 3, height: 3)
                .opacity(isActive ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
    }
}
