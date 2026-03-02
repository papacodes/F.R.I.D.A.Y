import Foundation

struct DateHelper {
    /// Parses natural language date strings from Gemini into a concrete Date.
    /// Handles: "today at 3pm", "tomorrow at 9am", ISO 8601, bare "today"/"tomorrow".
    static func parseDate(_ input: String) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // NSDataDetector — handles rich natural language with time components
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let date = detector?.matches(in: trimmed, options: [], range: range).first?.date {
            return date
        }

        // ISO 8601 (e.g. "2026-03-02T09:00:00Z")
        if let date = ISO8601DateFormatter().date(from: trimmed) { return date }

        // Bare keywords — no time component, returns start of day
        let clean = trimmed.lowercased()
        let cal = Calendar.current
        if clean.hasPrefix("today")    { return cal.startOfDay(for: Date()) }
        if clean.hasPrefix("tomorrow") { return cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!) }

        return nil
    }

    /// Kept for any legacy AppleScript callers that still need a formatted string.
    static func parseAndFormat(_ input: String) -> String {
        guard let date = parseDate(input) else { return input }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d, yyyy HH:mm:ss"
        return formatter.string(from: date)
    }
}
