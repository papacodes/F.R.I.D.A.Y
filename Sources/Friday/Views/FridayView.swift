import SwiftUI

// MARK: - Size constants (single source of truth)

enum NotchSizes {
    static let standardWidth: CGFloat = 440   // horizontal bar width
    static let openWidth:     CGFloat = 640   // full expanded width
    static let openHeight:    CGFloat = 260   // full expanded height
}

struct FridayView: View {
    @ObservedObject private var state = FridayState.shared

    private let spring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.82)

    // MARK: - Computed shape dimensions

    private var notchSize: CGSize {
        let h = state.closedNotchSize.height
        switch state.displayState {
        case .dismissed: return state.closedNotchSize
        case .standard:  return CGSize(width: NotchSizes.standardWidth, height: h)
        case .open:      return CGSize(width: NotchSizes.openWidth,     height: NotchSizes.openHeight)
        }
    }

    private var topCornerRadius: CGFloat {
        state.displayState == .open ? 19 : 6
    }

    private var bottomCornerRadius: CGFloat {
        state.displayState == .open ? 24 : 14
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Black notch shape — animates between all three sizes
            Color.black
                .frame(width: notchSize.width, height: notchSize.height)
                .clipShape(
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                )
                .animation(spring, value: state.displayState)

            // Content — cross-fades between states
            notchContent
                .animation(spring, value: state.displayState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: - Content per state

    @ViewBuilder
    private var notchContent: some View {
        switch state.displayState {

        case .dismissed:
            NotchIdleIndicator()
                .frame(
                    width:  state.closedNotchSize.width,
                    height: state.closedNotchSize.height
                )
                .transition(.opacity)

        case .standard:
            HorizontalNotchView()
                .frame(
                    width:  NotchSizes.standardWidth,
                    height: state.closedNotchSize.height
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
