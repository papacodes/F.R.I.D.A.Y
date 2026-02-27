import AppKit

class NotchWindow: NSPanel {

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        isReleasedWhenClosed = false
        worksWhenModal = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false

        appearance = NSAppearance(named: .darkAqua)

        // Use custom content view for mouse tracking
        contentView = NotchContentView()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

/// Custom view to handle mouse tracking outside of SwiftUI
class NotchContentView: NSView {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        // REFINED: Only track the top notch area, not the full vertical expansion window.
        // The window is 320pt tall to support expanded mode, but hover should only trigger at the very top.
        let notchHeight: CGFloat = 38 // Slightly taller than the notch for easier triggering
        let trackingRect = NSRect(
            x: 0,
            y: bounds.height - notchHeight,
            width: bounds.width,
            height: notchHeight
        )
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .mouseMoved]
        let area = NSTrackingArea(rect: trackingRect, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NotificationCenter.default.post(name: NSNotification.Name("notchMouseEntered"), object: nil)
    }
    
    override func mouseExited(with event: NSEvent) {
        NotificationCenter.default.post(name: NSNotification.Name("notchMouseExited"), object: nil)
    }
}
