import Foundation

// Routes execute_dev_task calls to the appropriate coding agent backend.
// Maintains one instance per (agentID, projectKey) pair so session continuity
// is preserved per-project for Claude while Gemini/Copilot remain stateless.
//
// Not @MainActor — accessed only from GeminiVoicePipeline's @MainActor context.
final class CodingAgentRouter {

    /// Default agent used when no explicit agent arg is provided.
    var preferred: CodingAgentID = .claude

    /// Keyed by "\(agentID.rawValue)/\(projectKey)".
    private var instances: [String: any CodingAgentProcess] = [:]

    /// Returns the agent instance for the given (agentID, projectKey) pair, creating it on first use.
    func resolve(agentID: CodingAgentID?, projectKey: String) -> any CodingAgentProcess {
        let id = agentID ?? preferred
        let key = "\(id.rawValue)/\(projectKey)"
        if let existing = instances[key] { return existing }
        let instance: any CodingAgentProcess
        switch id {
        case .claude:  instance = ClaudeProcess()
        case .gemini:  instance = GeminiCLIProcess()
        case .copilot: instance = CopilotProcess()
        }
        instances[key] = instance
        return instance
    }

    /// Resets all agent instances and clears the pool.
    func resetAll() {
        instances.values.forEach { $0.reset() }
        instances.removeAll()
    }
}
