import SwiftUI

struct MiniWeatherPill: View {
    @ObservedObject private var state = FridayState.shared

    var body: some View {
        Group {
            if let weather = state.currentWeather {
                HStack(spacing: 4) {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(.cyan)
                    Text("\(Int(weather.current_weather.temperature))°C")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(10)
            }
        }
    }
}
