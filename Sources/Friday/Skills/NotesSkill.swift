import Foundation

struct NotesSkill {
    static let notesDirectory = "/Users/papa/Documents/notes"

    static func createNote(filename: String, content: String) -> String {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: notesDirectory)
        if !fileManager.fileExists(atPath: notesDirectory) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        let fileURL = directoryURL.appendingPathComponent(filename.hasSuffix(".md") ? filename : "\(filename).md")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return "Successfully created note: \(filename)"
        } catch {
            return "Failed to create note: \(error.localizedDescription)"
        }
    }

    static func readNote(filename: String) -> String {
        let fileURL = URL(fileURLWithPath: notesDirectory).appendingPathComponent(filename.hasSuffix(".md") ? filename : "\(filename).md")
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return "Error reading note: \(error.localizedDescription)"
        }
    }

    static func appendToNote(filename: String, content: String) -> String {
        let fileURL = URL(fileURLWithPath: notesDirectory).appendingPathComponent(filename.hasSuffix(".md") ? filename : "\(filename).md")
        guard let fileHandle = try? FileHandle(forWritingTo: fileURL) else {
            return createNote(filename: filename, content: content)
        }
        do {
            fileHandle.seekToEndOfFile()
            let separator = "\n\n---\n\n" + content
            if let data = separator.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
            return "Successfully updated note: \(filename)"
        } catch {
            return "Failed to update note: \(error.localizedDescription)"
        }
    }

    static func listNotes() -> String {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: notesDirectory) else {
            return "No notes found."
        }
        let mdFiles = files.filter { $0.hasSuffix(".md") }.prefix(20)
        if mdFiles.isEmpty { return "No markdown notes found." }
        return "Notes in workspace:\n" + mdFiles.joined(separator: "\n")
    }
    
    static func deleteNote(filename: String) -> String {
        let fileURL = URL(fileURLWithPath: notesDirectory).appendingPathComponent(filename.hasSuffix(".md") ? filename : "\(filename).md")
        do {
            try FileManager.default.removeItem(at: fileURL)
            return "Successfully deleted note: \(filename)"
        } catch {
            return "Error deleting note: \(error.localizedDescription)"
        }
    }
}
