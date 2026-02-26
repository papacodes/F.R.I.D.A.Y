import Foundation

struct RemindersSkill {
    static func addReminder(title: String, dueDate: String?) -> String {
        var script = "tell application \"Reminders\"\n"
        script += "make new reminder with properties {name:\"\(title)\""
        if let date = dueDate {
            script += ", remind me date:date \"\(date)\""
        }
        script += "}\n"
        script += "return \"Added reminder: \(title)\"\n"
        script += "end tell"
        
        return MusicSkill.executeAppleScript(script)
    }

    static func listReminders() -> String {
        let script = "tell application \"Reminders\"\nset todoList to name of every reminder whose completed is false\nreturn todoList\nend tell"
        return MusicSkill.executeAppleScript(script)
    }
}
