import SwiftUI

/// Core Component: The persistent "Assistant" presence.
/// This view is specific to Friday and shows her internal state (mic, status, thinking).
struct NotchAssistantMiniView: View {
    @ObservedObject private var state = FridayState.shared
    
    var body: some View {
        let notchH = state.closedNotchSize.height
        
        VStack(spacing: 0) {
            // ROW 1: System Icons (Utility Row)
            NotchMiniView(
                left: fridayTopLeftWidget,
                right: fridayTopRightWidget
            )
            
            // ROW 2: The Assistant Layer (Centered Architecture)
            ZStack {
                // LEFT GROUP: Orb + Mini Waveform
                HStack(spacing: 8) {
                    MiniOrbView(
                        volume: state.volume,
                        isActive: state.isActive,
                        isError: state.isError,
                        isDevTask: state.isDevTaskRunning,
                        isConnected: state.isConnected
                    )
                    .scaleEffect(1.1)
                    
                    if (state.isListening || state.isSpeaking) && !state.isThinking {
                        MiniWaveform(isActive: true, color: .cyan)
                            .frame(width: 32, height: 14)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // CENTER: Status Text (Locked to exact middle)
                HStack {
                    Text(statusLabel.uppercased())
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(state.isError ? .red : .white)
                        .tracking(1.0)
                }
                
                // RIGHT: Mic Indicator
                HStack {
                    Spacer()
                    micIndicator
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .frame(height: notchH)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    @ViewBuilder
    private var micIndicator: some View {
        if state.isError {
            Button(action: { Task { await AppDelegate.pipeline.restart() } }) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
        } else {
            // Mic is on for the duration of the session. isListening (VAD) shows activity level.
            let micOn = state.isFridaySessionActive
            ZStack {
                Circle()
                    .fill(state.isListening ? Color.yellow.opacity(0.15) : Color.white.opacity(0.06))
                    .frame(width: 24, height: 24)

                Image(systemName: micOn ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(state.isListening ? .yellow : (micOn ? .white.opacity(0.5) : .red))
            }
        }
    }
    
    @ViewBuilder
    private var fridayTopLeftWidget: some View {
        if let alert = state.activeAlert {
            Image(systemName: alert.icon).font(.system(size: 13, weight: .bold)).foregroundColor(alert.color)
        } else if state.isPlayingMusic && !state.isActive {
            MiniWaveform(isActive: true, color: .white.opacity(0.6)).frame(width: 32, height: 14)
        } else if state.isContextWarning {
            // Context warning — same position as system alerts, no layout disruption
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.yellow.opacity(0.8))
        } else {
            Spacer().frame(width: 1)
        }
    }
    
    @ViewBuilder
    private var fridayTopRightWidget: some View {
        if let alert = state.activeAlert {
            if alert.style == .bar {
                // Volume / brightness — linear bar matches HorizontalNotchView treatment
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(width: 50, height: 4)
                    Capsule().fill(alert.color).frame(width: CGFloat(alert.value * 50.0), height: 4)
                }
            } else {
                CompactBatteryRing(value: alert.value, color: alert.color, isCharging: alert.isCharging)
            }
        } else {
            BatteryIndicator().opacity(0.6)
        }
    }
    
    private var statusLabel: String {
        if state.isError          { return "Error" }
        if state.isDevTaskRunning { return "Coding" }
        // Show what the tool is doing instead of the generic "Thinking" label
        if state.isThinking       { return state.currentToolLabel ?? "Thinking" }
        if state.isSpeaking       { return "Speaking" }
        if state.isListening      { return "Listening" }
        return "Waiting"
    }
}
