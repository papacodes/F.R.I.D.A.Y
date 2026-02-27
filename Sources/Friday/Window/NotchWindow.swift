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

        // isFloatingPanel must come first — it resets level to .floating (3)
        // Setting level afterwards ensures it sticks at mainMenu+3 (27)
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

        // Force dark so the black notch shape always matches the hardware cutout
        appearance = NSAppearance(named: .darkAqua)

        contentView?.wantsLayer = true
    }

    // Must not steal focus from whatever the user is doing
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Without this override, macOS clamps the frame to screen.visibleFrame,
    // which excludes the menu bar / notch area and pushes us down by ~38pt
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}
