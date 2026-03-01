import Foundation

// Dev brain — handles software development tasks via Claude Code CLI.
// Called only when Gemini routes a query via the execute_dev_task tool.
// Runs from the specified project directory so Claude has full code context.
//
// NOT @MainActor — background callbacks (readabilityHandler, terminationHandler)
// run on dispatch queues and must not inherit actor isolation. The GeminiVoicePipeline's
// @MainActor context serializes all calls to this class in practice.
final class ClaudeProcess: @unchecked Sendable {

    private var hasSession = false
    private var isBusy = false
    private var taskCount = 0
    /// After this many tasks, silently drop --continue and start a fresh Claude session.
    /// Prevents unbounded context growth from accumulated tool calls across many dev tasks.
    private let sessionResetThreshold = 8

    private static let claudePath: String = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "which claude"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        p.standardInput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? "claude" : path
    }()

    private static let notesDirectory = "/Users/papa/Documents/notes"

    /// Prefixed to the first message in each fresh session.
    /// Work silently — tool calls surface in the UI. Only the final summary goes back to Gemini.
    private let preamble = "[You are Friday's dev backend. Work silently — no commentary between tool calls. When done, respond in 1-2 plain sentences only — no markdown, no code blocks, no preamble. End your final sentence with [TASK_DONE].] "

    /// Ask Claude Code to perform a development task.
    /// - Parameters:
    ///   - message: The task description
    ///   - directory: Working directory (defaults to notes). Pass the project path for code tasks.
    ///   - maxTurns: Turn budget. Use 5 for lookups, 15 for changes. Defaults to 15.
    ///   - onProgress: Called from a background thread as Claude streams output — callers dispatch to MainActor.
    func ask(_ message: String, directory: String? = nil, maxTurns: Int = 15, onProgress: @escaping @Sendable (String) -> Void) async throws -> String {
        guard !isBusy else { return "[TASK_ERROR] Claude is already busy with another task in this project." }
        isBusy = true
        defer { isBusy = false }
        var args: [String] = [
            "--print",
            "--verbose",
            "--model", "claude-sonnet-4-6",
            "--output-format", "stream-json",
            "--max-turns", "\(maxTurns)"
        ]

        // Auto-reset: drop --continue after sessionResetThreshold tasks to prevent
        // Claude's own context from growing unboundedly across many execute_dev_task calls.
        if hasSession && taskCount >= sessionResetThreshold {
            print("Friday: ClaudeProcess session reset after \(taskCount) tasks")
            hasSession = false
            taskCount = 0
        }

        if hasSession {
            args += ["--continue", message]
        } else {
            args.append(preamble + message)
        }

        print("Friday: → claude \(directory ?? "notes") '\(message.prefix(60))'")
        let response = try await runStreaming(args: args, directory: directory, onProgress: onProgress)
        print("Friday: ← '\(response.prefix(80))'")

        if !response.isEmpty {
            hasSession = true
            taskCount += 1
        }
        return response
    }

    func reset() { hasSession = false; taskCount = 0 }

    // MARK: - Private

    private func runStreaming(
        args: [String],
        directory: String?,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Self.claudePath)
            p.arguments = args

            // Use the provided project directory, or fall back to notes
            let workDir = directory.map { NSString(string: $0).expandingTildeInPath } ?? Self.notesDirectory
            p.currentDirectoryURL = URL(fileURLWithPath: workDir)
            p.standardInput = FileHandle.nullDevice

            // Strip only CLAUDE_SESSION vars to prevent context bleed — keep auth vars intact
            var env = ProcessInfo.processInfo.environment
            env.removeValue(forKey: "CLAUDE_SESSION_ID")

            // Augment PATH with known dev tool locations that may be absent when Friday
            // launches from a GUI context or a shell that hasn't sourced the full profile.
            let extraPaths = [
                "/Users/papa/Projects/dev-tools/flutter/bin",  // Flutter / Dart
                "/opt/homebrew/bin",                           // Homebrew (M-series)
                "/usr/local/bin"                               // Homebrew (Intel), misc
            ]
            let existingPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = extraPaths.joined(separator: ":") + ":" + existingPath
            p.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            p.standardOutput = stdout
            p.standardError = stderr

            nonisolated(unsafe) var finalResult = ""
            nonisolated(unsafe) var lineBuffer = ""
            nonisolated(unsafe) var lastOutputTime = Date()   // tracks last data arrival — for no-output timeout
            nonisolated(unsafe) var lastProgressTime = Date.distantPast  // tracks last onProgress call — for throttle
            nonisolated(unsafe) var done = false

            // Rolling timeout: terminate if no stdout for 180s (generous for large tasks).
            // This alone isn't enough — --verbose mode outputs rate-limit retry messages every few
            // seconds, which resets lastOutputTime and keeps the process alive indefinitely.
            let timeoutTimer = DispatchSource.makeTimerSource(queue: .global())
            timeoutTimer.schedule(deadline: .now() + 30, repeating: 30)
            timeoutTimer.setEventHandler {
                if !done && Date().timeIntervalSince(lastOutputTime) > 180 {
                    print("Friday: claude timed out — no output for 180s")
                    p.terminate()
                }
            }
            timeoutTimer.resume()

            // Hard wall-clock cap: kill after 300s regardless of output volume.
            // Prevents --verbose rate-limit retries from hanging tasks indefinitely.
            let hardDeadline = DispatchSource.makeTimerSource(queue: .global())
            hardDeadline.schedule(deadline: .now() + 300)
            hardDeadline.setEventHandler {
                if !done {
                    print("Friday: claude hard timeout — 300s wall clock exceeded")
                    p.terminate()
                }
            }
            hardDeadline.resume()

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                lastOutputTime = Date()

                guard let chunk = String(data: data, encoding: .utf8) else { return }
                lineBuffer += chunk

                while let newlineIdx = lineBuffer.firstIndex(of: "\n") {
                    let line = String(lineBuffer[lineBuffer.startIndex..<newlineIdx])
                    lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIdx)...])
                    guard !line.isEmpty else { continue }

                    if let parsed = parseStreamLine(line) {
                        if let result = parsed.result { finalResult = result }
                        if let progress = parsed.progress {
                            // Throttle UI updates to 10Hz — use lastProgressTime, not lastOutputTime.
                            // lastOutputTime is reset on every data chunk so checking it here always
                            // gives ~0ms — which permanently suppressed onProgress. Bug fixed.
                            let now = Date()
                            if now.timeIntervalSince(lastProgressTime) > 0.1 {
                                lastProgressTime = now
                                onProgress(progress)
                            }
                        }
                    }
                }
            }

            p.terminationHandler = { _ in
                done = true
                timeoutTimer.cancel()
                hardDeadline.cancel()
                stdout.fileHandleForReading.readabilityHandler = nil

                if !lineBuffer.isEmpty, let parsed = parseStreamLine(lineBuffer) {
                    if let result = parsed.result { finalResult = result }
                }

                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                if let errText = String(data: errData, encoding: .utf8),
                   !errText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("Friday: claude stderr — \(errText.prefix(300))")
                }

                cont.resume(returning: finalResult)
            }

            do { try p.run() }
            catch {
                timeoutTimer.cancel()
                hardDeadline.cancel()
                cont.resume(throwing: error)
            }
        }
    }
}

// MARK: - stream-json parsing

private struct ParsedLine {
    var result: String?
    var progress: String?
}

private func parseStreamLine(_ line: String) -> ParsedLine? {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    var parsed = ParsedLine()
    let type = obj["type"] as? String ?? ""

    switch type {
    case "system":
        parsed.progress = "Starting up..."

    case "assistant":
        guard let msg = obj["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]]
        else { break }

        for part in content {
            let partType = part["type"] as? String ?? ""
            if partType == "tool_use" {
                let name = part["name"] as? String ?? ""
                let input = part["input"] as? [String: Any] ?? [:]
                parsed.progress = humanReadableToolUse(name: name, input: input)
                break
            } else if partType == "text", let text = part["text"] as? String {
                let snippet = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !snippet.isEmpty {
                    // Claude's own narration — pass it through as progress
                    parsed.progress = String(snippet.prefix(80))
                }
            }
        }

    case "result":
        if let result = obj["result"] as? String {
            parsed.result = result
        }
        if let isError = obj["isError"] as? Bool, isError {
            parsed.progress = "Error occurred"
        }

    default:
        break
    }

    return parsed
}

/// Converts a raw tool call into a readable status line for the activity feed.
private func humanReadableToolUse(name: String, input: [String: Any]) -> String {
    switch name {
    case "read_file", "read":
        let path = (input["path"] as? String) ?? (input["file_path"] as? String) ?? ""
        return "Reading \(path.isEmpty ? "file" : URL(fileURLWithPath: path).lastPathComponent)"
    case "write_file", "write":
        let path = (input["path"] as? String) ?? (input["file_path"] as? String) ?? ""
        return "Writing \(path.isEmpty ? "file" : URL(fileURLWithPath: path).lastPathComponent)"
    case "list_directory", "list_files", "glob":
        let path = (input["path"] as? String) ?? (input["pattern"] as? String) ?? ""
        return "Listing \(path.isEmpty ? "directory" : URL(fileURLWithPath: path).lastPathComponent)"
    case "bash", "run_shell", "execute":
        let cmd = (input["command"] as? String) ?? ""
        return cmd.isEmpty ? "Running command" : String(cmd.prefix(50))
    case "grep", "search", "search_files":
        let pattern = (input["pattern"] as? String) ?? (input["query"] as? String) ?? ""
        return "Searching: \(pattern.prefix(40))"
    case "edit_file", "str_replace_editor":
        let path = (input["path"] as? String) ?? (input["file_path"] as? String) ?? ""
        return "Editing \(path.isEmpty ? "file" : URL(fileURLWithPath: path).lastPathComponent)"
    default:
        return name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
