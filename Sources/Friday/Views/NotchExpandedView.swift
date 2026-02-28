import SwiftUI

struct NotchExpandedView: View {
    @ObservedObject private var state = FridayState.shared
    @Namespace private var animation

    var body: some View {
        ZStack(alignment: .top) {
            // Layer 0: Background Glow (Home only)
            if state.activeTab == .home {
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(y: 40)
                    .transition(.opacity)
            }

            // Layer 1: Layout Skeleton (Header and Bottom Pills)
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    // Left: Model Status
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
                    
                    // Right: Battery & Time
                    HStack(spacing: 16) {
                        BatteryIndicator()
                            .scaleEffect(0.85)
                        
                        Text(Date(), format: .dateTime.hour().minute())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
                .padding(.horizontal, 44)
                .padding(.top, 36)
                .frame(height: 50)

                Spacer()

                // Side Pills: Anchored to bottom
                HStack(alignment: .bottom, spacing: 20) {
                    Group {
                        if state.activeTab == .home {
                            if state.hasMusicTrack { MiniMusicPill(namespace: animation) }
                        } else if state.activeTab == .music {
                            MiniOrbPill(namespace: animation)
                        } else {
                            if state.hasMusicTrack { MiniMusicPill(namespace: animation) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                    
                    Group {
                        if state.activeTab == .home {
                            MiniCalendarPill(namespace: animation)
                        } else if state.activeTab == .music {
                            MiniCalendarPill(namespace: animation)
                        } else {
                            MiniOrbPill(namespace: animation)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 36)
            }

            // Layer 2: Main Hero Component
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
            .frame(width: 660, height: 280)
            .offset(y: 20)
            .zIndex(1)
        }
        .frame(width: 660, height: 280)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: state.activeTab)
    }
}
