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
        case .alert:     return CGSize(width: 440, height: h)
        case .miniExpanded:
            // Mini expanded height is standard unless active, as defined in NotchWindowController
            let targetHeight = state.isActive || state.hasMusicTrack ? h * 2.2 : h
            return CGSize(width: state.standardWidth, height: targetHeight)
        case .open:
            return CGSize(width: NotchSizes.openWidth, height: NotchSizes.openHeight)
        }
    }

    private var topCornerRadius: CGFloat {
        state.displayState == .open ? 18 : 6
    }

    private var bottomCornerRadius: CGFloat {
        state.displayState == .open ? 32 : 14
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Pitch Black Background
            Color.black
                .contentShape(Rectangle())
                .onTapGesture {
                    if state.displayState == .open {
                        // Smart collapse — goes to mini if Friday is active, dismissed if idle
                        NotificationCenter.default.post(name: .fridayCollapse, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .fridayExpand, object: nil)
                    }
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
                .shadow(color: .black.opacity(state.displayState == .dismissed ? 0 : 0.6), radius: 40, x: 0, y: 20)
                .animation(spring, value: state.displayState)
                .animation(spring, value: state.isActive)
                .animation(spring, value: state.hasMusicTrack)
                .animation(spring, value: state.standardWidth)

            // Content
            notchContent
                .animation(spring, value: state.displayState)
                .animation(spring, value: state.isActive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: - Content per state

    @ViewBuilder
    private var notchContent: some View {
        let notchH = state.closedNotchSize.height

        switch state.displayState {

        case .dismissed:
            NotchIdleIndicator()
                .frame(
                    width:  state.closedNotchSize.width,
                    height: notchH
                )
                .transition(.opacity)

        case .alert:
            AlertNotchView()
                .frame(width: 440, height: notchH)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))

        case .miniExpanded:
            HorizontalNotchView()
                .padding(.top, state.isActive || state.hasMusicTrack ? notchH : 0)
                .frame(
                    width:  state.standardWidth,
                    height: state.isActive || state.hasMusicTrack ? notchH * 2.2 : notchH
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))

        case .open:
            NotchExpandedView()
                .frame(
                    width:  NotchSizes.openWidth,
                    height: NotchSizes.openHeight
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                        removal:   .opacity
                    )
                )
        }
    }
}
