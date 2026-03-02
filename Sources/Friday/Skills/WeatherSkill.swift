import Foundation

struct WeatherSkill {
    static func fetchWeather() async -> Weather? {
        guard let loc = await LocationSkill.fetchLocation() else { 
            return nil
        }

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(loc.lat)&longitude=\(loc.lon)&current_weather=true"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let weather = try decoder.decode(Weather.self, from: data)
            return weather
        } catch {
            print("Error decoding weather data: \(error)")
            return nil
        }
    }
}
