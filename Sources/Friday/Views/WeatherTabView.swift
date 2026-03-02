import SwiftUI

struct WeatherTabView: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        ExpandedPanelView(
            title: "WEATHER",
            trailing: state.currentWeather?.current_weather.time
        ) {
            if let weather = state.currentWeather {
                let w = weather.current_weather

                HStack(alignment: .center, spacing: 0) {
                    // Hero temperature
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(w.temperature))°")
                            .font(.system(size: 54, weight: .thin, design: .rounded))
                            .foregroundColor(.white)
                        Text("CELSIUS")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.2))
                            .tracking(2)
                    }

                    Spacer()

                    Image(systemName: conditionIcon(windspeed: w.windspeed))
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundColor(.cyan.opacity(0.55))

                    Spacer()

                    // Stats column
                    VStack(alignment: .trailing, spacing: 10) {
                        weatherStat(icon: "wind", value: "\(Int(w.windspeed)) km/h", label: "WIND")
                        weatherStat(icon: "safari.fill", value: compassPoint(w.winddirection), label: "DIRECTION")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cloud.moon.fill")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.1))
                    Text("No weather data")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func weatherStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                Text(label)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.2))
                    .tracking(1)
            }
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.2))
                .frame(width: 20)
        }
    }

    private func conditionIcon(windspeed: Double) -> String {
        if windspeed > 40 { return "wind" }
        if windspeed > 20 { return "cloud.fill" }
        return "sun.max.fill"
    }

    private func compassPoint(_ degrees: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return dirs[Int((degrees + 22.5) / 45.0) % 8]
    }
}
