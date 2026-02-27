@preconcurrency import AppKit
import SwiftUI

@MainActor
final class NotchWindowController {
    private let panel: NotchWindow
    // Holds the CGS Space at absolute level Int.max — the mechanism that lets us
    // render above the menu bar / notch constraint (same technique as boring.notch)
    private let notchSpace = CGSSpace(level: 2147483647)

    // Fixed window dimensions — large enough for expanded content.
    // The NSWindow never moves or resizes. SwiftUI animates what's visible inside it.
    private let windowWidth: CGFloat = 640
    private let windowHeight: CGFloat = 320

    init() {
        panel = NotchWindow()
        panel.contentView = NSHostingView(rootView: FridayView())

        let screen = NSScreen.main ?? NSScreen.screens[0]

        let closedSize = notchClosedSize(screen: screen)
        FridayState.shared.closedNotchSize = closedSize

        let origin = NSPoint(
            x: screen.frame.midX - windowWidth / 2,
            y: screen.frame.maxY - windowHeight
        )
        let targetFrame = NSRect(origin: origin, size: CGSize(width: windowWidth, height: windowHeight))
        panel.setFrame(targetFrame, display: false)

        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        notchSpace.windows.insert(panel)
    }

    func toggle() {
        FridayState.shared.isExpanded ? collapse() : expand()
    }

    func expand() {
        guard !FridayState.shared.isExpanded else { return }
        panel.ignoresMouseEvents = false
        FridayState.shared.isExpanded = true
        Task { await AppDelegate.pipeline.wake() }
    }

    func collapse() {
        guard FridayState.shared.isExpanded else { return }
        FridayState.shared.isExpanded = false
        FridayState.shared.showInfoCard = false
        panel.ignoresMouseEvents = true
        Task { await AppDelegate.pipeline.sleep() }
    }

    // MARK: - Private

    private func notchClosedSize(screen: NSScreen) -> CGSize {
        var width: CGFloat = 200
        var height: CGFloat = 32

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let w = right.minX - left.maxX
            if w > 0 { width = w }
        }

        if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
        }

        return CGSize(width: width, height: height)
    }
}
