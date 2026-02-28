import Foundation

// Direct file system access for Friday's dev capabilities.
// Gemini calls these tools to read, write, and navigate the file system.
struct FileSystemSkill {

    private static let maxReadLength = 8000

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
            return annotated.isEmpty ? "(empty)" : annotated.joined(separator: "\n")
        } catch {
            return "Error listing \(expanded): \(error.localizedDescription)"
        }
    }
}
