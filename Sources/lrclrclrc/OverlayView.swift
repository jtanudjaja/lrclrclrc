import SwiftUI
import AppKit

/// Memoizes wrapped text heights. The stage re-lays-out on every render, and a
/// scrub re-renders per mouse move (60–120Hz) — measuring ~a dozen lines with
/// NSAttributedString each frame would burn CPU. Keyed by text+font+width;
/// cleared wholesale if it ever grows past a few tracks' worth.
private final class TextHeightCache {
    private var store: [String: CGFloat] = [:]

    func height(_ text: String, fontSize: CGFloat, width: CGFloat,
                compute: () -> CGFloat) -> CGFloat {
        let key = "\(fontSize)|\(Int(width))|\(text)"
        if let cached = store[key] { return cached }
        if store.count > 800 { store.removeAll() }
        let value = compute()
        store[key] = value
        return value
    }
}

/// The lyric card, per the layout spec:
///
/// Three zones — header (measured, never truncated), stage (flexible), footer
/// (constant one-row, reserved) — around a pixel-budget teleprompter that pins
/// the current line to the stage's exact center. Every text height is measured
/// with the real font at the real width; overflow renders clipped behind the
/// edge fade and can never push the chrome. Idle is the design (near-invisible
/// scrim, self-shadowed text); hover only changes opacity. Lines can be clicked
/// or vertically scrubbed to seek.
struct OverlayView: View {
    @ObservedObject var controller: LyricsController
    @ObservedObject var appearance: Appearance

    @State private var hovered = false
    // Scrub gesture state (spec Part 7).
    @State private var scrubbing = false
    @State private var scrubTranslation: CGFloat = 0
    @State private var scrubAnchor = 0
    @State private var heights = TextHeightCache()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)
    }

    var body: some View {
        GeometryReader { geo in
            card(size: geo.size)
        }
    }

    // MARK: - Card frame (the three zones)

    private func card(size: CGSize) -> some View {
        let fs = CGFloat(appearance.fontScale)
        let clickThrough = appearance.clickThroughActive
        let radius = 18 + 6 * (fs - 1)
        let showHeader = OverlayMetrics.headerVisible(height: size.height, fs: fs)
        let footerOn = !clickThrough && OverlayMetrics.controlsFit(height: size.height, width: size.width, fs: fs)
        // Idle is lyrics-only: header and controls fade in together on hover
        // (or stay on with Always Show Controls). Space stays reserved — the
        // switch is pure opacity, and the invisible header still drags.
        let chromeVisible = hovered || appearance.alwaysShowControls
        let controlsVisible = footerOn && chromeVisible

        return VStack(spacing: 5 * fs) {
            if showHeader {
                headerView(fs: fs, cardWidth: size.width)
                    .opacity(chromeVisible ? 1 : 0)
            }

            stageArea(fs: fs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if footerOn {
                footerRow(fs: fs, cardWidth: size.width, visible: controlsVisible)
                    .frame(height: OverlayMetrics.footerH * fs)
            }
        }
        .padding(.horizontal, 24 * fs)
        .padding(.vertical, 14 * fs)
        .frame(width: size.width, height: size.height)
        .background { backgroundLayer(radius: radius) }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .opacity(restingOpacity(clickThrough: clickThrough))
        .animation(.easeInOut(duration: 0.28), value: hovered)
        .animation(.easeInOut(duration: 1.2), value: controller.longIdle)
        .onHover { hovered = $0 }
        // Cursor authority for the whole card, run inside SwiftUI's own hover
        // pipeline so it beats the hosting view's built-in cursor handling:
        // resize arrows in the 8pt edge band, plain arrow everywhere else
        // (which also kills the I-beam SwiftUI shows over text).
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                (EdgeResizeView.resizeCursor(at: point, in: size) ?? .arrow).set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }

    /// FaceTime-style resting translucency: the whole card sits at a quiet 60%
    /// until hovered, and 25% after a long stop. Click-through is exempt —
    /// hover can't happen there, and readable lyrics are the point.
    private func restingOpacity(clickThrough: Bool) -> Double {
        if hovered { return 1 }
        if controller.longIdle { return 0.25 }
        if clickThrough { return 1 }
        return 0.6
    }

    // MARK: - Header (measured, never truncated, never resizes the window)

    @ViewBuilder
    private func headerView(fs: CGFloat, cardWidth: CGFloat) -> some View {
        let oneRow = controller.artist.isEmpty || OverlayMetrics.headerFitsOneRow(
            title: controller.title, artist: controller.artist, fs: fs, cardWidth: cardWidth
        )
        // Empty states dim the header — the stage carries the message.
        let dimmed = controller.stagePhase == .idle || controller.stagePhase == .permission
        Group {
            if oneRow {
                headerOneRow(fs: fs)
            } else {
                headerSplit(fs: fs)
            }
        }
        .opacity(dimmed ? 0.55 : 1)
        .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
        // The whole header row is the card's drag handle — overlaid (not
        // background) so grabbing the title/artist text itself also drags;
        // there's nothing interactive in the header to block.
        .overlay(WindowDragSurface())
    }

    private func headerOneRow(fs: CGFloat) -> some View {
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
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private func headerSplit(fs: CGFloat) -> some View {
        VStack(spacing: 1 * fs) {
            (Text(Image(systemName: "music.note"))
                .font(.system(size: 8.5 * fs, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
             + Text("  \(controller.title)")
                .font(.system(size: 11 * fs, weight: .semibold))
                .foregroundColor(.white.opacity(0.9)))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(controller.artist)
                .font(.system(size: 10 * fs))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stage (one designed home per state)

    private func stageArea(fs: CGFloat) -> some View {
        GeometryReader { g in
            stageContent(fs: fs, stage: g.size)
                .frame(width: g.size.width, height: g.size.height)
        }
        .clipped()
    }

    @ViewBuilder
    private func stageContent(fs: CGFloat, stage: CGSize) -> some View {
        switch controller.stagePhase {
        case .permission:
            permissionStage(fs)
        case .idle:
            idleStage(fs)
        case .searching:
            searchingStage(fs)
        case .notFound:
            notFoundStage(fs)
        case .intro(let countdown, let first):
            introStage(fs, countdown: countdown, first: first)
        case .synced:
            teleprompter(fs: fs, stage: stage, softer: false)
        case .unsynced:
            teleprompter(fs: fs, stage: stage, softer: true)
        }
    }

    private func permissionStage(_ fs: CGFloat) -> some View {
        VStack(spacing: 8 * fs) {
            Text("lrclrclrc needs permission to read the current track")
                .font(.system(size: 12 * fs))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { controller.openAutomationSettings() }) {
                Text("Grant Automation Access")
                    .font(.system(size: 11 * fs, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12 * fs)
                    .padding(.vertical, 4 * fs)
                    .background(Capsule().fill(.orange.opacity(0.55)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func idleStage(_ fs: CGFloat) -> some View {
        VStack(spacing: 6 * fs) {
            Text("♪")
                .font(.system(size: 20 * fs, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
            Text("Play something in Music or Spotify")
                .font(.system(size: 10.5 * fs))
                .foregroundStyle(.white.opacity(0.4))
        }
        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func searchingStage(_ fs: CGFloat) -> some View {
        VStack(spacing: 9 * fs) {
            Capsule().fill(.white.opacity(0.16)).frame(width: 150 * fs, height: 10 * fs)
            Capsule().fill(.white.opacity(0.11)).frame(width: 104 * fs, height: 8 * fs)
            Text(controller.status)
                .font(.system(size: 9.5 * fs, weight: .medium))
                .tracking(0.4 * fs)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 4 * fs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notFoundStage(_ fs: CGFloat) -> some View {
        VStack(spacing: 8 * fs) {
            Text("No lyrics found for this track")
                .font(.system(size: 12 * fs))
                .foregroundStyle(.white.opacity(0.65))
            Button(action: {
                NotificationCenter.default.post(name: Notification.Name("lrclrclrc.openFindLyrics"), object: nil)
            }) {
                Text("Find lyrics…")
                    .font(.system(size: 10.5 * fs, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 11 * fs)
                    .padding(.vertical, 3.5 * fs)
                    .background(Capsule().fill(appearance.accent.color.opacity(0.3)))
            }
            .buttonStyle(.plain)
        }
        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func introStage(_ fs: CGFloat, countdown: Int, first: Bool) -> some View {
        VStack(spacing: 6 * fs) {
            HStack(spacing: 5 * fs) {
                Text("♪")
                    .font(.system(size: 15 * fs, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: appearance.accent.color.opacity(0.3), radius: 8 * fs)
                Circle().fill(.white.opacity(0.95)).frame(width: 4 * fs, height: 4 * fs)
                Circle().fill(.white.opacity(0.65)).frame(width: 4 * fs, height: 4 * fs)
                Circle().fill(.white.opacity(0.35)).frame(width: 4 * fs, height: 4 * fs)
            }
            Text(countdownLabel(countdown, first: first))
                .font(.system(size: 10 * fs, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
            if !controller.nextLine.isEmpty {
                Text(controller.nextLine)
                    .font(.system(size: 15 * fs))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4 * fs)
            }
        }
        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func countdownLabel(_ seconds: Int, first: Bool) -> String {
        let s = max(0, seconds)
        return String(format: "%@ line in %d:%02d", first ? "first" : "next", s / 60, s % 60)
    }

    // MARK: - Teleprompter (pixel budget around a pinned center)

    private struct Slot: Identifiable {
        let id: Int          // line index; lines.count == the credit slot
        let y: CGFloat       // offset of the slot's center from stage center
        let isCredit: Bool
    }

    private func teleprompter(fs: CGFloat, stage: CGSize, softer: Bool) -> some View {
        let lines = controller.allLines
        let measureW = min(stage.width, 450 * fs)
        let step = OverlayMetrics.lineUnit * fs * 1.15
        let playing = max(0, controller.currentLineIndex)

        // Scrub: whole steps move the focus candidate; the remainder slides the
        // column 1:1 under the cursor, with rubber resistance past the ends.
        let rawShift = scrubbing ? Int((scrubTranslation / step).rounded()) : 0
        let unclamped = scrubAnchor - rawShift
        let focus = scrubbing ? min(max(unclamped, 0), max(0, lines.count - 1)) : playing
        var residual: CGFloat = 0
        if scrubbing {
            residual = scrubTranslation - CGFloat(scrubAnchor - focus) * step
            if unclamped != focus { residual *= 0.3 } // rubber-band
        }

        let slots = computeSlots(lines: lines, focus: focus, stage: stage, measureW: measureW, fs: fs)

        return ZStack {
            ForEach(slots) { slot in
                slotView(slot, lines: lines, focus: focus, playing: playing, softer: softer, fs: fs)
                    .frame(width: measureW)
                    .offset(y: slot.y + residual)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask(edgeFade)
        .contentShape(Rectangle())
        .gesture(scrubGesture(step: step, lineCount: lines.count))
        .animation(scrubbing ? nil : motion, value: controller.currentLineIndex)
    }

    /// Greedy pixel-budget fill around the pinned hero (spec Part 3, rules 1–2),
    /// rendering one overflow line past each budget for the clipped depth cue
    /// (rule 5), plus the credit slot after the final line.
    private func computeSlots(lines: [LrcLine], focus: Int, stage: CGSize, measureW: CGFloat, fs: CGFloat) -> [Slot] {
        guard !lines.isEmpty else { return [] }
        let f = min(max(focus, 0), lines.count - 1)
        // Spacing loosens slightly as the stage grows (theater feel).
        let gap = (6 + min(2.5, max(0, stage.height / fs - 260) * 0.02)) * fs
        let heroFont = OverlayMetrics.heroFont(fs: fs)
        let lineFont = OverlayMetrics.lineFont(fs: fs)
        let heroSize = 22 * fs
        let lineSize = 15 * fs
        let heroH = heights.height(lines[f].text, fontSize: heroSize, width: measureW) {
            OverlayMetrics.textHeight(lines[f].text, font: heroFont, width: measureW)
        }
        let budget = max(0, (stage.height - heroH) / 2)

        var slots = [Slot(id: f, y: 0, isCredit: false)]

        // Upward.
        var edge = -heroH / 2
        var used: CGFloat = 0
        var i = f - 1
        while i >= 0 {
            let text = lines[i].text
            let h = heights.height(text, fontSize: lineSize, width: measureW) {
                OverlayMetrics.textHeight(text, font: lineFont, width: measureW)
            }
            slots.append(Slot(id: i, y: edge - gap - h / 2, isCredit: false))
            edge -= gap + h
            used += gap + h
            i -= 1
            if used > budget { break } // that one was the clipped overflow line
        }

        // Downward (the slot after the last line carries the credit).
        edge = heroH / 2
        used = 0
        i = f + 1
        while i <= lines.count {
            let isCredit = i == lines.count
            if isCredit && controller.status.isEmpty { break }
            let h: CGFloat
            if isCredit {
                h = 14 * fs
            } else {
                let text = lines[i].text
                h = heights.height(text, fontSize: lineSize, width: measureW) {
                    OverlayMetrics.textHeight(text, font: lineFont, width: measureW)
                }
            }
            slots.append(Slot(id: i, y: edge + gap + h / 2, isCredit: isCredit))
            edge += gap + h
            used += gap + h
            i += 1
            if used > budget { break }
        }
        return slots
    }

    @ViewBuilder
    private func slotView(_ slot: Slot, lines: [LrcLine], focus: Int, playing: Int, softer: Bool, fs: CGFloat) -> some View {
        if slot.isCredit {
            Text(controller.status)
                .font(.system(size: 9.5 * fs, weight: .medium))
                .tracking(0.4 * fs)
                .foregroundStyle(.white.opacity(0.4))
        } else {
            lyricLine(slot.id, lines: lines, focus: focus, playing: playing, softer: softer, fs: fs)
        }
    }

    private func lyricLine(_ index: Int, lines: [LrcLine], focus: Int, playing: Int, softer: Bool, fs: CGFloat) -> some View {
        let isFocus = index == focus
        let distance = Double(abs(index - focus))
        // Unsynced ("softer"): the estimated line keeps the same size as its
        // neighbours — just brighter and semibold, no glow — honest about the
        // position being approximate.
        let opacity = isFocus ? (softer ? 0.95 : 1.0) : max(0.16, 0.62 - distance * 0.15)
        let size: CGFloat = (isFocus && !softer) ? 22 * fs : 15 * fs
        let weight: Font.Weight = isFocus ? (softer ? .semibold : .bold) : .regular
        let raw = lines[index].text
        let showMarker = scrubbing && index == playing && !isFocus

        return HStack(spacing: 6 * fs) {
            Text(raw.isEmpty ? "♪" : raw)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(.white.opacity(opacity))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true) // wrap, never truncate
                .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
                .shadow(color: (isFocus && !softer) ? appearance.accent.color.opacity(0.35) : .clear,
                        radius: (isFocus && !softer) ? 11 * fs : 0)
            if showMarker {
                Circle()
                    .fill(appearance.accent.color.opacity(0.9))
                    .frame(width: 4 * fs, height: 4 * fs)
                Text("playing")
                    .font(.system(size: 7.5 * fs, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            if scrubbing, isFocus, let target = controller.seekTarget(forLine: index) {
                timeChip(target, fs: fs)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { controller.seek(toLine: index) }
    }

    private func timeChip(_ seconds: Double, fs: CGFloat) -> some View {
        let s = max(0, Int(seconds))
        return Text(String(format: "%d:%02d", s / 60, s % 60))
            .font(.system(size: 9 * fs, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7 * fs)
            .padding(.vertical, 2 * fs)
            .background(Capsule().fill(appearance.accent.color.opacity(0.32)))
    }

    private var edgeFade: LinearGradient {
        LinearGradient(stops: [
            .init(color: .clear, location: 0.0),
            .init(color: .black, location: 0.12),
            .init(color: .black, location: 0.88),
            .init(color: .clear, location: 1.0),
        ], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Scrub gesture (spec Part 7)

    private func scrubGesture(step: CGFloat, lineCount: Int) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if !scrubbing {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    // Predominantly horizontal on the stage: hand the drag to
                    // the window so the card moves, same as dragging anywhere
                    // else. (Once handed off, this gesture stream goes quiet.)
                    guard dy > dx else {
                        if dx + dy < 24, let event = NSApp.currentEvent,
                           let window = NSApp.windows.first(where: { $0 is OverlayPanel }) {
                            window.performDrag(with: event)
                        }
                        return
                    }
                    guard lineCount > 0 else { return }
                    scrubbing = true
                    scrubAnchor = max(0, controller.currentLineIndex)
                }
                scrubTranslation = value.translation.height
            }
            .onEnded { value in
                guard scrubbing else { return }
                let shift = Int((value.translation.height / step).rounded())
                scrubbing = false
                scrubTranslation = 0
                guard shift != 0, lineCount > 0 else { return } // no move → cancel
                let target = min(max(scrubAnchor - shift, 0), lineCount - 1)
                controller.seek(toLine: target)
            }
    }

    // MARK: - Footer (one constant row: transport + timing as one centered group)

    private func footerRow(fs: CGFloat, cardWidth: CGFloat, visible: Bool) -> some View {
        // One centered cluster — transport beside timing — so the two can never
        // collide (~250pt×fs total, guaranteed by the floor width). The timing
        // slot is always reserved (opacity only), so sync state shifts nothing.
        HStack(spacing: 26 * fs) {
            HStack(spacing: 24 * fs) {
                transportButton("backward.fill", fs: fs) { controller.previousTrack() }
                transportButton(controller.isPlaying ? "pause.fill" : "play.fill", fs: fs) { controller.playPause() }
                transportButton("forward.fill", fs: fs) { controller.nextTrack() }
            }
            timingCluster(fs)
                .opacity(controller.isSynced ? 1 : 0)
                .allowsHitTesting(controller.isSynced && visible)
        }
        .frame(maxWidth: .infinity)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        // The footer's non-interactive background also drags the window.
        .background(WindowDragSurface())
    }

    private func timingCluster(_ fs: CGFloat) -> some View {
        HStack(spacing: 8 * fs) {
            transportButton("minus", fs: fs) { controller.nudgeOffset(-0.1) }
            Text(String(format: "%+.1fs", controller.offset))
                .font(.system(size: 10.5 * fs, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
            transportButton("plus", fs: fs) { controller.nudgeOffset(0.1) }
        }
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

    // MARK: - Chrome

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
}
