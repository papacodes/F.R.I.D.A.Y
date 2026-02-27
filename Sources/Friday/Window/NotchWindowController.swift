@preconcurrency import AppKit
import SwiftUI

@MainActor
final class NotchWindowController {
    private let panel: NotchWindow
    private let notchSpace = CGSSpace(level: 2147483647)

    // The NSWindow never moves or resizes — SwiftUI animates the visible shape inside it
    private let windowWidth:  CGFloat = 640
    private let windowHeight: CGFloat = 320

    init() {
        panel = NotchWindow()
        panel.contentView = NSHostingView(rootView: FridayView())

        let screen = NSScreen.main ?? NSScreen.screens[0]
        FridayState.shared.closedNotchSize = notchClosedSize(screen: screen)

        let origin = NSPoint(
            x: screen.frame.midX - windowWidth / 2,
            y: screen.frame.maxY - windowHeight
        )
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: windowWidth, height: windowHeight)), display: false)

        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        notchSpace.windows.insert(panel)

        // Start in standard (alive) state immediately
        goStandard()
    }

    // MARK: - Public API

    /// Hotkey handler — toggles between standard and open
    func toggle() {
        switch FridayState.shared.displayState {
        case .dismissed, .standard: goOpen()
        case .open:                 goStandard()
        }
    }

    func goStandard() {
        panel.ignoresMouseEvents = true
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
            FridayState.shared.displayState = .standard
        }
    }

    func goOpen() {
        panel.ignoresMouseEvents = false
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
            FridayState.shared.displayState = .open
        }
        Task { await AppDelegate.pipeline.wake() }
    }

    func dismiss() {
        panel.ignoresMouseEvents = true
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.9)) {
            FridayState.shared.displayState = .dismissed
        }
        Task { await AppDelegate.pipeline.sleep() }
    }

    // MARK: - Private

    private func notchClosedSize(screen: NSScreen) -> CGSize {
        var width:  CGFloat = 200
        var height: CGFloat = 32
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let w = right.minX - left.maxX
            if w > 0 { width = w }
        }
        if screen.safeAreaInsets.top > 0 { height = screen.safeAreaInsets.top }
        return CGSize(width: width, height: height)
    }
}
