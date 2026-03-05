import Foundation

@MainActor
protocol FridayBrain: AnyObject {
    /// Starts the background initialization of the brain (connecting to APIs or loading local models).
    func start() async
    
    /// Wakes the brain up, starts listening, and optionally sends a greeting.
    func wake() async
    
    /// Puts the brain to sleep and stops listening.
    func sleep() async
    
    /// Immediately stops all processing and shuts down the brain.
    func stop()
    
    /// Gracefully ends the session (e.g. saves notes, says goodbye) before stopping.
    func startGracefulStop()
    
    /// Fully restarts the brain, clearing any error states.
    func restart() async
}
