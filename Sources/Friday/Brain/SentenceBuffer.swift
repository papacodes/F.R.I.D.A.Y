import Foundation

actor SentenceBuffer {
    private var buffer: String = ""
    private let onSentence: @Sendable (String) -> Void
    
    init(onSentence: @escaping @Sendable (String) -> Void) {
        self.onSentence = onSentence
    }
    
    func append(_ chunk: String) {
        buffer += chunk
        
        // Look for sentence terminators
        let terminators: CharacterSet = [".", "!", "?"]
        
        // Find the last terminator index
        if let lastIndex = buffer.lastIndex(where: { char in
            char.unicodeScalars.allSatisfy { terminators.contains($0) }
        }) {
            let sentenceEndIndex = buffer.index(after: lastIndex)
            let sentence = String(buffer[..<sentenceEndIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !sentence.isEmpty {
                onSentence(sentence)
                buffer = String(buffer[sentenceEndIndex...])
            }
        }
    }
    
    func flush() {
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            onSentence(remaining)
        }
        buffer = ""
    }
}
