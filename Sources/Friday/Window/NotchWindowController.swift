@preconcurrency import AppKit
import SwiftUI

@MainActor
final class NotchWindowController {
    private let panel: NotchWindow
    private(set) var isExpanded = false

    private let expandedHeight: CGFloat = 350
    private let collapsedHeight: CGFloat = 32
    private let topOffset: CGFloat = 1

    init() {
        panel = NotchWindow()

        let hostingView = NSHostingView(rootView: FridayView())
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.alphaValue = 0
    }

    func toggle() {
        isExpanded ? collapse() : expand()
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let (notchX, notchWidth) = notchGeometry(screen: screen)
        let topOfScreen = screen.frame.maxY + topOffset

        let finalWidth = max(notchWidth, 320)
        let finalX = notchX - (finalWidth - notchWidth) / 2

        let targetFrame = NSRect(
            x: finalX,
            y: topOfScreen - expandedHeight,
            width: finalWidth,
            height: expandedHeight
        )

        let startFrame = NSRect(
            x: notchX,
            y: topOfScreen - collapsedHeight,
            width: notchWidth,
            height: collapsedHeight
        )

        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 1.25, 0.45, 1.0)
            panel.animator().setFrame(targetFrame, display: true)
        }

        Task { await AppDelegate.pipeline.wake() }
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false

        FridayState.shared.showInfoCard = false
        Task { await AppDelegate.pipeline.sleep() }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let (notchX, notchWidth) = notchGeometry(screen: screen)
        let topOfScreen = screen.frame.maxY + topOffset

        let collapseFrame = NSRect(
            x: notchX,
            y: topOfScreen - collapsedHeight,
            width: notchWidth,
            height: collapsedHeight
        )

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(collapseFrame, display: true)
        }, completionHandler: {
            Task { @MainActor in
                self.panel.alphaValue = 0
                self.panel.orderOut(nil)
            }
        })
    }

    private func notchGeometry(screen: NSScreen) -> (x: CGFloat, width: CGFloat) {
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let x     = left.maxX
            let width = right.minX - left.maxX
            if width > 0 { return (x, width) }
        }
        return (screen.frame.midX - 150, 300)
    }
}
