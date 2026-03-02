import SwiftUI

struct WeatherTabView: View {
    @EnvironmentObject var state: FridayState

    var body: some View {
        Group {
            if let weather = state.currentWeather {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Current Weather")
                        .font(.title2)
                        .foregroundColor(.white)

                    HStack {
                        Image(systemName: "cloud.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.cyan)

                        VStack(alignment: .leading) {
                            Text("\(Int(weather.current_weather.temperature))°C")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                            Text("Time: \(weather.current_weather.time)")
                                .font(.footnote)
                                .foregroundColor(.gray)
                        }
                    }

                    HStack {
                        Image(systemName: "wind")
                        Text("Wind: \(Int(weather.current_weather.windspeed)) km/h")
                    }
                    .foregroundColor(.white)
                }
                .padding()
            } else {
                Text("Fetching weather...")
                    .foregroundColor(.gray)
                    .onAppear {
                        // Trigger fetch logic here (to be implemented in state manager)
                    }
            }
        }
    }
}
