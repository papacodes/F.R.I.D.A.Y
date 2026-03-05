import Foundation

struct ToolRegistry {
    static let readFileTool = FunctionDecl(
        name: "read_file",
        description: "Read the full contents of a file. Use ~ for home directory. Supports all text files — Swift, Dart, Markdown, JSON, etc.",
        parameters: FunctionParams(
            type: "object",
            properties: ["path": ParamProperty(type: "STRING", description: "Absolute or ~-relative path to the file")],
            required: ["path"]
        )
    )

    static let writeFileTool = FunctionDecl(
        name: "write_file",
        description: "Write content to a file, creating it or overwriting it. Use this to create or fully replace files.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "path":    ParamProperty(type: "STRING", description: "Absolute or ~-relative path to the file"),
                "content": ParamProperty(type: "STRING", description: "The full content to write")
            ],
            required: ["path", "content"]
        )
    )

    static let listDirectoryTool = FunctionDecl(
        name: "list_directory",
        description: "List files and subdirectories in a directory. Hidden files are excluded.",
        parameters: FunctionParams(
            type: "object",
            properties: ["path": ParamProperty(type: "STRING", description: "Absolute or ~-relative path to the directory")],
            required: ["path"]
        )
    )

    static let runShellTool = FunctionDecl(
        name: "run_shell",
        description: "Run any zsh command — git, swift build, grep, find, sed, xcode-select, etc. Returns stdout and stderr. Always pass a directory when working in a specific project.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "command":   ParamProperty(type: "STRING", description: "The shell command to run"),
                "directory": ParamProperty(type: "STRING", description: "Optional working directory (e.g. ~/projects/friday)")
            ],
            required: ["command"]
        )
    )

    static let weatherTool = FunctionDecl(
        name: "get_weather",
        description: "Get the current weather.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    static let timeTool = FunctionDecl(
        name: "get_time",
        description: "Get the current date and time.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    static let batteryTool = FunctionDecl(
        name: "get_battery_status",
        description: "Get the current battery level, charging state, plug status, and whether Low Power Mode is active.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    static let mapTool = FunctionDecl(
        name: "find_nearby_places",
        description: "Find businesses, hospitals, restaurants, etc. nearby.",
        parameters: FunctionParams(
            type: "object",
            properties: ["query": ParamProperty(type: "STRING", description: "What to search for (e.g. hospital, pizza, gas)")],
            required: ["query"]
        )
    )

    static let searchTool = FunctionDecl(
        name: "web_search",
        description: "Search the web for current events, facts, or general knowledge.",
        parameters: FunctionParams(
            type: "object",
            properties: ["query": ParamProperty(type: "STRING", description: "The search query")],
            required: ["query"]
        )
    )

    static let musicTool = FunctionDecl(
        name: "control_music",
        description: "Control Apple Music playback (play, pause, next, search).",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "action": ParamProperty(type: "STRING", description: "The music command (play, pause, next, search)"),
                "query": ParamProperty(type: "STRING", description: "The song/artist to search and play (only for search action)")
            ],
            required: ["action"]
        )
    )

    static let playlistTool = FunctionDecl(
        name: "play_playlist",
        description: "Search for and play an Apple Music playlist by name.",
        parameters: FunctionParams(
            type: "object",
            properties: ["name": ParamProperty(type: "STRING", description: "The name of the playlist to play")],
            required: ["name"]
        )
    )

    static let notesTool = FunctionDecl(
        name: "manage_notes",
        description: "Full management of markdown notes in ~/Documents/notes.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "action": ParamProperty(type: "STRING", description: "create, read, append, list, or delete"),
                "filename": ParamProperty(type: "STRING", description: "The name of the note file"),
                "content": ParamProperty(type: "STRING", description: "The content to write or append")
            ],
            required: ["action"]
        )
    )

    static let remindersTool = FunctionDecl(
        name: "manage_reminders",
        description: "Create or list macOS reminders.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "action": ParamProperty(type: "STRING", description: "add or list"),
                "title": ParamProperty(type: "STRING", description: "Reminder title"),
                "due_date": ParamProperty(type: "STRING", description: "Optional due date (natural language like 'tomorrow at 10am')")
            ],
            required: ["action"]
        )
    )

    static let calendarTool = FunctionDecl(
        name: "manage_calendar",
        description: "Read or create events in the user's local Calendar. Use get_schedule to check what's on for a day. Use add to create a new event.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "action":     ParamProperty(type: "STRING", description: "get_schedule or add"),
                "date":       ParamProperty(type: "STRING", description: "For get_schedule: the day to check. Use plain English — 'today', 'tomorrow', 'next Monday', 'March 5'. Omit for today."),
                "title":      ParamProperty(type: "STRING", description: "For add: event title"),
                "start_time": ParamProperty(type: "STRING", description: "For add: start time in plain English, e.g. 'today at 3pm', 'tomorrow at 9am'"),
                "end_time":   ParamProperty(type: "STRING", description: "For add: end time in plain English. Omit to default to 1 hour after start.")
            ],
            required: ["action"]
        )
    )

    static let executeDevTaskTool = FunctionDecl(
        name: "execute_dev_task",
        description: "Execute a development task using a coding agent (Claude Code by default, or Gemini CLI / GitHub Copilot as alternatives). Use for code analysis, making changes, debugging, or any task requiring understanding of a code project. Always pass project_path. Keep the task tightly scoped — one specific question or change, not 'look at everything'. Pass max_turns=5 for read-only questions, 15 for changes.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "task":         ParamProperty(type: "STRING", description: "The specific task or question for the coding agent. Be precise and scoped."),
                "project_path": ParamProperty(type: "STRING", description: "Absolute path to the project (e.g. ~/projects/friday, ~/projects/oats). Required for code projects."),
                "max_turns":    ParamProperty(type: "STRING", description: "Turn budget for Claude Code. Pass \"5\" for lookups/reads, \"15\" for edits. Default 15."),
                "agent":        ParamProperty(type: "STRING", description: "Which coding agent: \"claude\" (default), \"gemini\", or \"copilot\". Omit for Claude. Use \"gemini\" or \"copilot\" when rate-limited or when Papa requests a different agent.")
            ],
            required: ["task"]
        )
    )

    static let ragTool = FunctionDecl(
        name: "retrieve_knowledge",
        description: "Search Papa's notes for relevant information — past decisions, project context, session history, standards, lessons learned. Use this instead of read_file when looking up knowledge from notes. Returns the most relevant excerpts only.",
        parameters: FunctionParams(
            type: "object",
            properties: ["query": ParamProperty(type: "STRING", description: "Natural language description of what you're looking for")],
            required: ["query"]
        )
    )

    static let disconnectTool = FunctionDecl(
        name: "disconnect_session",
        description: "Immediately disconnect the live session and go to sleep. Use this when the user says goodbye or tells you to stop listening.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    static let refreshSessionTool = FunctionDecl(
        name: "refresh_session",
        description: "Reconnect with a fresh context window. Call this when approaching session limits or when Papa asks to reconnect. Always save session notes with manage_notes BEFORE calling this.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    static let getUiStateTool = FunctionDecl(
        name: "get_ui_state",
        description: "Get the current state of the Friday UI — panel size, active tab, running tasks. Call this before taking UI actions so you know what's already showing.",
        parameters: FunctionParams(type: "object", properties: [:], required: [])
    )

    static let controlUiTool = FunctionDecl(
        name: "control_ui",
        description: "Control the Friday UI. Use get_ui_state first to know what's already showing before acting.",
        parameters: FunctionParams(
            type: "object",
            properties: [
                "action":  ParamProperty(type: "STRING", description: "expand, collapse, switch_tab, or dismiss_task"),
                "tab":     ParamProperty(type: "STRING", description: "For switch_tab: home, music, calendar, reminders, notes"),
                "task_id": ParamProperty(type: "STRING", description: "For dismiss_task: the project key (e.g. 'friday', 'oats'). Omit to dismiss all completed tasks.")
            ],
            required: ["action"]
        )
    )

    static let captureScreenTool = FunctionDecl(
        name: "capture_screen",
        description: "Capture a screenshot of Papa's screen so you can see what he's looking at. Only call this when he explicitly asks you to look at his screen or says he needs visual help. This is privacy-sensitive — never capture passively.",
        parameters: FunctionParams(
            type: "object",
            properties: ["prompt": ParamProperty(type: "STRING", description: "What to look for or answer based on the screenshot")],
            required: ["prompt"]
        )
    )

    static let allTools: [FunctionDecl] = [
        ragTool, executeDevTaskTool, readFileTool, writeFileTool, listDirectoryTool, runShellTool,
        weatherTool, timeTool, batteryTool, mapTool, searchTool, musicTool,
        playlistTool, notesTool, remindersTool, calendarTool, disconnectTool, refreshSessionTool,
        getUiStateTool, controlUiTool, captureScreenTool
    ]
}
