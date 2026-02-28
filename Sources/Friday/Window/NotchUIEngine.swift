@preconcurrency import AppKit
import SwiftUI
import Combine

@MainActor
final class NotchUIEngine: NSObject, NSWindowDelegate {
    private let panel: NotchWindow
    private let notchSpace = CGSSpace(level: 2147483647)

    private let windowWidth:  CGFloat = 640
    private let windowHeight: CGFloat = 320
    
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
        FridayState.shared.displayState = .dismissed
        // Initial "Ready" sequence
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            FridayState.shared.postAlert(SystemAlert.friday(duration: 3.5))
        }
    }
    
    private func setupNotifications() {
        // Hard dismiss — always goes fully dormant (Gemini goodbye, explicit force-stop)
        NotificationCenter.default.addObserver(forName: .fridayDismiss, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        // Smart collapse — respects active state (user tapping the notch closed)
        NotificationCenter.default.addObserver(forName: .fridayCollapse, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.collapseOrDismiss() }
        }
        NotificationCenter.default.addObserver(forName: .fridayExpand, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                switch FridayState.shared.displayState {
                case .dismissed, .mini: self?.goMiniExpanded(userInitiated: true, wake: true)
                case .miniExpanded:     self?.goOpen(silent: true, userInitiated: true)
                case .open:             break
                }
            }
        }

        // WAKE WORD: "Hey Friday" detected — wake into miniExpanded (not full open)
        NotificationCenter.default.addObserver(forName: .fridayWakeWord, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                let ds = FridayState.shared.displayState
                guard ds == .dismissed || ds == .mini else { return }
                self?.goMiniExpanded(wake: true)
            }
        }
        
        // HOVER ENTER: Deliberate delay
        NotificationCenter.default.addObserver(forName: NSNotification.Name("notchMouseEntered"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isMouseInside = true
                self?.dismissalTimer?.invalidate()
                self?.dismissalTimer = nil

                let state = FridayState.shared
                state.isHovering = true
                
                // Wake Engine starts ONLY when hovering over the idle notch
                if state.displayState == .dismissed || state.displayState == .mini {
                    WakeWordEngine.shared.start()
                    // If an alert is active, expand to show details (name, value, etc)
                    withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.8)) {
                        state.displayState = state.activeAlert != nil ? .miniExpanded : .mini
                    }
                }

                if state.displayState == .dismissed {
                    self?.intentionalHoverTimer?.invalidate()
                    self?.intentionalHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
                        Task { @MainActor in
                            if let self = self, self.isMouseInside {
                                self.goMini()  // hover → mini pill only
                            }
                        }
                    }
                } else if (state.displayState == .mini || state.displayState == .miniExpanded) && state.hasMusicTrack {
                    self?.triggerHaptic()
                }
            }
        }
        
        // HOVER EXIT
        NotificationCenter.default.addObserver(forName: NSNotification.Name("notchMouseExited"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Clear state immediately
                self.isMouseInside = false
                self.intentionalHoverTimer?.invalidate()
                self.intentionalHoverTimer = nil
                
                let state = FridayState.shared
                state.isHovering = false
                
                // Wake Engine stops IMMEDIATELY when hover ends
                WakeWordEngine.shared.stop()
                
                // Start the 3s countdown to dormancy
                self.startDismissalTimer()
                
                // Optional: trigger subtle haptic on exit if user wants it
                // self.triggerHaptic()
            }
        }
    }
    
    private func startDismissalTimer() {
        dismissalTimer?.invalidate()
        // Collapse to miniExpanded after 3s of cursor being away from the open panel
        dismissalTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkAndDismiss()
            }
        }
    }
    
    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    private func checkAndDismiss() {
        let state = FridayState.shared
        // If we are currently hovering, dont dismiss yet.
        if isMouseInside { return }
        
        withAnimation(.interactiveSpring(response: 0.8, dampingFraction: 0.9)) {
            if state.isUserInitiatedExpansion {
                // Do nothing — wait for explicit user action
            } else if state.isActive || state.isDevTaskRunning {
                state.displayState = .miniExpanded
            } else if state.hasMusicTrack {
                state.displayState = .mini
            } else if state.activeAlert != nil {
                // Alert is visible - wait for its own timer to handle it
            } else {
                // Back to physical notch
                state.displayState = .dismissed
            }
        }
    }

    // MARK: - Public API

    func toggle() {
        switch FridayState.shared.displayState {
        case .dismissed, .mini: goMiniExpanded(userInitiated: true, wake: true)
        case .miniExpanded:     goOpen(silent: true, userInitiated: true)
        case .open:             goMiniExpanded()    // stay in session, just collapse the panel
        }
    }

    /// Smart collapse — called when the user taps to dismiss the open panel.
    /// Collapses to mini if Friday is active (keeps pipeline running);
    /// fully dismisses and stops the pipeline if she's idle.
    func collapseOrDismiss() {
        let state = FridayState.shared
        FridayState.shared.isUserInitiatedExpansion = false
        triggerHaptic()

        if state.isActive || state.isDevTaskRunning {
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.9)) {
                FridayState.shared.displayState = .miniExpanded
            }
            // Pipeline keeps running — Friday is still working
        } else {
            WakeWordEngine.shared.stop()
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.9)) {
                FridayState.shared.displayState = .dismissed
            }
            // Graceful shutdown — Friday writes session notes before the pipeline closes.
            // The pipeline posts .fridayDismiss itself when done (or after 15s fallback).
            AppDelegate.pipeline.startGracefulStop()
        }
    }

    func goMini() {
        FridayState.shared.recordActivity()
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
            FridayState.shared.displayState = .mini
        }
        triggerHaptic()
        // Wake engine keeps running — user hovered, Friday not yet active
    }

    func goMiniExpanded(userInitiated: Bool = false, wake: Bool = false) {
        WakeWordEngine.shared.stop()
        FridayState.shared.recordActivity()
        FridayState.shared.isUserInitiatedExpansion = userInitiated
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
            FridayState.shared.displayState = .miniExpanded
        }
        triggerHaptic()
        if wake {
            Task { await AppDelegate.pipeline.wake() }
        }
    }

    func goOpen(silent: Bool = false, userInitiated: Bool = false) {
        WakeWordEngine.shared.stop()
        FridayState.shared.recordActivity()
        FridayState.shared.isUserInitiatedExpansion = userInitiated
        triggerHaptic()
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
            FridayState.shared.displayState = .open
        }
        if !silent { Task { await AppDelegate.pipeline.wake() } }
    }

    func dismiss() {
        FridayState.shared.recordActivity()
        FridayState.shared.isUserInitiatedExpansion = false
        
        // Stop everything immediately
        AppDelegate.pipeline.stop()
        WakeWordEngine.shared.stop()
        
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.9)) {
            FridayState.shared.displayState = .dismissed
            triggerHaptic()
        }
    }

    // MARK: - Private

    private var isCursorOverVisibleNotch: Bool {
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let state = FridayState.shared
        let notchH = state.closedNotchSize.height
        
        let visibleWidth: CGFloat
        let visibleHeight: CGFloat
        
        switch state.displayState {
        case .dismissed: 
            visibleWidth = state.closedNotchSize.width
            visibleHeight = notchH
        case .mini: 
            visibleWidth = 440
            visibleHeight = notchH + 2
        case .miniExpanded: 
            visibleWidth = state.activeAlert != nil ? 440 : state.standardWidth
            visibleHeight = state.isActive || state.hasMusicTrack ? notchH * 2.2 : notchH
        case .open: 
            visibleWidth = NotchSizes.openWidth
            visibleHeight = NotchSizes.openHeight
        }
        
        let checkRect = NSRect(
            x: frame.midX - (visibleWidth / 2),
            y: frame.maxY - visibleHeight,
            width: visibleWidth,
            height: visibleHeight
        )
        return checkRect.contains(mouse)
    }

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
