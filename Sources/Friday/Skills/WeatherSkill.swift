import Foundation

struct WeatherSkill {
    static func fetchWeather() async -> String {
        guard let loc = await LocationSkill.fetchLocation() else { 
            return "Unable to determine your location for weather."
        }

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(loc.lat)&longitude=\(loc.lon)&current_weather=true"
        guard let url = URL(string: urlString) else { return "Unable to fetch weather data." }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = json["current_weather"] as? [String: Any],
               let temp = current["temperature"], let wind = current["windspeed"] {
                return "In \(loc.city), it is currently \(temp) degrees with a wind speed of \(wind) kilometers per hour."
            }
        } catch {
            return "Weather service is currently unavailable."
        }
        return "Unable to parse weather for \(loc.city)."
    }
}
