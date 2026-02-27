import SwiftUI

struct NotchTabBar: View {
    @ObservedObject private var state = FridayState.shared
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { tab in
                TabBarButton(tab: tab, isActive: state.activeTab == tab, namespace: tabNamespace)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            state.activeTab = tab
                        }
                    }
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
        )
    }
}

private struct TabBarButton: View {
    let tab: NotchTab
    let isActive: Bool
    let namespace: Namespace.ID

    var body: some View {
        ZStack {
            if isActive {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .matchedGeometryEffect(id: "tabBackground", in: namespace)
                    .frame(height: 28)
            }
            
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .bold))
                
                if isActive {
                    Text(tab.label.uppercased())
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .tracking(0.5)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundColor(isActive ? .white : .white.opacity(0.4))
            .padding(.horizontal, 10)
        }
        .frame(height: 28)
        .contentShape(Capsule())
    }
}
