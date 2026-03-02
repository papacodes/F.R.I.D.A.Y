import SwiftUI

/// Shared namespace components for the expanded view's "Stage" layout.

// MARK: - Mini Orb Pill
struct MiniOrbPill: View {
    @ObservedObject private var state = FridayState.shared
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 10) {
            SiriOrbView(
                volume: state.volume,
                isThinking: state.isThinking,
                isError: state.isError,
                isDevTask: state.isDevTaskRunning,
                isConnected: state.isConnected
            )
            .frame(width: 20, height: 20)
            .matchedGeometryEffect(id: "orb_view", in: namespace)
            
            Text("Friday")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .textCase(.uppercase)
                .tracking(0.5)
                .matchedGeometryEffect(id: "orb_text", in: namespace)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
                .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                .matchedGeometryEffect(id: "orb_bg", in: namespace)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                if state.activeTab == .home && state.isFridayDetailOpen {
                    state.activeDetail = .none
                } else {
                    state.activeTab = .home
                }
            }
        }
    }
}

// MARK: - Mini Music Pill
struct MiniMusicPill: View {
    @ObservedObject private var state = FridayState.shared
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 10) {
            AlbumArtThumbnail(size: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .matchedGeometryEffect(id: "music_art", in: namespace)
            
            Text(state.nowPlayingTitle.isEmpty ? "MUSIC" : state.nowPlayingTitle)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .textCase(.uppercase)
                .lineLimit(1)
                .tracking(0.5)
                .matchedGeometryEffect(id: "music_info", in: namespace)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
                .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                .matchedGeometryEffect(id: "music_bg", in: namespace)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                state.activeTab = .music
            }
        }
    }
}

// MARK: - Mini Calendar Pill
struct MiniCalendarPill: View {
    @ObservedObject private var state = FridayState.shared
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 10) {
            Text(Date(), format: .dateTime.weekday(.abbreviated).day())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .textCase(.uppercase)
                .tracking(0.5)
                .matchedGeometryEffect(id: "cal_info", in: namespace)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
                .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                .matchedGeometryEffect(id: "cal_bg", in: namespace)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                state.activeTab = .calendar
            }
        }
    }
}
