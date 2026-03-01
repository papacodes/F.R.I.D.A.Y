import Foundation

// MARK: - Client → Server: Setup

struct SetupMessage: Encodable {
    let setup: SetupPayload
}

struct SetupPayload: Encodable {
    let model: String
    let generationConfig: GenerationConfig?
    let systemInstruction: SystemInstruction?
    let tools: [ToolsList]?
}

struct GenerationConfig: Encodable {
    let responseModalities: [String]
    let speechConfig: SpeechConfig?
    let inputAudioTranscription: EmptyConfig?
    let outputAudioTranscription: EmptyConfig?
}

struct SpeechConfig: Encodable {
    let voiceConfig: VoiceConfig
}

struct VoiceConfig: Encodable {
    let prebuiltVoiceConfig: PrebuiltVoiceConfig
}

struct PrebuiltVoiceConfig: Encodable {
    let voiceName: String
}

struct SystemInstruction: Encodable {
    let parts: [TextPart]
}

struct TextPart: Encodable {
    let text: String
}

struct ToolsList: Encodable {
    let functionDeclarations: [FunctionDecl]
}

struct FunctionDecl: Encodable {
    let name: String
    let description: String
    let parameters: FunctionParams
}

struct FunctionParams: Encodable {
    let type: String
    let properties: [String: ParamProperty]
    let required: [String]
}

struct ParamProperty: Encodable {
    let type: String
    let description: String
}

struct EmptyConfig: Encodable {}

// MARK: - Client → Server: Realtime audio

struct RealtimeInputMessage: Encodable {
    let realtimeInput: RealtimeInput
}

struct RealtimeInput: Encodable {
    let mediaChunks: [MediaChunk]
}

struct MediaChunk: Encodable {
    let mimeType: String
    let data: String  // base64-encoded PCM
}

// MARK: - Client → Server: Text turn (used for startup greeting)

struct ClientContentMessage: Encodable {
    let clientContent: ClientContent
}

struct ClientContent: Encodable {
    let turns: [ContentTurn]
    let turnComplete: Bool
}

struct ContentTurn: Encodable {
    let role: String
    let parts: [TextPart]
}

// MARK: - Client → Server: Tool result

struct ToolResponseMessage: Encodable {
    let toolResponse: ToolResponseBody
}

struct ToolResponseBody: Encodable {
    let functionResponses: [FunctionResponseItem]
}

struct FunctionResponseItem: Encodable {
    let id: String
    let name: String
    let response: [String: String]
}

// MARK: - Server → Client

struct ServerMessage: Decodable {
    let setupComplete: SetupComplete?
    let serverContent: ServerContent?
    let toolCall: ToolCallMessage?
    let error: ServerError?
}

struct ServerError: Decodable {
    let code: Int?
    let message: String?
    let status: String?
}

struct SetupComplete: Decodable {}

struct ServerContent: Decodable {
    let modelTurn: ModelTurn?
    let turnComplete: Bool?
    let interrupted: Bool?
    let outputTranscription: AudioTranscription?
    let inputTranscription: AudioTranscription?
}

struct ModelTurn: Decodable {
    let parts: [ServerPart]
}

struct ServerPart: Decodable {
    let inlineData: InlineData?
    let text: String?
}

struct InlineData: Decodable {
    let mimeType: String
    let data: String  // base64-encoded PCM
}

struct AudioTranscription: Decodable {
    let text: String
}

struct ToolCallMessage: Decodable {
    let functionCalls: [FunctionCall]
}

struct FunctionCall: Decodable {
    let id: String
    let name: String
    let args: [String: String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id   = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)

        // Gemini sometimes sends number-typed params (e.g. max_turns: 15) even when the tool
        // declares them as STRING. A plain [String: String] decode throws on the first integer
        // value, which causes the entire message to be silently dropped by the outer catch-all.
        // This custom decoder coerces all arg values to strings to prevent that failure.
        var result: [String: String] = [:]
        if let raw = try? c.nestedContainer(keyedBy: DynamicKey.self, forKey: .args) {
            for key in raw.allKeys {
                if let s = try? raw.decode(String.self, forKey: key) {
                    result[key.stringValue] = s
                } else if let n = try? raw.decode(Double.self, forKey: key) {
                    result[key.stringValue] = n == n.rounded() ? String(Int(n)) : String(n)
                } else if let b = try? raw.decode(Bool.self, forKey: key) {
                    result[key.stringValue] = b ? "true" : "false"
                }
            }
        }
        args = result
    }

    private enum CodingKeys: String, CodingKey { case id, name, args }
    private struct DynamicKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}
