import AppKit

class NotchWindow: NSPanel {

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        // Clear background — SwiftUI draws the pill shape and handles corner rounding
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        // Float above normal windows but below menus/overlays
        level = .floating

        isFloatingPanel = true
        worksWhenModal = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        contentView?.wantsLayer = true
    }
}
