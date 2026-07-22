import SwiftUI

/// The glass lyric card rendered inside the floating panel.
///
/// Responsive to arbitrary sizes and aspect ratios:
///   • content scales to fit *both* axes (not just height), so wide-short and
///     tall-narrow windows both stay proportional;
///   • `minimumScaleFactor` lets long lines shrink instead of truncating;
///   • secondary rows (title/artist, prev/next, status) drop out when the
///     window is short, so the current lyric always fits.
///
/// The background is nearly transparent when idle and firmer on hover; a dark
/// contrast halo on the text keeps the white glyphs legible on any wallpaper
/// even when the background is barely there.
struct OverlayView: View {
    @ObservedObject var controller: LyricsController
    @State private var hovered = false

    // Reference dimensions the design is tuned at; scale is derived from these.
    private let baseWidth: CGFloat = 620
    private let baseHeight: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            let scale = max(0.5, min(4.0, min(geo.size.width / baseWidth,
                                              geo.size.height / baseHeight)))
            let showContext = geo.size.height >= 118   // prev/next + meta
            let showStatus = geo.size.height >= 138

            VStack(spacing: 4 * scale) {
                if showContext {
                    HStack(spacing: 8 * scale) {
                        Text(controller.title)
                            .font(.system(size: 12 * scale, weight: .semibold))
                        Text(controller.artist)
                            .font(.system(size: 11 * scale))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                    Text(nonEmpty(controller.prevLine))
                        .font(.system(size: 13 * scale))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Text(nonEmpty(controller.currentLine))
                    .font(.system(size: 19 * scale, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)

                if showContext {
                    Text(nonEmpty(controller.nextLine))
                        .font(.system(size: 13 * scale))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                if showStatus {
                    Text(controller.status)
                        .font(.system(size: 10 * scale))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20 * scale)
            .padding(.vertical, 12 * scale)
            .frame(width: geo.size.width, height: geo.size.height)
            // Contrast halo: a tight + soft dark shadow so white text reads on
            // any background, especially while the card is near-transparent.
            .shadow(color: .black.opacity(0.75), radius: max(1, scale))
            .shadow(color: .black.opacity(0.45), radius: 4 * scale)
            .background(
                RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                    .fill(Color.black.opacity(hovered ? 0.5 : 0.12))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
            .animation(.easeInOut(duration: 0.22), value: hovered)
            .onHover { hovered = $0 }
        }
    }

    /// Keep a non-empty string so the row keeps its height when a line is blank.
    private func nonEmpty(_ s: String) -> String { s.isEmpty ? " " : s }
}
