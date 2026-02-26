import AppKit
import SwiftUI

@MainActor
class NotchWindowController {
    private let panel: NotchWindow
    private(set) var isExpanded = false
    private var pipeline: GeminiVoicePipeline?

    private let expandedHeight: CGFloat = 350 // Much taller for card + orb
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

        // Ensure at least 320 width for the card
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

        if pipeline == nil {
            pipeline = GeminiVoicePipeline(state: FridayState.shared)
        }
        pipeline?.start()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false

        pipeline?.stop()
        FridayState.shared.showInfoCard = false // Reset card state on collapse

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

// Typo fix for timing function
extension CAMediaTimingFunction {
    static var standard: CAMediaTimingFunction { CAMediaTimingFunction(name: .default) }
}
