import Foundation
import SwiftUI

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
    
    @Published var showInfoCard = false
    @Published var modelName = "Gemini 2.5 Flash"
    
    // Tracking session greetings
    @Published var hasGreetedThisSession = false

    func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<FridayState, T>, to value: T) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}
