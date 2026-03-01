import Foundation

struct SearchSkill {
    static func searchWeb(_ query: String) async -> String {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Stage 1: DuckDuckGo Instant Answer — encyclopedic facts, Wikipedia abstracts
        if let instant = await instantAnswer(encodedQuery), !instant.isEmpty {
            // Still supplement with news headlines so current context is included
            let news = await newsSearch(encodedQuery)
            if let news {
                return "\(instant)\n\nRecent news: \(news)"
            }
            return instant
        }

        // Stage 2: Google News RSS — current events, breaking news, recent reports
        if let news = await newsSearch(encodedQuery), !news.isEmpty {
            return news
        }

        return "No results found for '\(query)'. The topic may be very localised or the query too specific."
    }

    // MARK: - Stage 1: Instant Answer (facts / Wikipedia)

    private static func instantAnswer(_ encodedQuery: String) async -> String? {
        let urlString = "https://api.duckduckgo.com/?q=\(encodedQuery)&format=json&no_html=1&skip_disambig=1"
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let abstract = json["AbstractText"] as? String, !abstract.isEmpty { return abstract }
        return nil
    }

    // MARK: - Stage 2: Google News RSS (current events)

    private static func newsSearch(_ encodedQuery: String) async -> String? {
        let urlString = "https://news.google.com/rss/search?q=\(encodedQuery)&hl=en-US&gl=US&ceid=US:en"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let xml = String(data: data, encoding: .utf8) else { return nil }

        // Parse first 5 <item> blocks from the RSS feed
        var headlines: [String] = []
        var remaining = xml
        while headlines.count < 5,
              let itemStart = remaining.range(of: "<item>"),
              let itemEnd = remaining.range(of: "</item>") {
            let item = String(remaining[itemStart.upperBound..<itemEnd.lowerBound])
            remaining = String(remaining[itemEnd.upperBound...])

            guard let title = xmlValue(tag: "title", in: item), !title.isEmpty else { continue }
            let source = xmlValue(tag: "source", in: item)
            headlines.append(source.map { "\(title) (\($0))" } ?? title)
        }

        guard !headlines.isEmpty else { return nil }
        return "Recent news on '\(headlines.first.map { _ in "" } ?? "")': " + headlines.joined(separator: "; ")
    }

    // MARK: - Helpers

    private static func xmlValue(tag: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(tag)"),
              let closeAngle = text.range(of: ">", range: open.upperBound..<text.endIndex),
              let closeTag = text.range(of: "</\(tag)>", range: closeAngle.upperBound..<text.endIndex)
        else { return nil }
        let raw = String(text[closeAngle.upperBound..<closeTag.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip CDATA wrapper if present
        if raw.hasPrefix("<![CDATA[") && raw.hasSuffix("]]>") {
            return String(raw.dropFirst(9).dropLast(3))
        }
        return raw.isEmpty ? nil : raw
    }
}
