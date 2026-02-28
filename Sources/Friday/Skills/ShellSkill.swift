import Foundation

// Shell execution for Friday's dev capabilities.
// Runs through /bin/zsh -lc so PATH and env are fully loaded.
// All execution happens off the main thread — safe to await from @MainActor.
struct ShellSkill {

    private static let maxOutputLength = 6000
    private static let timeoutSeconds: TimeInterval = 90

    static func run(_ command: String, directory: String? = nil) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runSync(command, directory: directory))
            }
        }
    }

    private static func runSync(_ command: String, directory: String?) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        p.standardInput = FileHandle.nullDevice

        if let dir = directory {
            let expanded = (dir as NSString).expandingTildeInPath
            p.currentDirectoryURL = URL(fileURLWithPath: expanded)
        }

        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr

        do { try p.run() } catch {
            return "Failed to start command: \(error.localizedDescription)"
        }

        let sem = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in sem.signal() }

        if sem.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            p.terminate()
            return "Command timed out after \(Int(timeoutSeconds))s."
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        var out = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !err.isEmpty {
            out = out.isEmpty ? err : "\(out)\n---\n\(err)"
        }

        if out.isEmpty {
            out = p.terminationStatus == 0 ? "(no output)" : "(exit \(p.terminationStatus), no output)"
        }

        if out.count > maxOutputLength {
            out = String(out.prefix(maxOutputLength)) + "\n... [truncated — \(out.count) chars total]"
        }

        return out
    }
}
