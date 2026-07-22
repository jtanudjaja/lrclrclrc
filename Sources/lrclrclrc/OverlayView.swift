import SwiftUI

/// The glass lyric card rendered inside the floating panel.
struct OverlayView: View {
    @ObservedObject var controller: LyricsController

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(controller.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(controller.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            .lineLimit(1)

            Text(nonEmpty(controller.prevLine))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)

            Text(nonEmpty(controller.currentLine))
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .shadow(color: .blue.opacity(0.25), radius: 8)

            Text(nonEmpty(controller.nextLine))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)

            Text(controller.status)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Keep a non-empty string so the row keeps its height when a line is blank.
    private func nonEmpty(_ s: String) -> String { s.isEmpty ? " " : s }
}
