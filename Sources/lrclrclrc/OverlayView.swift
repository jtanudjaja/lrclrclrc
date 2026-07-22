import SwiftUI

/// The lyric card.
///
/// Sizing model: **font size** comes only from `appearance.fontScale` (the Text
/// Size knob / Larger-Smaller), independent of the window. The **window size**
/// decides how many lyric lines are shown — a taller card fills with more
/// context lines, fading softly at the top and bottom like a teleprompter.
struct OverlayView: View {
    @ObservedObject var controller: LyricsController
    @ObservedObject var appearance: Appearance
    @State private var hovered = false

    var body: some View {
        GeometryReader { geo in
            let fs = CGFloat(appearance.fontScale)
            let heroSize = 22 * fs
            let lineSize = 15 * fs
            let radius = 18 + 6 * (fs - 1)

            // Three components — header (top), lyrics (middle), footer (status +
            // controls, bottom) — each reacting to window height and text size.
            // Visibility is keyed to window size only (never to hover), so
            // resizing is the only thing that adds/removes a component. The panel
            // enforces a minimum size (OverlayMetrics.minContentSize) so all
            // three normally always fit; these thresholds are the graceful
            // fallback if the window is ever forced smaller than that floor.
            let h = geo.size.height
            let showHeader = OverlayMetrics.headerVisible(height: h, fs: fs)
            let roomForControls = OverlayMetrics.controlsFit(height: h, width: geo.size.width, fs: fs)
            let controlsVisible = (hovered || appearance.alwaysShowControls) && roomForControls

            // Footer control space is *reserved whenever it could appear* — not
            // when it is currently shown — so hovering fades the controls into
            // already-reserved space instead of reflowing the lyric column.
            let controlsH: CGFloat = roomForControls
                ? (controller.isSynced ? OverlayMetrics.controlsSyncedH : OverlayMetrics.controlsPlainH) * fs
                : 0
            let reserve = (OverlayMetrics.vPadding
                + (showHeader ? OverlayMetrics.headerH : 0)) * fs
                + controlsH
            let fitLines = max(1, Int((h - reserve) / (OverlayMetrics.lineUnit * fs)))
            let context = max(0, min(9, (fitLines - 1) / 2))

            VStack(spacing: 5 * fs) {
                if controller.permissionNeeded { permissionButton(fs) }
                if showHeader { header(fs) }

                // The "· LRCLIB" credit is no longer a fixed footer — it's the
                // slot rendered just after the final lyric (see lyricColumn), so
                // it scrolls into view at the end of the song instead of always
                // occupying space.
                lyricColumn(fs: fs, heroSize: heroSize, lineSize: lineSize, context: context)

                if roomForControls {
                    controlsBlock(fs: fs, visible: controlsVisible)
                        .frame(height: controlsH)
                }
            }
            .padding(.horizontal, 24 * fs)
            .padding(.vertical, 14 * fs)
            .frame(width: geo.size.width, height: geo.size.height)
            .shadow(color: .black.opacity(0.7), radius: max(1, fs))
            .shadow(color: .black.opacity(0.4), radius: 5 * fs)
            .background { backgroundLayer(radius: radius) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .bottomTrailing) { grip(fs) }
            .animation(.easeInOut(duration: 0.28), value: hovered)
            .onHover { hovered = $0 }
        }
    }

    // MARK: - Lyric column (fills vertical space)

    private func lyricColumn(fs: CGFloat, heroSize: CGFloat, lineSize: CGFloat, context: Int) -> some View {
        let lines = controller.allLines
        let current = controller.currentLineIndex

        return ZStack {
            if lines.isEmpty {
                // No timed lyrics yet: show whatever line we have plus the status
                // ("looking up lyrics…", "unsynced · LRCLIB", etc.) so the credit
                // and progress are still visible when there's nothing to scroll.
                VStack(spacing: 8 * fs) {
                    Text(nonEmpty(controller.currentLine))
                        .font(.system(size: heroSize, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if !controller.status.isEmpty { creditText(fs, lineSize: lineSize) }
                }
            } else {
                let cur = max(0, current)
                // Always render an equal number of slots above and below the
                // current line. When the song hasn't got that many lines above
                // (or below) yet, the slot is left blank — so the current line
                // stays pinned to the vertical centre instead of drifting up at
                // the start or down at the end. The slot immediately *after* the
                // final lyric holds the "· LRCLIB" credit, so it scrolls in at
                // the end of the song rather than being shown the whole time.
                VStack(spacing: 6 * fs) {
                    ForEach(-context...context, id: \.self) { off in
                        let i = cur + off
                        if i >= 0 && i < lines.count {
                            lineText(i, current: current, heroSize: heroSize, lineSize: lineSize, fs: fs)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Click a timed line to jump playback there —
                                    // same behaviour as the Full Lyrics window.
                                    if let t = controller.allLines[i].time { controller.seek(to: t) }
                                }
                        } else if i == lines.count && !controller.status.isEmpty {
                            creditText(fs, lineSize: lineSize)
                        } else {
                            Color.clear.frame(height: lineSize * 1.2)
                        }
                    }
                }
                .mask(edgeFade(context))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.easeInOut(duration: 0.32), value: current)
    }

    private func lineText(_ i: Int, current: Int, heroSize: CGFloat, lineSize: CGFloat, fs: CGFloat) -> some View {
        let isCurrent = i == current
        let distance = Double(abs(i - max(current, 0)))
        let opacity = isCurrent ? 1.0 : max(0.16, 0.62 - distance * 0.15)
        return Text(nonEmpty(controller.allLines[i].text))
            .font(.system(size: isCurrent ? heroSize : lineSize, weight: isCurrent ? .bold : .regular))
            .foregroundStyle(.white.opacity(opacity))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true) // wrap, never truncate
            .shadow(color: isCurrent ? appearance.accent.color.opacity(0.35) : .clear,
                    radius: isCurrent ? 11 * fs : 0)
            .id(i)
            .transition(.opacity)
            .frame(maxWidth: .infinity)
    }

    /// The source credit / status, rendered as one lyric-sized slot so it sits
    /// naturally below the last line.
    private func creditText(_ fs: CGFloat, lineSize: CGFloat) -> some View {
        Text(controller.status)
            .font(.system(size: 9.5 * fs, weight: .medium))
            .tracking(0.4 * fs)
            .foregroundStyle(.white.opacity(0.4))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: lineSize * 1.2)
    }

    /// Solid (no fade) for a couple of lines; soft top/bottom fade once the
    /// column is tall enough to look like a teleprompter.
    private func edgeFade(_ context: Int) -> LinearGradient {
        if context < 2 {
            return LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(stops: [
            .init(color: .clear, location: 0.0),
            .init(color: .black, location: 0.14),
            .init(color: .black, location: 0.86),
            .init(color: .clear, location: 1.0),
        ], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Chrome

    private func header(_ fs: CGFloat) -> some View {
        // One concatenated line so a long title+artist truncates cleanly at the
        // tail instead of overflowing past the card edge.
        var text = Text(Image(systemName: "music.note"))
            .font(.system(size: 8.5 * fs, weight: .semibold))
            .foregroundColor(.white.opacity(0.45))
        text = text + Text("  \(controller.title)")
            .font(.system(size: 11 * fs, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
        if !controller.artist.isEmpty {
            text = text + Text("   ·   \(controller.artist)")
                .font(.system(size: 11 * fs, weight: .regular))
                .foregroundColor(.white.opacity(0.55))
        }
        return text
            .tracking(0.2 * fs)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
    }

    /// Transport (+ timing when synced) inside a fixed-height slot. Only its
    /// opacity changes on hover — the slot is always reserved, so nothing above
    /// it moves.
    private func controlsBlock(fs: CGFloat, visible: Bool) -> some View {
        VStack(spacing: 4 * fs) {
            transportRow(fs)
            if controller.isSynced { timingRow(fs) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
    }

    private func transportRow(_ fs: CGFloat) -> some View {
        HStack(spacing: 24 * fs) {
            transportButton("backward.fill", fs: fs) { controller.previousTrack() }
            transportButton(controller.isPlaying ? "pause.fill" : "play.fill", fs: fs) { controller.playPause() }
            transportButton("forward.fill", fs: fs) { controller.nextTrack() }
        }
        .padding(.top, 3 * fs)
        .transition(.opacity)
    }

    private func timingRow(_ fs: CGFloat) -> some View {
        HStack(spacing: 12 * fs) {
            transportButton("minus", fs: fs) { controller.nudgeOffset(-0.1) }
            Text(String(format: "%+.1fs", controller.offset))
                .font(.system(size: 11 * fs, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 42 * fs)
            transportButton("plus", fs: fs) { controller.nudgeOffset(0.1) }
        }
        .transition(.opacity)
    }

    private func permissionButton(_ fs: CGFloat) -> some View {
        Button(action: { controller.openAutomationSettings() }) {
            Label("Grant Automation access", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12 * fs, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12 * fs)
                .padding(.vertical, 5 * fs)
                .background(Capsule().fill(.orange.opacity(0.55)))
        }
        .buttonStyle(.plain)
    }

    private func transportButton(_ symbol: String, fs: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14 * fs, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.6), radius: 2)
                .frame(width: 22 * fs, height: 20 * fs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func grip(_ fs: CGFloat) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8.5 * fs, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
            .shadow(color: .black.opacity(0.6), radius: 2)
            .padding(6 * fs)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func backgroundLayer(radius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.black.opacity(hovered ? min(0.5, appearance.backgroundOpacity + 0.22) : appearance.backgroundOpacity))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(hovered ? 0.5 : 0)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.0)],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1
                )
                .opacity(hovered ? 1 : 0)
        }
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(hovered ? 0.35 : 0), radius: 22, y: 9)
    }

    private func nonEmpty(_ s: String) -> String { s.isEmpty ? " " : s }
}
