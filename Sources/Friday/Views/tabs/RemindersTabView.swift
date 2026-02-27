import SwiftUI

struct RemindersTabView: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REMINDERS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(1.5)
                    Text("Nothing due")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "bell")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.15))
            }

            Divider().background(Color.white.opacity(0.08))

            VStack(spacing: 8) {
                reminderRow(title: "Ask Friday to add a reminder", done: false)
            }

            Spacer()

            Text("\"Hey Friday, remind me to...\"")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 4)
    }

    private func reminderRow(title: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(done ? Color.cyan : Color.white.opacity(0.2), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.cyan)
                }
            }
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(done ? .white.opacity(0.25) : .white.opacity(0.4))
                .strikethrough(done, color: .white.opacity(0.2))
            Spacer()
        }
    }
}
