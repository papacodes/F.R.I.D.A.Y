import AppKit
import SwiftUI

@MainActor
class NotchWindowController {
    private let panel: NotchWindow
    private(set) var isExpanded = false
    private var pipeline: VoicePipeline?

    private let panelHeight: CGFloat = 56
    private let menuBarGap: CGFloat  = 6   // breathing room below the menu bar

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

    // MARK: - Expand / collapse

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let (notchX, notchWidth) = notchGeometry(screen: screen)
        let belowMenuBar = screen.visibleFrame.maxY   // bottom edge of menu bar

        // Where the panel lives when visible
        let targetFrame = NSRect(
            x: notchX,
            y: belowMenuBar - panelHeight - menuBarGap,
            width: notchWidth,
            height: panelHeight
        )

        // Start hidden with its bottom flush against the menu bar bottom —
        // looks like it slides out from inside the notch
        let startFrame = NSRect(
            x: notchX,
            y: belowMenuBar,
            width: notchWidth,
            height: panelHeight
        )

        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.46
            // Spring overshoot → subtle bounce at rest
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }

        if pipeline == nil {
            pipeline = VoicePipeline(state: FridayState.shared)
        }
        pipeline?.start()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false

        pipeline?.stop()

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let (notchX, notchWidth) = notchGeometry(screen: screen)
        let belowMenuBar = screen.visibleFrame.maxY

        // Retreat back up into the notch
        let collapseFrame = NSRect(
            x: notchX,
            y: belowMenuBar,
            width: notchWidth,
            height: panelHeight
        )

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(collapseFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in self.panel.orderOut(nil) }
        })
    }

    // MARK: - Notch geometry

    // Returns the x origin and width of the notch using the screen's auxiliary
    // area rects (macOS 12+). Falls back to a centred pill on non-notch displays.
    private func notchGeometry(screen: NSScreen) -> (x: CGFloat, width: CGFloat) {
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let x     = left.maxX
            let width = right.minX - left.maxX
            if width > 0 { return (x, width) }
        }
        // Non-notch display — centred 200pt pill
        return (screen.frame.midX - 100, 200)
    }
}
