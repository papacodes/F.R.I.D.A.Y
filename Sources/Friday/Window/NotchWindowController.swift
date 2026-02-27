@preconcurrency import AppKit
import SwiftUI

@MainActor
final class NotchWindowController: NSObject, NSWindowDelegate {
    private let panel: NotchWindow
    private let notchSpace = CGSSpace(level: 2147483647)

    private let windowWidth:  CGFloat = 640
    private let windowHeight: CGFloat = 320
    
    private var activityTimer: Timer?
    private var dismissalTimer: Timer?
    private var intentionalHoverTimer: Timer?
    
    private var isMouseInside = false

    override init() {
        self.panel = NotchWindow()
        super.init()
        
        panel.delegate = self
        
        let hostingView = NSHostingView(rootView: FridayView())
        if let cv = panel.contentView {
            hostingView.frame = cv.bounds
            hostingView.autoresizingMask = [.width, .height]
            cv.addSubview(hostingView)
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        FridayState.shared.closedNotchSize = Self.notchClosedSize(screen: screen)

        let origin = NSPoint(
            x: screen.frame.midX - windowWidth / 2,
            y: screen.frame.maxY - windowHeight
        )
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: windowWidth, height: windowHeight)), display: false)

        panel.orderFrontRegardless()
        notchSpace.windows.insert(panel)

        setupNotifications()

        // START DISMISSED
        dismiss()
        
        // Background Activity Watcher (Music/AI)
        activityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkActivity()
            }
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .fridayDismiss, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        
        // HOVER ENTER: Deliberate delay
        NotificationCenter.default.addObserver(forName: NSNotification.Name("notchMouseEntered"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isMouseInside = true
                self?.dismissalTimer?.invalidate()
                self?.dismissalTimer = nil
                
                if FridayState.shared.displayState == .dismissed {
                    self?.intentionalHoverTimer?.invalidate()
                    self?.intentionalHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
                        Task { @MainActor in
                            if let self = self, self.isMouseInside {
                                self.goStandard()
                                self.triggerHaptic()
                            }
                        }
                    }
                }
            }
        }
        
        // HOVER EXIT
        NotificationCenter.default.addObserver(forName: NSNotification.Name("notchMouseExited"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isMouseInside = false
                self?.intentionalHoverTimer?.invalidate()
                self?.intentionalHoverTimer = nil
                
                self?.startDismissalTimer()
            }
        }
    }
    
    private func startDismissalTimer() {
        dismissalTimer?.invalidate()
        dismissalTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndDismiss()
            }
        }
    }
    
    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    // MARK: - Activity Logic
    
    private func checkActivity() {
        let state = FridayState.shared
        
        // Force open if music is playing
        if state.hasMusicTrack && !state.isMusicPaused {
            if state.displayState == .dismissed {
                goStandard()
                triggerHaptic()
            }
            return
        }
        
        // If we are in standard state but no music/AI/mouse is present, handle auto-dismiss
        if state.displayState == .standard && !state.isActive && !state.hasMusicTrack && !isMouseInside {
            let inactiveTime = Date().timeIntervalSince(state.lastActivityTime)
            if inactiveTime > 5.0 {
                dismiss()
            }
        }
        
        // If music was paused, wait 5s
        if state.isMusicPaused && state.displayState == .standard && !isMouseInside {
            let inactiveTime = Date().timeIntervalSince(state.lastMusicActivity)
            if inactiveTime > 5.0 {
                dismiss()
            }
        }
    }
    
    private func checkAndDismiss() {
        let state = FridayState.shared
        // Only dismiss if mouse is actually outside AND nothing else is holding it open
        if !isMouseInside && !state.isActive && !state.isPlayingMusic {
            dismiss()
        }
    }

    // MARK: - Public API

    func toggle() {
        switch FridayState.shared.displayState {
        case .dismissed, .standard: goOpen()
        case .open:                 goStandard()
        }
    }

    func goStandard() {
        FridayState.shared.recordActivity()
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
            FridayState.shared.displayState = .standard
        }
    }

    func goOpen() {
        FridayState.shared.recordActivity()
        triggerHaptic()
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
            FridayState.shared.displayState = .open
        }
        Task { await AppDelegate.pipeline.wake() }
    }

    func dismiss() {
        FridayState.shared.recordActivity()
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.9)) {
            FridayState.shared.displayState = .dismissed
        }
        AppDelegate.pipeline.stop()
    }

    // MARK: - Private

    private static func notchClosedSize(screen: NSScreen) -> CGSize {
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
