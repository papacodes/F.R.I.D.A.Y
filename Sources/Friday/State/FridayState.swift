import Foundation

@MainActor
final class FridayState: ObservableObject {
    static let shared = FridayState()
    private init() {}

    @Published var isListening = false
    @Published var isThinking = false
    @Published var isSpeaking = false
    @Published var isError = false
    @Published var transcript = ""

    func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<FridayState, T>, to value: T) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}
