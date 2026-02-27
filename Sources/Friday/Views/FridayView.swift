import SwiftUI

struct FridayView: View {
    @ObservedObject private var state = FridayState.shared

    private let openSize = CGSize(width: 640, height: 260)
    private let openAnimation  = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8)
    private let closeAnimation = Animation.interactiveSpring(response: 0.3,  dampingFraction: 0.9)

    private var currentAnimation: Animation {
        state.isExpanded ? openAnimation : closeAnimation
    }

    private var notchSize: CGSize {
        state.isExpanded ? openSize : state.closedNotchSize
    }

    private var topCornerRadius: CGFloat    { state.isExpanded ? 19 : 6 }
    private var bottomCornerRadius: CGFloat { state.isExpanded ? 24 : 14 }

    var body: some View {
        ZStack(alignment: .top) {

            // ── Always-present black notch shape ────────────────────────────
            // Collapsed: blends with hardware notch.
            // Expanded: grows down to reveal content.
            Color.black
                .clipShape(
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                )
                .frame(width: notchSize.width, height: notchSize.height)
                .animation(currentAnimation, value: state.isExpanded)

            // ── Collapsed alive indicator ────────────────────────────────────
            // Sits inside the physical notch dimensions — subtle but shows
            // Friday is running.
            NotchIdleIndicator()
                .frame(width: state.closedNotchSize.width, height: state.closedNotchSize.height)
                .opacity(state.isExpanded ? 0 : 1)
                .animation(currentAnimation, value: state.isExpanded)

            // ── Expanded content ─────────────────────────────────────────────
            if state.isExpanded {
                NotchExpandedView()
                    .frame(width: openSize.width, height: openSize.height)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal:   .opacity
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(currentAnimation, value: state.isExpanded)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}
