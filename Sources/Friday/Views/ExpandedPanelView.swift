import SwiftUI

/// Reusable layout shell for all expanded-panel tab content views.
///
/// Provides the standard header row (uppercase title + optional trailing label),
/// correct positioning within the 660×280 expanded panel, and a content slot.
/// Any view using this template must be rendered in NotchExpandedView WITHOUT
/// an external `.padding(.top, 66)` — the template owns that positioning.
///
/// Usage:
///   ExpandedPanelView(title: "WEATHER", trailing: "12:00") {
///       // your content here
///   }
struct ExpandedPanelView<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(2.5)

                Spacer()

                if let trailing {
                    Text(trailing)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.18))
                }
            }
            .padding(.bottom, 14)

            content()
        }
        .padding(.horizontal, 52)
        .padding(.top, 68)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
