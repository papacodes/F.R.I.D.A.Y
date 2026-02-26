import Foundation

// Determines which Claude model handles a given query.
// Light → haiku (fast, cheap, no session overhead)
// Medium → sonnet (default, session continuity)
// Heavy → opus (deep reasoning, session continuity)
enum QueryTier {
    case light, medium, heavy

    // Short alias accepted by `claude --model`
    var modelAlias: String {
        switch self {
        case .light:  return "haiku"
        case .medium: return "sonnet"
        case .heavy:  return "opus"
        }
    }

    static func classify(_ text: String) -> QueryTier {
        let lower = text.lowercased()
        let words = text.split(separator: " ").count

        // Heavy: explicit deep-work signals in longer queries
        let heavySignals = [
            "plan ", "design ", "architect", "walk me through",
            "in detail", "step by step", "help me build", "write a complete",
            "create a full", "explain everything",
        ]
        if words > 12 && heavySignals.contains(where: { lower.contains($0) }) {
            return .heavy
        }

        // Light: short or clearly simple/conversational
        if words <= 7 { return .light }
        let lightSignals = [
            "what time", "what's the time", "what is the time",
            "how are you", "good morning", "good afternoon",
            "good evening", "good night", "thank you", "thanks",
            "write a note", "read my note", "remind me",
            "weather", "joke", "what day", "what's today",
        ]
        if lightSignals.contains(where: { lower.contains($0) }) { return .light }

        return .medium
    }
}

@MainActor
final class ClaudeProcess {

    // Session only tracked for medium/heavy queries — light queries are stateless
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

    private let preamble = "[You are Friday, Papa's voice assistant. Reply in 1-2 short spoken sentences. No markdown.] "

    // Fire-and-forget: starts the claude Node.js process so the OS caches the binary.
    func preWarm() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.claudePath)
        p.arguments = ["--print", "--no-session-persistence", "--model", "haiku", "ready"]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        var env = ProcessInfo.processInfo.environment
        for key in env.keys where key.hasPrefix("CLAUDE") { env.removeValue(forKey: key) }
        p.environment = env
        try? p.run()
        print("Friday: pre-warming claude (haiku)")
    }

    // Notes workspace — gives Claude context about all projects
    private static let notesDirectory = "/Users/papa/Documents/notes"

    func ask(_ message: String) async throws -> String {
        let tier = QueryTier.classify(message)
        var args: [String] = ["--print", "--model", tier.modelAlias]
        let workDir: String

        switch tier {
        case .light:
            // Stateless, no project context — fastest path
            args += ["--no-session-persistence", preamble + message]
            workDir = NSHomeDirectory()
        case .medium, .heavy:
            // Run from notes workspace so Claude has project context
            workDir = Self.notesDirectory
            if hasSession {
                args += ["--continue", message]
            } else {
                args.append(preamble + message)
            }
        }

        print("Friday: → \(tier.modelAlias) '\(args.last?.prefix(60) ?? "")'")
        let response = try await run(args: args, workingDirectory: workDir)
        print("Friday: ← '\(response.prefix(80))'")

        if tier != .light, !response.isEmpty { hasSession = true }
        return response
    }

    func reset() { hasSession = false }

    // MARK: - Private

    private func run(args: [String], workingDirectory: String = NSHomeDirectory()) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Self.claudePath)
            p.arguments = args
            p.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            p.standardInput = FileHandle.nullDevice

            var env = ProcessInfo.processInfo.environment
            for key in env.keys where key.hasPrefix("CLAUDE") { env.removeValue(forKey: key) }
            p.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            p.standardOutput = stdout
            p.standardError = stderr

            nonisolated(unsafe) var done = false
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
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
                if !errText.isEmpty { print("Friday: stderr — \(errText)") }
                cont.resume(returning: text)
            }

            do { try p.run() }
            catch { cont.resume(throwing: error) }
        }
    }
}
