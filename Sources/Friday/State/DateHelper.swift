import Foundation

struct DateHelper {
    /// Returns a string like 'March 1, 2026 15:00:00' which is generally robust for AppleScript
    static func formatForAppleScript(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d, yyyy HH:mm:ss"
        return formatter.string(from: date)
    }

    /// Parses various formats from Gemini and returns an AppleScript-friendly string
    static func parseAndFormat(_ input: String) -> String {
        let clean = input.lowercased()
        let now = Date()
        let calendar = Calendar.current

        if clean.contains("tomorrow") {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            return formatForAppleScript(tomorrow)
        }
        if clean.contains("today") {
            return formatForAppleScript(now)
        }

        // Fallback to data detector for natural language parsing
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = detector?.matches(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count))
        
        if let date = matches?.first?.date {
            return formatForAppleScript(date)
        }

        return input // Return original if all else fails
    }
}
