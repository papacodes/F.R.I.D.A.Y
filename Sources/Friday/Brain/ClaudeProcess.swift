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

    func ask(_ message: String) async throws -> String {
        var args: [String] = ["--print", "--model", "sonnet"]

        if hasSession {
            args += ["--continue", message]
        } else {
            args.append(preamble + message)
        }

        print("Friday: → claude '\(message.prefix(60))'")
        let response = try await run(args: args)
        print("Friday: ← '\(response.prefix(80))'")

        if !response.isEmpty { hasSession = true }
        return response
    }

    func reset() { hasSession = false }

    // MARK: - Private

    private func run(args: [String]) async throws -> String {
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

            nonisolated(unsafe) var done = false
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
                if !done { print("Friday: claude timed out"); p.terminate() }
            }

            p.terminationHandler = { _ in
                done = true
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                let err = stderr.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: out, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errText = String(data: err, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !errText.isEmpty { print("Friday: claude stderr — \(errText)") }
                cont.resume(returning: text)
            }

            do { try p.run() }
            catch { cont.resume(throwing: error) }
        }
    }
}
