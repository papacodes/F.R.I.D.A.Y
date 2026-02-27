import Foundation
import SwiftUI

extension Notification.Name {
    static let fridayTrigger = Notification.Name("fridayTrigger")
}

@MainActor
final class FridayState: ObservableObject {
    static let shared = FridayState()
    private init() {}

    @Published var isListening = false
    @Published var isThinking = false
    @Published var isSpeaking = false
    @Published var isError = false
    @Published var transcript = ""
    @Published var volume: Float = 0.0
    
    @Published var isExpanded = false
    @Published var closedNotchSize: CGSize = CGSize(width: 200, height: 32)
    @Published var showInfoCard = false
    @Published var modelName = "Gemini 2.5 Flash"
    @Published var hasGreetedThisSession = false

    @Published var lastActivityTime = Date()

    func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<FridayState, T>, to value: T) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
    
    func recordActivity() {
        lastActivityTime = Date()
    }
}
