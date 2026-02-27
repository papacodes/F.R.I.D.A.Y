import SwiftUI

/// Three-column home: Music | Friday Orb | Info
struct NotchHomeView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            MusicPanelView()
                .frame(maxWidth: .infinity)

            // Vertical dividers
            divider
            FridayStatusPanelView()
                .frame(width: 160)
            divider

            InfoPanelView()
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
    }
}
