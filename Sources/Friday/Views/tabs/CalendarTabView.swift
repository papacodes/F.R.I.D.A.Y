import SwiftUI

struct CalendarTabView: View {
    var namespace: Namespace.ID

    @State private var events: [CalendarEventItem] = []
    @State private var isLoading = true

    var body: some View {
        HStack(spacing: 24) {
            // Large date badge
            VStack(alignment: .leading, spacing: 0) {
                Text(Date(), format: .dateTime.weekday(.wide))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.cyan)
                    .textCase(.uppercase)

                Text(Date(), format: .dateTime.day())
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, -6)
            }
            .frame(width: 100, alignment: .leading)
            .matchedGeometryEffect(id: "cal_info", in: namespace)

            // Events list
            Group {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if events.isEmpty {
                    Text("No events today")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.25))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(events) { event in
                                eventRow(event)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black, .black, .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
            .frame(height: 80)
        }
        .frame(height: 140)
        .background(
            Color.white.opacity(0.01)
                .cornerRadius(20)
                .matchedGeometryEffect(id: "cal_bg", in: namespace)
        )
        .padding(.horizontal, 40)
        .task {
            events = await CalendarSkill.todayEvents()
            isLoading = false
        }
    }

    private func eventRow(_ event: CalendarEventItem) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(event.calendarColor)
                .frame(width: 4, height: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
}
