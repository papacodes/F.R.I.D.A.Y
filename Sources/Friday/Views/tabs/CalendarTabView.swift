import SwiftUI

struct CalendarTabView: View {
    var body: some View {
        VStack(spacing: 12) {
            // Date header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date(), format: .dateTime.weekday(.wide))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.cyan)
                        .tracking(1)
                    Text(Date(), format: .dateTime.month(.wide).day())
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "calendar")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.15))
            }

            Divider().background(Color.white.opacity(0.08))

            // Placeholder events
            VStack(spacing: 8) {
                calendarRow(time: "—", title: "Ask Friday for your events", color: .white.opacity(0.15))
            }

            Spacer()

            Text("\"Hey Friday, what's on my calendar today?\"")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 4)
    }

    private func calendarRow(time: String, title: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(color)
                .frame(width: 2, height: 28)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                Text(time)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
            Spacer()
        }
    }
}
