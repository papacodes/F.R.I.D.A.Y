import Foundation

struct TimeSkill {
    static func getCurrentTime() -> String {
        let df = DateFormatter()
        df.timeStyle = .short
        return df.string(from: Date())
    }

    static func getCurrentDate() -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        return df.string(from: Date())
    }
}
