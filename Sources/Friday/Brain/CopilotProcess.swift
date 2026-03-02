import Foundation

// Coding agent backend that delegates to GitHub Copilot CLI.
// Each call is stateless — no session continuity, reset() is a no-op.
// Completion is signalled by process exit code, not by a [TASK_DONE] marker.
// ANSI escape sequences are stripped from all stdout lines.
//
// NOT @MainActor — mirrors ClaudeProcess background-queue architecture.
final class CopilotProcess: @unchecked Sendable, CodingAgentProcess {

    let agentName = "Copilot"
    private(set) var isBusy = false

    private static let notesDirectory = "/Users/papa/Documents/notes"

    /// Resolved once at startup. Checks the Homebrew path first, falls back to `which copilot`.
    private static let copilotPath: String = {
        let homebrew = "/opt/homebrew/bin/copilot"
        if FileManager.default.fileExists(atPath: homebrew) { return homebrew }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "which copilot"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        p.standardInput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? "copilot" : path
    }()

    /// Prepended to every task so the model behaves like a silent coding assistant.
    private let preamble = "You are a coding assistant. Work directly and silently. When the task is complete, give a 1-2 sentence plain-text summary of what you did. No markdown, no code blocks, no preamble. "

    func ask(_ message: String, directory: String? = nil, maxTurns: Int = 15,
             onProgress: @escaping @Sendable (String) -> Void) async throws -> String {
        guard !isBusy else { return "[TASK_ERROR] Copilot is already busy with another task in this project." }
        isBusy = true
        defer { isBusy = false }

        print("Friday: → copilot \(directory ?? "notes") '\(message.prefix(60))'")
        let response = try await runStreaming(prompt: preamble + message, directory: directory, onProgress: onProgress)
        print("Friday: ← copilot '\(response.prefix(80))'")
        return response
    }

    func reset() { /* stateless — no session to reset */ }

    // MARK: - Private

    private func runStreaming(
        prompt: String,
        directory: String?,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Self.copilotPath)
            p.arguments = ["-p", prompt, "--allow-all", "--no-color"]

            let workDir = directory.map { NSString(string: $0).expandingTildeInPath } ?? Self.notesDirectory
            p.currentDirectoryURL = URL(fileURLWithPath: workDir)
            p.standardInput = FileHandle.nullDevice

            var env = ProcessInfo.processInfo.environment
            // Suppress TUI rendering that would corrupt the plain-text output stream.
            env["NO_COLOR"] = "1"
            env["TERM"] = "dumb"
            let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
            let existingPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = extraPaths.joined(separator: ":") + ":" + existingPath
            p.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            p.standardOutput = stdout
            p.standardError = stderr

            nonisolated(unsafe) var accumulated = ""
            nonisolated(unsafe) var lineBuffer = ""
            nonisolated(unsafe) var lastOutputTime = Date()
            nonisolated(unsafe) var lastProgressTime = Date.distantPast
            nonisolated(unsafe) var done = false

            let timeoutTimer = DispatchSource.makeTimerSource(queue: .global())
            timeoutTimer.schedule(deadline: .now() + 30, repeating: 30)
            timeoutTimer.setEventHandler {
                if !done && Date().timeIntervalSince(lastOutputTime) > 180 {
                    print("Friday: copilot timed out — no output for 180s")
                    p.terminate()
                }
            }
            timeoutTimer.resume()

            let hardDeadline = DispatchSource.makeTimerSource(queue: .global())
            hardDeadline.schedule(deadline: .now() + 300)
            hardDeadline.setEventHandler {
                if !done {
                    print("Friday: copilot hard timeout — 300s wall clock exceeded")
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
                accumulated += chunk

                while let newlineIdx = lineBuffer.firstIndex(of: "\n") {
                    let line = String(lineBuffer[lineBuffer.startIndex..<newlineIdx])
                    lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIdx)...])
                    let clean = stripANSI(line)
                    guard !clean.isEmpty else { continue }

                    let now = Date()
                    if now.timeIntervalSince(lastProgressTime) > 0.1 {
                        lastProgressTime = now
                        onProgress(clean)
                    }
                }
            }

            p.terminationHandler = { proc in
                done = true
                timeoutTimer.cancel()
                hardDeadline.cancel()
                stdout.fileHandleForReading.readabilityHandler = nil

                if !lineBuffer.isEmpty {
                    accumulated += lineBuffer
                }

                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                if let errText = String(data: errData, encoding: .utf8),
                   !errText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("Friday: copilot stderr — \(errText.prefix(300))")
                }

                let output = stripANSI(accumulated).trimmingCharacters(in: .whitespacesAndNewlines)
                if proc.terminationStatus == 0, !output.isEmpty {
                    cont.resume(returning: output)
                } else {
                    let reason = output.isEmpty ? "no output" : "exit \(proc.terminationStatus)"
                    cont.resume(returning: "[TASK_ERROR] Copilot failed (\(reason))")
                }
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

// MARK: - ANSI stripping

/// Walks the string's unicode scalars and removes ANSI CSI escape sequences (ESC [ ... final).
/// Regex-free for performance.
private func stripANSI(_ s: String) -> String {
    var result = ""
    result.reserveCapacity(s.count)
    let scalars = s.unicodeScalars
    var i = scalars.startIndex
    while i < scalars.endIndex {
        let c = scalars[i]
        if c.value == 0x1B {
            scalars.formIndex(after: &i)
            if i < scalars.endIndex && scalars[i].value == 0x5B { // '['
                scalars.formIndex(after: &i)
                while i < scalars.endIndex {
                    let b = scalars[i].value
                    scalars.formIndex(after: &i)
                    if b >= 0x40 && b <= 0x7E { break } // final byte
                }
            }
        } else {
            result.unicodeScalars.append(c)
            scalars.formIndex(after: &i)
        }
    }
    return result
}
