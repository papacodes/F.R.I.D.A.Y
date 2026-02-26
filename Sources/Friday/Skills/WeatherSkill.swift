import Foundation

struct WeatherSkill {
    static func fetchWeather() async -> String {
        // Default to London or similar if location is not available in CLI context
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=51.5074&longitude=-0.1278&current_weather=true"
        guard let url = URL(string: urlString) else { return "Unable to fetch weather." }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = json["current_weather"] as? [String: Any],
               let temp = current["temperature"], let wind = current["windspeed"] {
                return "It is currently \(temp) degrees with a wind speed of \(wind) kilometers per hour."
            }
        } catch {
            return "Weather service is currently unavailable."
        }
        return "Unable to parse weather data."
    }
}
