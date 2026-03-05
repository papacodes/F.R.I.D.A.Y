import SwiftUI

struct NotchExpandedView: View {
    @ObservedObject private var state = FridayState.shared
    @Namespace private var animation

    var body: some View {
        ZStack(alignment: .top) {
            // Layer 0: Background Glow (Home only) — colour tracks state
            if state.activeTab == .home {
                let glowColor: Color = state.isError ? .red : (state.isThinking ? .purple : .cyan)
                Circle()
                    .fill(glowColor.opacity(0.12))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(y: 40)
                    .transition(.opacity)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.isError)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.isThinking)
            }

            // Layer 1: Header bar — model badge, battery, time, dismiss
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    // Left: Model Status
                    Button(action: { withAnimation { state.activeTab = .assistant } }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(state.isConnected ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                            Text(state.modelName.uppercased())
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.35))
                                .tracking(1)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Right: Battery, Time, and X dismiss
                    HStack(spacing: 12) {
                        BatteryIndicator()
                            .scaleEffect(0.85)

                        Text(Date(), format: .dateTime.hour().minute())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.35))

                        Button(action: {
                            NotificationCenter.default.post(name: .fridayCollapse, object: nil)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 44)
                .padding(.top, 36)
                .frame(height: 50)

                Spacer()
            }

            // Layer 2: Main Hero Component
            ZStack {
                if state.activeTab == .home {
                    switch state.activeDetail {
                    case .activity:
                        ExpandedViewActivity(namespace: animation)
                    case .weather:
                        WeatherTabView()
                    case .none:
                        FridayStatusPanelView(namespace: animation)
                    }
                } else if state.activeTab == .music {
                    MusicTabView(namespace: animation)
                        .padding(.top, 66)
                } else if state.activeTab == .calendar {
                    CalendarTabView(namespace: animation)
                        .padding(.top, 66)
                } else if state.activeTab == .assistant {
                    AssistantTabView()
                        .padding(.top, 66)
                } else {
                    FridayStatusPanelView(namespace: animation)
                }
            }
            .frame(width: 660, height: 280)
            .offset(y: 20)
            .zIndex(1)

            // Layer 3: Bottom Pills — above hero content so they always receive taps
            HStack(alignment: .bottom, spacing: 20) {
                // Left pill
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

                // Center orb pill — flies in when the activity detail view is open
                if state.activeTab == .home && state.isFridayDetailOpen {
                    MiniOrbPill(namespace: animation)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.75)),
                            removal: .opacity.combined(with: .scale(scale: 0.75))
                        ))
                }

                // Right pill
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .zIndex(2)

            // Layer 4: Context warning badge — bottom center, floats over all content, no layout impact
            if state.isContextWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.yellow.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 14)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .frame(width: 660, height: 280)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: state.activeTab)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: state.activeDetail)
        .animation(.easeInOut(duration: 0.4), value: state.isContextWarning)
    }
}
