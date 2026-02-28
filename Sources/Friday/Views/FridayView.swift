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
                NotificationCenter.default.post(name: .fridayToggle, object: nil)
            }
            .shadow(color: .black.opacity(state.displayState == .dismissed ? 0 : (state.displayState == .mini ? 0.3 : 0.6)), radius: 40, x: 0, y: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(spring, value: state.displayState)
        .animation(spring, value: state.isActive)
        .animation(spring, value: state.hasMusicTrack)
        .animation(spring, value: state.standardWidth)
        .preferredColorScheme(.dark)
    }

    // MARK: - Content per state

    @ViewBuilder
    private var notchContent: some View {
        let notchH = state.closedNotchSize.height

        // Always show the expanded content if an alert is active (even during contraction to dismissed)
        if state.activeAlert != nil && state.displayState != .open {
            HorizontalNotchView()
                .frame(width: notchSize.width, height: notchSize.height)
        } else {
            switch state.displayState {
            case .dismissed:
                NotchIdleIndicator()
                    .frame(width: state.closedNotchSize.width, height: notchH)
                    .transition(.opacity)

            case .mini:
                HorizontalNotchView()
                    .frame(width: 440, height: notchH)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))

            case .miniExpanded:
                if state.activeAlert != nil {
                    AlertNotchView()
                        .frame(width: 440, height: notchH)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                } else {
                    HorizontalNotchView()
                        
                        .frame(
                            width:  state.standardWidth,
                            height: state.isActive || state.hasMusicTrack ? notchH * 2.2 : notchH
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }

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
}
