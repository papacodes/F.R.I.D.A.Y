import Foundation

enum Phrases {

    static let greetings = [
        "Hey, I'm here. Go ahead.",
        "What's up?",
        "Yeah?",
        "I'm listening.",
        "Ready when you are.",
        "Go ahead, Papa.",
        "Online. What do you need?",
        "Talk to me.",
    ]

    static let thinking = [
        "Give me a sec.",
        "On it.",
        "Let me think about that.",
        "Working on it.",
        "One moment.",
        "Checking on that.",
        "Hmm, let me work through that.",
    ]

    static let errors = [
        "Hmm, I seem to be having a problem. Try again?",
        "Something's not working on my end.",
        "I hit a snag there. Sorry about that.",
        "I'm having trouble with that one. Try me again.",
        "Not sure what happened — want to try that again?",
    ]

    static func randomGreeting() -> String { greetings.randomElement()! }
    static func randomThinking() -> String { thinking.randomElement()! }
    static func randomError() -> String { errors.randomElement()! }
}
