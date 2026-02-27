import SwiftUI

struct NotesTabView: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOTES")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(1.5)
                    Text("Your notes")
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "note.text")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.15))
            }

            Divider().background(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 8) {
                noteRow(title: "Ask Friday to read or write notes")
            }

            Spacer()

            Text("\"Hey Friday, add a note...\"")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 4)
    }

    private func noteRow(title: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.12))
                .frame(width: 2, height: 28)

            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(2)
            Spacer()
        }
    }
}
