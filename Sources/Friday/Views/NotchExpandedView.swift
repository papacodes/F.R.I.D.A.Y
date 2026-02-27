import SwiftUI

struct NotchExpandedView: View {
    @ObservedObject private var state = FridayState.shared
    @Namespace private var animation

    var body: some View {
        VStack(spacing: 0) {
            // Header: Pushed down and in significantly to avoid notch curves
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.isConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(state.modelName.uppercased())
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(1)
                }
                
                Spacer()
                
                Text(Date(), format: .dateTime.hour().minute())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 44) // Deep horizontal padding for header
            .padding(.top, 36)        // Pushed down below the physical notch base
            .frame(height: 50)

            // Main Stage Area
            ZStack {
                // Background Glow (Home only)
                if state.activeTab == .home {
                    Circle()
                        .fill(Color.cyan.opacity(0.08))
                        .frame(width: 250, height: 250)
                        .blur(radius: 50)
                        .offset(y: 10)
                }

                VStack(spacing: 0) {
                    // HERO SLOT: Constrained to keep everything centered
                    ZStack {
                        switch state.activeTab {
                        case .home:
                            FridayStatusPanelView(namespace: animation)
                        case .music:
                            MusicTabView(namespace: animation)
                        case .calendar:
                            CalendarTabView(namespace: animation)
                        default:
                            FridayStatusPanelView(namespace: animation)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140) // Fixed height to prevent pushing pills down
                    .padding(.top, 4)

                    Spacer()

                    // SIDE PILLS: Pushed in from corners to avoid curvature clipping
                    HStack(alignment: .bottom, spacing: 20) {
                        // Left Pill
                        Group {
                            if state.activeTab == .home {
                                if state.hasMusicTrack { MiniMusicPill(namespace: animation) }
                            } else if state.activeTab == .music {
                                MiniOrbPill(namespace: animation)
                            } else {
                                if state.hasMusicTrack { MiniMusicPill(namespace: animation) }
                            }
                        }
                        
                        Spacer()
                        
                        // Right Pill
                        Group {
                            if state.activeTab == .home {
                                MiniCalendarPill(namespace: animation)
                            } else if state.activeTab == .music {
                                MiniCalendarPill(namespace: animation)
                            } else {
                                MiniOrbPill(namespace: animation)
                            }
                        }
                    }
                    .padding(.horizontal, 48) // Very safe horizontal padding
                    .padding(.bottom, 36)     // Pushed up from the bottom edge
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 660, height: 280)
    }
}
