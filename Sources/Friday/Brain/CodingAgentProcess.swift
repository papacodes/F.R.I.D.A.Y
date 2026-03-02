import Foundation

enum CodingAgentID: String {
    case claude, gemini, copilot
}

protocol CodingAgentProcess: AnyObject, Sendable {
    var agentName: String { get }
    var isBusy: Bool { get }
    func ask(_ message: String, directory: String?, maxTurns: Int,
             onProgress: @escaping @Sendable (String) -> Void) async throws -> String
    func reset()
}
