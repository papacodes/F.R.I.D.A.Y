import Foundation

struct SearchSkill {
    static func searchWeb(_ query: String) async -> String {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // Using a lightweight search bridge
        let urlString = "https://api.duckduckgo.com/?q=\(encodedQuery)&format=json&no_html=1&skip_disambig=1"
        
        guard let url = URL(string: urlString) else { return "Invalid search query." }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
                    return abstract
                }
                if let related = json["RelatedTopics"] as? [[String: Any]], let first = related.first?["Text"] as? String {
                    return first
                }
            }
        }
        catch {}
        
        return "I searched for \(query) but couldn't find a definitive answer. You might want to try Claude for deeper analysis."
    }
}
