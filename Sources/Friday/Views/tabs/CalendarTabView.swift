import SwiftUI

struct CalendarTabView: View {
    @ObservedObject private var state = FridayState.shared
    var namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            // Calendar Stage
            HStack(spacing: 24) {
                // Large Date View
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
                
                // Vertical Events List
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        eventRow(title: "Friday Review", time: "10:00 AM", color: .cyan)
                        eventRow(title: "Design Sync", time: "02:30 PM", color: .purple)
                        eventRow(title: "System Check", time: "05:00 PM", color: .white.opacity(0.15))
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 80)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black, .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
        }
        .frame(height: 140)
        .background(
            Color.white.opacity(0.01)
                .cornerRadius(20)
                .matchedGeometryEffect(id: "cal_bg", in: namespace)
        )
        .padding(.horizontal, 40)
    }

    private func eventRow(title: String, time: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(time)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
}
