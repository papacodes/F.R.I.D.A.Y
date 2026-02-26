import Foundation

struct LocationSkill {
    struct LocationData: Decodable {
        let city: String
        let regionName: String
        let lat: Double
        let lon: Double
    }

    static func fetchLocation() async -> LocationData? {
        guard let url = URL(string: "http://ip-api.com/json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(LocationData.self, from: data)
        } catch {
            return nil
        }
    }
}
