import Foundation
import SwiftUI

/// Manages the system notification and alert overlay lifecycle.
///
/// This is a completely separate system from Friday's session state.
/// When a Friday session is active (isFridaySessionActive = true), this engine
/// can only manage the alert overlay content — it never touches displayState.
/// Panel visibility is solely Friday's responsibility during an active session.
@MainActor
final class NotchAlertEngine {
    static let shared = NotchAlertEngine()
    private init() {}

    private var alertQueue: [SystemAlert] = []
    private var alertTimer: Timer?

    // MARK: - Public API

    func postAlert(_ alert: SystemAlert) {
        let state = FridayState.shared
        if state.activeAlert?.id == alert.id {
            state.activeAlert = alert
            alertTimer?.invalidate()
            alertTimer = Timer.scheduledTimer(withTimeInterval: alert.duration, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    if FridayState.shared.isHovering { return }
                    self.showNextAlert()
                }
            }
            return
        }
        alertQueue.append(alert)
        if state.activeAlert == nil { showNextAlert() }
    }

    func showNextAlert() {
        let state = FridayState.shared
        guard !alertQueue.isEmpty else {
            // Friday session owns the panel — clear the alert overlay only, never touch displayState
            if state.isFridaySessionActive {
                withAnimation(.interactiveSpring(response: 0.8, dampingFraction: 0.9)) {
                    state.activeAlert = nil
                }
                return
            }
            // Notification-only dismissal path
            if !state.isPlayingMusic && (state.displayState == .mini || state.displayState == .miniExpanded) {
                if state.isHovering { return }
                withAnimation(.interactiveSpring(response: 0.8, dampingFraction: 0.9)) {
                    state.displayState = .dismissed
                }
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if state.isHovering || state.isFridaySessionActive { return }
                    if self.alertQueue.isEmpty {
                        state.activeAlert = nil
                    } else {
                        // A new alert arrived during the dismissal window — process it now.
                        self.showNextAlert()
                    }
                }
            } else if !state.isPlayingMusic && !state.isHovering {
                state.activeAlert = nil
            }
            return
        }

        let alert = alertQueue.removeFirst()
        alertTimer?.invalidate()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            state.activeAlert = alert
            // Only pull the notch up to mini when Friday is NOT in session and panel is dormant
            if !state.isFridaySessionActive && state.displayState == .dismissed {
                state.displayState = .mini
            }
        }

        alertTimer = Timer.scheduledTimer(withTimeInterval: alert.duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if FridayState.shared.isHovering { return }
                self.showNextAlert()
            }
        }
    }
}
