import Foundation

struct Weather: Codable {
    let latitude: Double
    let longitude: Double
    let generationtime_ms: Double
    let current_weather: CurrentWeather
}

struct CurrentWeather: Codable {
    let temperature: Double
    let windspeed: Double
    let winddirection: Double
    let time: String
}
