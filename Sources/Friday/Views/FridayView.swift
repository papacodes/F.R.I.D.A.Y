import SwiftUI

// MARK: - Size constants (single source of truth)

enum NotchSizes {
    static let openWidth:     CGFloat = 660   // slightly wider for a more premium spread
    static let openHeight:    CGFloat = 280   // slightly taller for better breathing room
}

struct FridayView: View {
    @ObservedObject private var state = FridayState.shared

    private let spring = Animation.interactiveSpring(response: 0.42, dampingFraction: 0.85)

    // MARK: - Computed shape dimensions

    private var notchSize: CGSize {
        let h = state.closedNotchSize.height
        switch state.displayState {
        case .dismissed: return state.closedNotchSize
        case .mini:
            // Unify canvas width with alerts (440) + 2px overshoot for coverage
            return CGSize(width: 440, height: h + 2)
        case .miniExpanded:
            // Standard height: 32 (Row 1) + 32 (Row 2) = 64
            let targetHeight = h * 2.0 
            return CGSize(width: state.standardWidth, height: targetHeight)
        case .open:
            return CGSize(width: NotchSizes.openWidth, height: NotchSizes.openHeight)
        }
    }

    private var topCornerRadius: CGFloat {
        state.displayState == .open ? 18 : 6
    }

    private var bottomCornerRadius: CGFloat {
        switch state.displayState {
        case .open:        return 32
        case .mini:        return 20  // rounder pill for the small state
        default:           return 14
        }
    }

    // MARK: - Body

        var body: some View {
        ZStack(alignment: .top) {
            // Main Notch Container
            ZStack(alignment: .top) {
                Color.black

                notchContent
                    .animation(spring, value: state.displayState)
                    .animation(spring, value: state.isActive)
            }
            .frame(width: notchSize.width, height: notchSize.height)
            .clipShape(
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
            )
            .overlay(
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                // When fully open, the X button and tab pills handle all interactions.
                // Only allow tap-to-toggle in collapsed states to prevent intercepting pill taps.
                guard state.displayState != .open else { return }
                NotificationCenter.default.post(name: .fridayToggle, object: nil)
            }
            .shadow(color: .black.opacity(state.displayState == .dismissed ? 0 : (state.displayState == .mini ? 0.3 : 0.5)), radius: 28, x: 0, y: 10)

            // Task Manager Pill — floats below the expanded notch when tasks are active
            if state.displayState == .open && !state.activeTasks.isEmpty {
                VStack(spacing: 0) {
                    // Transparent spacer matching the notch height + gap
                    Color.clear
                        .frame(height: NotchSizes.openHeight + 12)
                        .allowsHitTesting(false)

                    TaskManagerPillView()
                        .frame(width: NotchSizes.openWidth)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -8)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .ignoresSafeArea()
        .animation(spring, value: state.displayState)
        .animation(spring, value: state.isActive)
        .animation(spring, value: state.hasMusicTrack)
        .animation(spring, value: state.standardWidth)
        .animation(spring, value: state.activeTasks.isEmpty)
        .preferredColorScheme(.dark)
    }

    // MARK: - Content per state

        @ViewBuilder
    private var notchContent: some View {
        let notchH = state.closedNotchSize.height

        if state.displayState == .open {
            // Full expanded view — always takes priority in open state, session or not
            NotchExpandedView()
                .frame(width: NotchSizes.openWidth, height: NotchSizes.openHeight)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                    removal: .opacity
                ))

        } else if (state.isFridaySessionActive || state.isDevTaskRunning) && state.activeAlert == nil {
            // Friday's session view — shown when in session and no notification is active
            NotchAssistantMiniView()
                .frame(width: notchSize.width, height: notchSize.height)
                .transition(.opacity)

        } else if state.activeAlert != nil || state.displayState == .mini || state.displayState == .miniExpanded {
            // Notifications, alerts, or music — displayed as intended, even during a session.
            // When the alert clears, content switches back to NotchAssistantMiniView automatically.
            HorizontalNotchView()
                .frame(width: notchSize.width, height: notchSize.height)
                .transition(.opacity)

        } else {
            // Dormant physical notch
            NotchIdleIndicator()
                .frame(width: state.closedNotchSize.width, height: notchH)
                .transition(.opacity)
        }
    }
}
