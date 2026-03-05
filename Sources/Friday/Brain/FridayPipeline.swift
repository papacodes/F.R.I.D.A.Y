import Foundation
import SwiftUI

@MainActor
final class FridayPipeline: FridayBrain {
    private let state = FridayState.shared
    private let local: LocalVoicePipeline
    private let cloud: GeminiVoicePipeline
    
    private var active: FridayBrain {
        state.isLocalMode ? local : (cloud as FridayBrain)
    }
    
    init() {
        self.local = LocalVoicePipeline(state: FridayState.shared)
        self.cloud = GeminiVoicePipeline(state: FridayState.shared)
    }
    
    func start() async {
        local.start()
        await cloud.start()
    }
    
    func wake() async {
        if state.isLocalMode {
            cloud.stop()
        } else {
            await local.sleep()
        }
        await active.wake()
    }
    
    func sleep() async { await active.sleep() }
    func stop() { local.stop(); cloud.stop() }
    func startGracefulStop() { active.startGracefulStop() }
    func restart() async { await active.restart() }
}
