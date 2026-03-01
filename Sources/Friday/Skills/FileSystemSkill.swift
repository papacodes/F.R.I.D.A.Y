import Foundation

// Direct file system access for Friday's dev capabilities.
// Gemini calls these tools to read, write, and navigate the file system.
struct FileSystemSkill {

    private static let maxReadLength = 3000

    static func readFile(path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        do {
            var content = try String(contentsOfFile: expanded, encoding: .utf8)
            if content.count > maxReadLength {
                content = String(content.prefix(maxReadLength))
                    + "\n\n... [file truncated at \(maxReadLength) chars — use run_shell with tail/sed to read a specific range]"
            }
            return content
        } catch {
            return "Error reading \(expanded): \(error.localizedDescription)"
        }
    }

    static func writeFile(path: String, content: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "Written to \(expanded) (\(content.count) chars)."
        } catch {
            return "Error writing \(expanded): \(error.localizedDescription)"
        }
    }

    private static let maxDirectoryEntries = 60

    static func listDirectory(path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: expanded)
            let sorted = items.filter { !$0.hasPrefix(".") }.sorted()
            let annotated = sorted.map { name -> String in
                var isDir: ObjCBool = false
                let full = (expanded as NSString).appendingPathComponent(name)
                FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
                return isDir.boolValue ? "\(name)/" : name
            }
            if annotated.isEmpty { return "(empty)" }
            if annotated.count > maxDirectoryEntries {
                let shown = annotated.prefix(maxDirectoryEntries).joined(separator: "\n")
                return "\(shown)\n... [\(annotated.count - maxDirectoryEntries) more entries not shown — use run_shell with find/ls to filter]"
            }
            return annotated.joined(separator: "\n")
        } catch {
            return "Error listing \(expanded): \(error.localizedDescription)"
        }
    }
}
