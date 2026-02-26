import Foundation

enum WhisperBridge {

    static func transcribe(_ wavData: Data) async throws -> String {
        let boundary = "FridayBoundary\(Int.random(in: 100_000...999_999))"

        var req = URLRequest(url: URL(string: "http://127.0.0.1:2022/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("whisper-1\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        append("\r\n--\(boundary)--\r\n")

        req.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: req)
        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WhisperResponse: Decodable { let text: String }
