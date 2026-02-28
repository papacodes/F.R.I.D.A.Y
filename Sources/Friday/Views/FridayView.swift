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
        case .standard:  
            // If active (speaking/listening), grow downward. If idle, stay inside notch height.
            let targetHeight = state.isActive ? h * 2.2 : h
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
                        NotificationCenter.default.post(name: .fridayDismiss, object: nil) 
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

        case .standard:
            HorizontalNotchView()
                // Only push content down if we are in the "Active" (tall) state
                .padding(.top, state.isActive ? notchH : 0)
                .frame(
                    width:  state.standardWidth,
                    height: state.isActive ? notchH * 2.2 : notchH
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
