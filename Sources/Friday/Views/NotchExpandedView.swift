import SwiftUI

/// The full expanded view — sits inside the NotchShape, always 640pt wide.
/// Top padding clears the physical notch camera area; tab bar anchors the bottom.
struct NotchExpandedView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Push content below the physical notch (camera/sensor area)
            Spacer().frame(height: state.closedNotchSize.height + 6)

            // Main content
            Group {
                switch state.activeTab {
                case .home:      NotchHomeView()
                case .music:     MusicTabView()
                case .calendar:  CalendarTabView()
                case .reminders: RemindersTabView()
                case .notes:     NotesTabView()
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.activeTab)

            // Tab bar
            Divider()
                .background(Color.white.opacity(0.07))
                .padding(.horizontal, 16)

            NotchTabBar()
                .frame(height: 44)
                .padding(.horizontal, 8)
        }
    }
}
