import Foundation

// Dev brain — handles software development tasks via Claude Code CLI.
// Called only when Gemini routes a query via the execute_dev_task tool.
// Always runs with the notes workspace as context so Claude has project history.
@MainActor
final class ClaudeProcess {

    private var hasSession = false

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

    private let preamble = "[You are Friday's dev backend. Return a brief spoken summary of what was done — no markdown, no preamble.] "

    /// onProgress is called from a background thread — callers must dispatch to MainActor themselves.
    func ask(_ message: String, onProgress: @escaping @Sendable (String) -> Void) async throws -> String {
        var args: [String] = [
            "--print",
            "--model", "claude-sonnet-4-6",
            "--output-format", "stream-json",
            "--max-turns", "10"
        ]

        if hasSession {
            args += ["--continue", message]
        } else {
            args.append(preamble + message)
        }

        print("Friday: → claude '\(message.prefix(60))'")
        let response = try await runStreaming(args: args, onProgress: onProgress)
        print("Friday: ← '\(response.prefix(80))'")

        if !response.isEmpty { hasSession = true }
        return response
    }

    func reset() { hasSession = false }

    // MARK: - Private

    private func runStreaming(
        args: [String],
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Self.claudePath)
            p.arguments = args
            p.currentDirectoryURL = URL(fileURLWithPath: Self.notesDirectory)
            p.standardInput = FileHandle.nullDevice

            var env = ProcessInfo.processInfo.environment
            for key in env.keys where key.hasPrefix("CLAUDE") { env.removeValue(forKey: key) }
            p.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            p.standardOutput = stdout
            p.standardError = stderr

            nonisolated(unsafe) var finalResult = ""
            nonisolated(unsafe) var lineBuffer = ""
            nonisolated(unsafe) var lastOutputTime = Date()
            nonisolated(unsafe) var done = false

            // Rolling timeout: terminate if no stdout for 120s
            let timeoutTimer = DispatchSource.makeTimerSource(queue: .global())
            timeoutTimer.schedule(deadline: .now() + 15, repeating: 15)
            timeoutTimer.setEventHandler {
                if !done && Date().timeIntervalSince(lastOutputTime) > 120 {
                    print("Friday: claude timed out — no output for 120s")
                    p.terminate()
                }
            }
            timeoutTimer.resume()

            // Stream stdout line by line as Claude works
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                lastOutputTime = Date()

                guard let chunk = String(data: data, encoding: .utf8) else { return }
                lineBuffer += chunk

                // Process all complete newline-terminated lines
                while let newlineIdx = lineBuffer.firstIndex(of: "\n") {
                    let line = String(lineBuffer[lineBuffer.startIndex..<newlineIdx])
                    lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIdx)...])
                    guard !line.isEmpty else { continue }

                    if let parsed = parseStreamLine(line) {
                        if let result = parsed.result { finalResult = result }
                        if let progress = parsed.progress { onProgress(progress) }
                    }
                }
            }

            p.terminationHandler = { _ in
                done = true
                timeoutTimer.cancel()
                stdout.fileHandleForReading.readabilityHandler = nil

                // Flush remaining buffer
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
                cont.resume(throwing: error)
            }
        }
    }
}

// MARK: - stream-json parsing (free function so it can be called from nonisolated context)

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
        parsed.progress = "Claude starting..."

    case "assistant":
        guard let msg = obj["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]]
        else { break }

        for part in content {
            let partType = part["type"] as? String ?? ""
            if partType == "tool_use", let name = part["name"] as? String {
                parsed.progress = "→ \(name)"
                break  // report first tool per message
            } else if partType == "text", let text = part["text"] as? String {
                let snippet = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !snippet.isEmpty {
                    parsed.progress = String(snippet.prefix(70))
                }
            }
        }

    case "result":
        if let result = obj["result"] as? String {
            parsed.result = result
        }
        if let isError = obj["isError"] as? Bool, isError {
            parsed.progress = "✗ Error"
        }

    default:
        break
    }

    return parsed
}
