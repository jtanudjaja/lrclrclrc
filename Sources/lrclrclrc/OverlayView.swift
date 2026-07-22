import SwiftUI

/// The lyric card. Design goals: near-invisible when idle, frosted glass on
/// hover; the current line is the luminous hero with dimmed context above and
/// below; lines cross-fade as the song advances. Scales to any size/aspect and
/// keeps white text legible on any wallpaper via a dark contrast halo.
struct OverlayView: View {
    @ObservedObject var controller: LyricsController
    @State private var hovered = false

    private let baseWidth: CGFloat = 620
    private let baseHeight: CGFloat = 150
    private let glow = Color(red: 0.60, green: 0.79, blue: 1.0)

    var body: some View {
        GeometryReader { geo in
            let scale = max(0.5, min(4.0, min(geo.size.width / baseWidth,
                                              geo.size.height / baseHeight)))
            let showContext = geo.size.height >= 118
            let showStatus = geo.size.height >= 138
            let roomForControls = geo.size.height >= 108 && geo.size.width >= 240
            let radius = 20 * scale

            VStack(spacing: 5 * scale) {
                if controller.permissionNeeded {
                    permissionButton(scale: scale)
                }

                if showContext {
                    header(scale: scale)
                    contextLine(controller.prevLine, scale: scale)
                }

                heroLine(scale: scale)

                if showContext {
                    contextLine(controller.nextLine, scale: scale)
                }

                if showStatus {
                    Text(controller.status)
                        .font(.system(size: 9.5 * scale, weight: .medium))
                        .tracking(0.4 * scale)
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }

                if hovered, roomForControls {
                    transportRow(scale: scale)
                        .transition(.opacity)
                }

                if hovered, controller.isSynced, roomForControls {
                    timingRow(scale: scale)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24 * scale)
            .padding(.vertical, 14 * scale)
            .frame(width: geo.size.width, height: geo.size.height)
            // Dark contrast halo so white text reads on any wallpaper.
            .shadow(color: .black.opacity(0.7), radius: max(1, scale))
            .shadow(color: .black.opacity(0.4), radius: 5 * scale)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.black.opacity(hovered ? 0.30 : 0.08))
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(hovered ? 0.55 : 0) // frosted glass on hover
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(hovered ? 0.14 : 0.05), lineWidth: 1)
                }
                .environment(\.colorScheme, .dark)
                .shadow(color: .black.opacity(hovered ? 0.35 : 0), radius: 22 * scale, y: 9 * scale)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8.5 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(6 * scale)
                    .opacity(hovered ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.28), value: hovered)
            .animation(.easeOut(duration: 0.3), value: controller.currentLine)
            .onHover { hovered = $0 }
        }
    }

    // MARK: - Pieces

    private func header(scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: "music.note")
                .font(.system(size: 8.5 * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(controller.title)
                .font(.system(size: 11 * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            if !controller.artist.isEmpty {
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text(controller.artist)
                    .font(.system(size: 11 * scale, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .tracking(0.2 * scale)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func contextLine(_ text: String, scale: CGFloat) -> some View {
        Text(nonEmpty(text))
            .font(.system(size: 13 * scale, weight: .regular))
            .foregroundStyle(.white.opacity(0.32))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.opacity)
    }

    private func heroLine(scale: CGFloat) -> some View {
        Text(nonEmpty(controller.currentLine))
            .font(.system(size: 22 * scale, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.4)
            .multilineTextAlignment(.center)
            .shadow(color: glow.opacity(0.35), radius: 11 * scale)
            .contentTransition(.opacity)
            .padding(.vertical, 1 * scale)
    }

    private func transportRow(scale: CGFloat) -> some View {
        HStack(spacing: 24 * scale) {
            transportButton("backward.fill", scale: scale) { controller.previousTrack() }
            transportButton(controller.isPlaying ? "pause.fill" : "play.fill", scale: scale) { controller.playPause() }
            transportButton("forward.fill", scale: scale) { controller.nextTrack() }
        }
        .padding(.top, 3 * scale)
    }

    private func timingRow(scale: CGFloat) -> some View {
        HStack(spacing: 12 * scale) {
            transportButton("minus", scale: scale) { controller.nudgeOffset(-0.1) }
            Text(String(format: "%+.1fs", controller.offset))
                .font(.system(size: 11 * scale, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 42 * scale)
            transportButton("plus", scale: scale) { controller.nudgeOffset(0.1) }
        }
    }

    private func permissionButton(scale: CGFloat) -> some View {
        Button(action: { controller.openAutomationSettings() }) {
            Label("Grant Automation access", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12 * scale)
                .padding(.vertical, 5 * scale)
                .background(Capsule().fill(.orange.opacity(0.55)))
        }
        .buttonStyle(.plain)
    }

    private func transportButton(_ symbol: String, scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.6), radius: 2)
                .frame(width: 22 * scale, height: 20 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Keep a non-empty string so a row keeps its height when a line is blank.
    private func nonEmpty(_ s: String) -> String { s.isEmpty ? " " : s }
}
