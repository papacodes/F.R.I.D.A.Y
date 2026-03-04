import Foundation

struct Config {
    static let shared = Config()
    
    let apiKey: String?

    private init() {
        self.apiKey = Config.loadEnv()["GEMINI_API_KEY"] ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
    }

    private static func loadEnv() -> [String: String] {
        var results: [String: String] = [:]
        
        // Try to find .env in current directory or project root
        let paths = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"),
            URL(fileURLWithPath: "/Users/papa/projects/friday/.env")
        ]

        for url in paths {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    let parts = line.components(separatedBy: "=")
                    if parts.count == 2 {
                        results[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
                break
            }
        }
        return results
    }
}
