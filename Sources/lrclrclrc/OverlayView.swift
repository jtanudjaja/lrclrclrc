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

            let showHeader = geo.size.height >= 116
            let showStatus = geo.size.height >= 150
            let roomForControls = geo.size.height >= 104 && geo.size.width >= 240
            let controlsVisible = (hovered || appearance.alwaysShowControls) && roomForControls

            let reserve = 30 * fs
                + (showHeader ? 24 * fs : 0)
                + (showStatus ? 18 * fs : 0)
                + (controlsVisible ? 34 * fs : 0)
            let fitLines = max(1, Int((geo.size.height - reserve) / (lineSize * 1.7)))
            let context = max(0, min(9, (fitLines - 1) / 2))

            VStack(spacing: 5 * fs) {
                if controller.permissionNeeded { permissionButton(fs) }
                if showHeader { header(fs) }

                lyricColumn(fs: fs, heroSize: heroSize, lineSize: lineSize, context: context)

                if showStatus {
                    Text(controller.status)
                        .font(.system(size: 9.5 * fs, weight: .medium))
                        .tracking(0.4 * fs)
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                if controlsVisible { transportRow(fs) }
                if controlsVisible, controller.isSynced { timingRow(fs) }
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
                Text(nonEmpty(controller.currentLine))
                    .font(.system(size: heroSize, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let cur = max(0, current)
                let start = max(0, cur - context)
                let end = min(lines.count - 1, cur + context)
                VStack(spacing: 6 * fs) {
                    ForEach(Array(start...end), id: \.self) { i in
                        lineText(i, current: current, heroSize: heroSize, lineSize: lineSize, fs: fs)
                    }
                }
                .mask(edgeFade(context))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(spacing: 6 * fs) {
            Image(systemName: "music.note")
                .font(.system(size: 8.5 * fs, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(controller.title)
                .font(.system(size: 11 * fs, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            if !controller.artist.isEmpty {
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text(controller.artist)
                    .font(.system(size: 11 * fs, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .tracking(0.2 * fs)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
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
