import SwiftUI

/// The glass lyric card rendered inside the floating panel.
///
/// Fonts scale with the window size (so resizing grows the lyrics, not just the
/// padding), and the background fades more transparent when the mouse isn't over
/// the card — the "not in focus" state for a panel that never takes key focus.
struct OverlayView: View {
    @ObservedObject var controller: LyricsController
    @State private var hovered = false

    // Design sizes at the default 150pt-tall window; everything scales from here.
    private let baseHeight: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            let scale = max(0.7, min(3.0, geo.size.height / baseHeight))

            VStack(spacing: 4 * scale) {
                HStack(spacing: 8 * scale) {
                    Text(controller.title)
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundColor(.white)
                    Text(controller.artist)
                        .font(.system(size: 11 * scale))
                        .foregroundColor(.white.opacity(0.6))
                }
                .lineLimit(1)

                Text(nonEmpty(controller.prevLine))
                    .font(.system(size: 13 * scale))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)

                Text(nonEmpty(controller.currentLine))
                    .font(.system(size: 19 * scale, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .shadow(color: .blue.opacity(0.25), radius: 8 * scale)

                Text(nonEmpty(controller.nextLine))
                    .font(.system(size: 13 * scale))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)

                Text(controller.status)
                    .font(.system(size: 10 * scale))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 22 * scale)
            .padding(.vertical, 14 * scale)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(
                RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                    .fill(Color.black.opacity(hovered ? 0.6 : 0.26))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
            .animation(.easeInOut(duration: 0.22), value: hovered)
            .onHover { hovered = $0 }
        }
    }

    /// Keep a non-empty string so the row keeps its height when a line is blank.
    private func nonEmpty(_ s: String) -> String { s.isEmpty ? " " : s }
}
