import SwiftUI

/// Reverted to the simple, robust version of the expanded view.
struct NotchExpandedView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack(alignment: .center) {
                NotchTabBar()
                    .padding(.leading, 16)
                    .scaleEffect(0.95)
                
                Spacer()
                
                TimelineView(.animation(minimumInterval: 30)) { _ in
                    Text(Date(), format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .monospacedDigit()
                }
                .padding(.trailing, 16)
            }
            .frame(height: state.closedNotchSize.height + 10)
            .padding(.top, 4)

            // Main Content Area
            ZStack {
                Group {
                    switch state.activeTab {
                    case .home:      NotchHomeView()
                    case .music:     MusicTabView()
                    case .calendar:  CalendarTabView()
                    case .reminders: RemindersTabView()
                    case .notes:     NotesTabView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)),
                    removal:   .opacity
                ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.activeTab)
    }
}
