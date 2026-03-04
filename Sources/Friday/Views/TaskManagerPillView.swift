import SwiftUI

// MARK: - Task Manager Pill
// Floats below the expanded notch when execute_dev_task tasks are active.
// Shows one chip per task. Tap to expand a task's live log.

struct TaskManagerPillView: View {
    @ObservedObject private var state = FridayState.shared
    @State private var expandedTaskId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Chip row — always visible
            chipRow

            // Log panel — slides in below chips when a task is selected
            if let id = expandedTaskId,
               let activeTask = state.activeTasks.first(where: { $0.id == id }) {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 16)

                logPanel(activeTask: activeTask)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 12)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: expandedTaskId)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: state.activeTasks)
        // Clear expandedTaskId if task is dismissed
        .onChange(of: state.activeTasks) { _, tasks in
            if let id = expandedTaskId, !tasks.contains(where: { $0.id == id }) {
                expandedTaskId = nil
            }
        }
    }

    // MARK: - Chip Row

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(state.activeTasks) { activeTask in
                TaskChip(activeTask: activeTask, isSelected: expandedTaskId == activeTask.id) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        expandedTaskId = expandedTaskId == activeTask.id ? nil : activeTask.id
                    }
                } onDismiss: {
                    if expandedTaskId == activeTask.id { expandedTaskId = nil }
                    state.dismissTask(id: activeTask.id)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Log Panel

    private func logPanel(activeTask: ActiveTask) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(activeTask.log) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(entry.isError ? Color.red : Color.white.opacity(0.3))
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)
                            Text(entry.text)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(entry.isError ? .red.opacity(0.85) : .white.opacity(0.65))
                                .lineLimit(2)
                        }
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 160)
            // Auto-scroll to latest entry
            .onChange(of: activeTask.log.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }
}

// MARK: - Task Chip

private struct TaskChip: View {
    let activeTask: ActiveTask
    let isSelected: Bool
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            statusIndicator
            Text(activeTask.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            if !activeTask.currentStep.isEmpty && activeTask.status == .running {
                Text(activeTask.currentStep)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                    .frame(maxWidth: 140)
            }
            // Dismiss button — only for done/error tasks
            if activeTask.status != .running {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(chipBackground)
                .overlay(
                    Capsule()
                        .stroke(chipBorder, lineWidth: isSelected ? 1 : 0.5)
                )
        )
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: activeTask.status)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch activeTask.status {
        case .running:
            PulsingDot(color: .cyan)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.red)
        }
    }

    private var chipBackground: Color {
        switch activeTask.status {
        case .running: return isSelected ? Color.cyan.opacity(0.15) : Color.white.opacity(0.08)
        case .done:    return isSelected ? Color.green.opacity(0.12) : Color.white.opacity(0.06)
        case .error:   return isSelected ? Color.red.opacity(0.15)   : Color.white.opacity(0.06)
        }
    }

    private var chipBorder: Color {
        switch activeTask.status {
        case .running: return isSelected ? Color.cyan.opacity(0.5)  : Color.white.opacity(0.15)
        case .done:    return isSelected ? Color.green.opacity(0.4) : Color.white.opacity(0.1)
        case .error:   return isSelected ? Color.red.opacity(0.5)   : Color.white.opacity(0.1)
        }
    }
}

// MARK: - Pulsing Dot (running indicator)

private struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(pulse ? 0.0 : 0.3))
                .frame(width: 12, height: 12)
                .scaleEffect(pulse ? 1.8 : 1.0)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
