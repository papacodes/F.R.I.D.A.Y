import Foundation
import SwiftUI

enum ToolResult {
    case text(String)
    case captureImage(base64: String, prompt: String, textResult: String)
    case refreshSession(textResult: String)
    case disconnectSession(textResult: String)
}

@MainActor
final class ToolDispatcher {
    static let shared = ToolDispatcher()
    private let agentRouter = CodingAgentRouter()
    
    private init() {}
    
    func execute(name: String, args: [String: String], state: FridayState) async -> ToolResult {
        var result = "Task complete."
        
        switch name {
        case "read_file":
            if let path = args["path"] {
                state.beginDevTask()
                result = FileSystemSkill.readFile(path: path)
                state.endDevTask()
            }

        case "write_file":
            if let path = args["path"], let content = args["content"] {
                state.beginDevTask()
                result = FileSystemSkill.writeFile(path: path, content: content)
                state.endDevTask()
            }

        case "list_directory":
            if let path = args["path"] {
                result = FileSystemSkill.listDirectory(path: path)
            }

        case "run_shell":
            if let command = args["command"] {
                state.beginDevTask()
                result = await ShellSkill.run(command, directory: args["directory"])
                state.endDevTask()
            }

        case "get_weather":
            if let weather = await WeatherSkill.fetchWeather() {
                let w = weather.current_weather
                result = "Temperature: \(Int(w.temperature))°C, Wind: \(Int(w.windspeed)) km/h."
                state.currentWeather = weather
                state.update(\.activeTab, to: .home)
                state.update(\.activeDetail, to: .weather)
                if state.displayState != .open {
                    NotificationCenter.default.post(name: .fridayExpand, object: nil)
                }
            } else {
                result = "Unable to fetch weather data."
            }
        case "get_time":
            result = "It is currently \(TimeSkill.getCurrentTime()) on \(TimeSkill.getCurrentDate())."
        case "get_battery_status":
            result = BatterySkill.getBatteryStatus()
        case "find_nearby_places":
            if let q = args["query"] { result = await MapsSkill.findNearby(q) }
        case "retrieve_knowledge":
            if let q = args["query"] { result = await RAGSkill.retrieve(query: q) }

        case "web_search":
            if let q = args["query"] { result = await SearchSkill.searchWeb(q) }
        case "control_music":
            if let action = args["action"] {
                switch action {
                case "play": result = MusicSkill.play()
                case "pause": result = MusicSkill.pause()
                case "next": result = MusicSkill.nextTrack()
                case "search": 
                    if let q = args["query"] { result = MusicSkill.playSearch(q) }
                default: result = "Music action not recognized."
                }
            }
        case "play_playlist":
            if let name = args["name"] { result = MusicSkill.playPlaylist(name) }
        case "manage_notes":
            if let action = args["action"] {
                let filename = args["filename"] ?? "FridayNotes"
                let content = args["content"] ?? ""
                switch action {
                case "create": result = NotesSkill.createNote(filename: filename, content: content)
                case "read": result = NotesSkill.readNote(filename: filename)
                case "append": result = NotesSkill.appendToNote(filename: filename, content: content)
                case "list": result = NotesSkill.listNotes()
                case "delete": result = NotesSkill.deleteNote(filename: filename)
                default: result = "Notes action not recognized."
                }
            }
        case "manage_reminders":
            if let action = args["action"] {
                if action == "add", let title = args["title"] {
                    let date = args["due_date"].map { DateHelper.parseAndFormat($0) }
                    result = RemindersSkill.addReminder(title: title, dueDate: date)
                } else if action == "list" {
                    result = RemindersSkill.listReminders()
                }
            }
        case "manage_calendar":
            if let action = args["action"] {
                if action == "add", let title = args["title"], let start = args["start_time"] {
                    result = await CalendarSkill.addEvent(
                        title: title,
                        startTimeString: start,
                        endTimeString: args["end_time"]
                    )
                } else if action == "get_schedule" {
                    result = await CalendarSkill.getSchedule(forDate: args["date"])
                }
            }
        case "execute_dev_task":
            guard let task = args["task"] else {
                return .text("[TASK_ERROR] execute_dev_task called without a task argument.")
            }
            let projectPath = args["project_path"]
            let projectKey = projectPath ?? "default"
            let agentID = args["agent"].flatMap { CodingAgentID(rawValue: $0) }
            let agent = agentRouter.resolve(agentID: agentID, projectKey: projectKey)

            let projectName = projectPath
                .map { URL(fileURLWithPath: $0.replacingOccurrences(of: "~", with: "")).lastPathComponent }
                ?? "task"
            let agentSuffix: String
            switch agentID ?? .claude {
            case .claude:  agentSuffix = ""
            case .gemini:  agentSuffix = " [gemini cli]"
            case .copilot: agentSuffix = " [copilot]"
            }
            let taskLabel = projectName + agentSuffix

            if agent.isBusy {
                return .text("\(agent.agentName) is already running a task for \(taskLabel). Please wait.")
            }

            state.startTask(id: projectKey, label: taskLabel)
            state.addActivity(type: .info, title: agent.agentName, subtitle: task)

            let maxTurns = args["max_turns"].flatMap { Int($0) } ?? 15
            do {
                result = try await agent.ask(task, directory: projectPath, maxTurns: maxTurns) { progress in
                    Task { @MainActor in
                        FridayState.shared.updateTask(id: projectKey, step: progress)
                    }
                }
                if agent is ClaudeProcess {
                    if result.contains("[TASK_DONE]") {
                        result = result.replacingOccurrences(of: "[TASK_DONE]", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        state.completeTask(id: projectKey)
                    } else {
                        state.errorTask(id: projectKey, message: "Ended without confirmation — may be incomplete")
                    }
                } else {
                    if result.hasPrefix("[TASK_ERROR]") {
                        state.errorTask(id: projectKey, message: "Task failed")
                    } else {
                        state.completeTask(id: projectKey)
                    }
                }
                state.update(\.transcript, to: "")
                let limit = 1500
                if result.count > limit {
                    let head = String(result.prefix(400))
                    let tail = String(result.suffix(1000))
                    result = "\(head)\n…[truncated]\n\(tail)"
                }
            } catch {
                state.errorTask(id: projectKey, message: error.localizedDescription)
                result = "\(agent.agentName) failed: \(error.localizedDescription)"
            }

        case "capture_screen":
            if let prompt = args["prompt"] {
                let captureResult = await ScreenCaptureSkill.captureAndAnalyze(prompt: prompt)
                if captureResult.hasPrefix("[SCREENSHOT_CAPTURED]") {
                    let base64 = captureResult.replacingOccurrences(of: "[SCREENSHOT_CAPTURED]", with: "")
                    return .captureImage(base64: base64, prompt: prompt, textResult: "Screenshot captured. Looking at it now.")
                } else {
                    result = captureResult
                }
            }

        case "control_ui":
            if let action = args["action"] {
                switch action {
                case "expand":
                    if state.displayState == .open {
                        result = "Already fully expanded."
                    } else {
                        NotificationCenter.default.post(name: .fridayExpand, object: nil)
                        result = "Expanded."
                    }
                case "collapse":
                    if state.displayState == .miniExpanded {
                        result = "Already in compact view."
                    } else {
                        NotificationCenter.default.post(name: .fridayCollapse, object: nil)
                        result = "Collapsed."
                    }
                case "switch_tab":
                    let tab = args["tab"] ?? "home"
                    switch tab {
                    case "music":     state.update(\.activeTab, to: .music)
                    case "calendar":  state.update(\.activeTab, to: .calendar)
                    case "reminders": state.update(\.activeTab, to: .reminders)
                    case "notes":     state.update(\.activeTab, to: .notes)
                    default:          state.update(\.activeTab, to: .home)
                    }
                    if state.displayState != .open {
                        NotificationCenter.default.post(name: .fridayExpand, object: nil)
                    }
                    result = "Switched to \(tab) tab."
                case "dismiss_task":
                    if let taskId = args["task_id"] {
                        state.dismissTask(id: taskId)
                        result = "Task '\(taskId)' dismissed."
                    } else {
                        state.dismissCompletedTasks()
                        result = "Completed tasks cleared."
                    }
                default:
                    result = "Unknown UI action: \(action)"
                }
            }

        case "get_ui_state":
            let panelDesc: String
            switch state.displayState {
            case .open:         panelDesc = "fully expanded"
            case .miniExpanded: panelDesc = "compact (mini-expanded)"
            case .mini:         panelDesc = "mini pill"
            case .dismissed:    panelDesc = "dormant"
            }
            let taskDesc = state.activeTasks.isEmpty ? "none" :
                state.activeTasks.map { "\($0.label) (\($0.status == .running ? "running" : $0.status == .done ? "done" : "error"))" }
                    .joined(separator: ", ")
            result = "Panel: \(panelDesc). Tab: \(state.activeTab.label). Tasks: \(taskDesc)."

        case "refresh_session":
            return .refreshSession(textResult: "Reconnecting now. I'll be right back.")

        case "disconnect_session":
            let dateStr: String = {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
            }()
            let notePath = "~/Documents/notes/projects/friday/sessions/\(dateStr).md"
            let msg = "Closing session. Write a brief session note to \(notePath) — what was worked on today, key decisions, what carries forward. Append to the file if it already exists. Then say a brief goodbye to Papa."
            return .disconnectSession(textResult: msg)

        default:
            result = "Tool not found."
        }
        
        return .text(result)
    }
}
