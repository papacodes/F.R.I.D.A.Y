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
        NotificationCenter.default.addObserver(forName: .fridayExpand, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.goOpen(silent: true) }
        }

        // WAKE WORD: "Hey Friday" detected — summon the full panel and wake Gemini
        NotificationCenter.default.addObserver(forName: .fridayWakeWord, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard FridayState.shared.displayState != .open else { return }
                self?.goOpen()
            }
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
                            }
                        }
                    }
                }
            }
        }
        
        // HOVER EXIT
        NotificationCenter.default.addObserver(forName: NSNotification.Name("notchMouseExited"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // The tracking area is only 38pt, but the notch grows taller in
                // standard-active (~70pt) and open (280pt) states. Guard against
                // false exits when the cursor moves into expanded content below the zone.
                if self.isCursorOverVisibleNotch { return }

                self.isMouseInside = false
                self.intentionalHoverTimer?.invalidate()
                self.intentionalHoverTimer = nil
                self.startDismissalTimer()
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
            }
            return
        }
        
        // If we are in standard state but no music/AI/mouse is present, handle auto-dismiss
        if state.displayState == .standard && !state.isActive && !state.hasMusicTrack && !isMouseInside && !isCursorOverVisibleNotch {
            let inactiveTime = Date().timeIntervalSince(state.lastActivityTime)
            if inactiveTime > 5.0 {
                dismiss()
            }
        }

        // If music was paused, wait 5s
        if state.isMusicPaused && state.displayState == .standard && !isMouseInside && !isCursorOverVisibleNotch {
            let inactiveTime = Date().timeIntervalSince(state.lastMusicActivity)
            if inactiveTime > 5.0 {
                dismiss()
            }
        }
    }
    
    private func checkAndDismiss() {
        let state = FridayState.shared
        if !isMouseInside && !isCursorOverVisibleNotch && !state.isActive && !state.isPlayingMusic {
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
            triggerHaptic()
        }
        // If coming from open state, Gemini had the mic — restart wake word after it releases
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            WakeWordEngine.shared.start()
        }
    }

    func goOpen(silent: Bool = false) {
        // Stop wake word before Gemini takes the mic
        WakeWordEngine.shared.stop()
        FridayState.shared.recordActivity()
        triggerHaptic()
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
            FridayState.shared.displayState = .open
        }
        if !silent { Task { await AppDelegate.pipeline.wake() } }
    }

    func dismiss() {
        FridayState.shared.recordActivity()
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.9)) {
            FridayState.shared.displayState = .dismissed
            triggerHaptic()
        }
        AppDelegate.pipeline.stop()
        // Restart wake word after the pipeline releases the mic
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            WakeWordEngine.shared.start()
        }
    }

    // MARK: - Private

    /// Checks whether the real cursor position (screen coordinates) is over the
    /// visible notch content. This is the ground-truth guard used to catch false
    /// mouseExited events fired by the narrow 38pt tracking area when the notch
    /// has grown taller in standard-active or open states.
    private var isCursorOverVisibleNotch: Bool {
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let state = FridayState.shared
        let notchH = state.closedNotchSize.height
        let visibleHeight: CGFloat
        switch state.displayState {
        case .dismissed: visibleHeight = notchH
        case .standard:  visibleHeight = state.isActive ? notchH * 2.2 : notchH
        case .open:      visibleHeight = NotchSizes.openHeight
        }
        let checkRect = NSRect(
            x: frame.minX,
            y: frame.maxY - visibleHeight,
            width: frame.width,
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
