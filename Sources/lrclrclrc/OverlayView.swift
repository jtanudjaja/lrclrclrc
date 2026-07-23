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

    /// The entire palette: the user's colour, and the pole opposite it. Text
    /// and marks take the first, everything they are read *against* — halo
    /// rim, hero bloom, chip backing — takes the second. Nothing on the card
    /// is a third colour, so there is no element that can be legible on one
    /// wallpaper and lost on the next.
    private var textColor: Color { appearance.textColor }
    private var haloColor: Color { appearance.textShadow }

    var body: some View {
        GeometryReader { geo in
            card(size: geo.size)
        }
        // The window is titled (for native resize) with the title bar hidden;
        // NSHostingView still reports that invisible bar as a top safe-area
        // inset, which pushed the whole card down ~28pt inside the window.
        // The card owns the full frame — there is no chrome to avoid.
        .ignoresSafeArea()
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
        .padding(.horizontal, OverlayMetrics.hPadding / 2 * fs)
        .padding(.vertical, OverlayMetrics.vPadding / 2 * fs)
        .frame(width: size.width, height: size.height)
        .background { backgroundLayer(radius: radius) }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .opacity(restingOpacity(clickThrough: clickThrough))
        .animation(.easeInOut(duration: 0.28), value: hovered)
        .animation(.easeInOut(duration: 1.2), value: controller.longIdle)
        .onHover { hovered = $0 }
        // Cursor discipline via SwiftUI's own hover pipeline (the channel
        // that killed the I-beam): plain arrow over the interior, hands OFF
        // near the edges. The window is ordinary and activatable, so the
        // titled frame paints the native resize arrows at and just outside
        // the boundary — setting our own cursor there would only fight it.
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                let band: CGFloat = 8
                let nearEdge = point.x <= band || point.y <= band
                    || point.x >= size.width - band || point.y >= size.height - band
                if !nearEdge { NSCursor.arrow.set() }
            case .ended:
                break // leaving the card — the system owns the cursor
            }
        }
    }

    /// Lyrics stay at full presence while music plays — a whole-card resting
    /// fade muted the product itself (the text), which defeated the point.
    /// The recede-when-ignored behaviour lives in the chrome (hidden idle) and
    /// in the long-stop fade: 25% after ~30s of nothing playing.
    private func restingOpacity(clickThrough: Bool) -> Double {
        if hovered { return 1 }
        if controller.longIdle { return 0.25 }
        return 1
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
        .shadow(color: haloColor.opacity(0.75), radius: 2, y: 1)
        // The whole header row is the card's drag handle — overlaid (not
        // background) so grabbing the title/artist text itself also drags;
        // there's nothing interactive in the header to block.
        .overlay(WindowDragSurface())
    }

    private func headerOneRow(fs: CGFloat) -> some View {
        var text = Text(Image(systemName: "music.note"))
            .font(.system(size: 8.5 * fs, weight: .semibold))
            .foregroundColor(textColor.opacity(0.45))
        text = text + Text("  \(controller.title)")
            .font(.system(size: 11 * fs, weight: .semibold))
            .foregroundColor(textColor.opacity(0.9))
        if !controller.artist.isEmpty {
            text = text + Text("   ·   \(controller.artist)")
                .font(.system(size: 11 * fs, weight: .regular))
                .foregroundColor(textColor.opacity(0.55))
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
                .foregroundColor(textColor.opacity(0.45))
             + Text("  \(controller.title)")
                .font(.system(size: 11 * fs, weight: .semibold))
                .foregroundColor(textColor.opacity(0.9)))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(controller.artist)
                .font(.system(size: 10 * fs))
                .foregroundColor(textColor.opacity(0.55))
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
        // Vertically this is a real containment rule: the stage must not spill
        // into the header or the footer, and the phases that aren't the
        // teleprompter have no edge fade to soften an overrun. Horizontally it
        // was only ever incidental — glyphs stop at their own bounds, so the
        // side edges never cut anything until the hero bloom arrived. They cut
        // it into a straight vertical line, well inside the window, because the
        // stage sits within the card's own padding. So the sides open up by the
        // bloom's reach and the card's rounded clip becomes the horizontal
        // boundary; top and bottom are unchanged.
        .clipShape(SideBleedRect(bleed: OverlayMetrics.heroGlowBleed(fs: fs)))
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
            // Not a separate screen: the countdown lives in the hero slot of
            // the normal teleprompter, with the full lyric context below —
            // scrub or click a line to skip the instrumental.
            teleprompter(fs: fs, stage: stage, softer: false, intro: (countdown, first))
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
                .foregroundStyle(textColor.opacity(0.75))
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
                .foregroundStyle(textColor.opacity(0.4))
            Text(controller.sourceHint)
                .font(.system(size: 10.5 * fs))
                .foregroundStyle(textColor.opacity(0.4))
        }
        .shadow(color: haloColor.opacity(0.7), radius: 2, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func searchingStage(_ fs: CGFloat) -> some View {
        VStack(spacing: 9 * fs) {
            Capsule().fill(textColor.opacity(0.16)).frame(width: 150 * fs, height: 10 * fs)
            Capsule().fill(textColor.opacity(0.11)).frame(width: 104 * fs, height: 8 * fs)
            Text(controller.status)
                .font(.system(size: 9.5 * fs, weight: .medium))
                .tracking(0.4 * fs)
                .foregroundStyle(textColor.opacity(0.4))
                .padding(.top, 4 * fs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func notFoundStage(_ fs: CGFloat) -> some View {
        VStack(spacing: 8 * fs) {
            Text("No lyrics found for this track")
                .font(.system(size: 12 * fs))
                .foregroundStyle(textColor.opacity(0.65))
            Button(action: {
                NotificationCenter.default.post(name: Notification.Name("lrclrclrc.openFindLyrics"), object: nil)
            }) {
                Text("Find lyrics…")
                    .font(.system(size: 10.5 * fs, weight: .semibold))
                    .foregroundStyle(textColor.opacity(0.95))
                    .padding(.horizontal, 11 * fs)
                    .padding(.vertical, 3.5 * fs)
                    .background(chipBacking)
            }
            .buttonStyle(.plain)
        }
        .shadow(color: haloColor.opacity(0.7), radius: 2, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The intro/instrumental indicator as a single hero-slot row: ♪ + fading
    /// dots + countdown. Rendered inside the teleprompter, never as its own
    /// screen — the surrounding lines stay visible and seekable.
    private func introSlot(countdown: Int, first: Bool, fs: CGFloat) -> some View {
        HStack(spacing: 6 * fs) {
            Text("♪")
                .font(.system(size: 19 * fs, weight: .bold))
                .foregroundStyle(textColor)
                .heroGlow(haloColor, fs: fs)
            ForEach([1.0, 0.75, 0.5], id: \.self) { opacity in
                Circle().fill(textColor.opacity(opacity)).frame(width: 5 * fs, height: 5 * fs)
            }
            Text(countdownLabel(countdown, first: first))
                .font(.system(size: 13 * fs, weight: .semibold).monospacedDigit())
                .foregroundStyle(textColor.opacity(0.95))
                .padding(.leading, 3 * fs)
        }
        .shadow(color: haloColor.opacity(0.75), radius: 2, y: 1)
        .frame(maxWidth: .infinity)
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

    private func teleprompter(fs: CGFloat, stage: CGSize, softer: Bool,
                              intro: (countdown: Int, first: Bool)? = nil) -> some View {
        let lines = controller.allLines
        let measureW = min(stage.width, 450 * fs)
        let step = OverlayMetrics.lineUnit * fs * 1.15
        let playingRaw = controller.currentLineIndex
        let playing = max(0, playingRaw)
        // Before the first line the countdown centers as a *virtual* slot
        // (index -1) with the whole song laid out beneath it.
        let baseFocus = (intro != nil && playingRaw < 0) ? -1 : playing

        // Scrub: whole steps move the focus candidate; the remainder slides the
        // column 1:1 under the cursor, with rubber resistance past the ends.
        let rawShift = scrubbing ? Int((scrubTranslation / step).rounded()) : 0
        let unclamped = scrubAnchor - rawShift
        let focus = scrubbing ? min(max(unclamped, 0), max(0, lines.count - 1)) : baseFocus
        var residual: CGFloat = 0
        if scrubbing {
            residual = scrubTranslation - CGFloat(scrubAnchor - focus) * step
            if unclamped != focus { residual *= 0.3 } // rubber-band
        }

        let slots = computeSlots(lines: lines, focus: focus, stage: stage, measureW: measureW, fs: fs)

        return ZStack {
            ForEach(slots) { slot in
                slotView(slot, lines: lines, focus: focus, playing: playing, softer: softer, fs: fs,
                         intro: scrubbing ? nil : intro)
                    .frame(width: measureW)
                    .offset(y: slot.y + residual)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The fade is a *vertical* dissolve, but a mask cuts on all four sides:
        // sized to the band, it also erases everything past the band's left and
        // right edges. Nothing used to be wide enough to notice — glyphs stop at
        // the text's own bounds — but the hero bloom spreads past them, so a
        // full-width focus line got its pool sliced into a straight vertical
        // line. Bleeding the gradient outward leaves the horizontal boundary to
        // the card's rounded clip, which is a real edge, instead of to this
        // invisible rectangle.
        .mask(
            edgeFade(stageHeight: stage.height, fs: fs)
                .padding(.horizontal, -OverlayMetrics.heroGlowBleed(fs: fs))
        )
        .contentShape(Rectangle())
        .gesture(scrubGesture(step: step, lineCount: lines.count))
        .animation(scrubbing ? nil : motion, value: controller.currentLineIndex)
    }

    /// Greedy pixel-budget fill around the pinned hero (spec Part 3, rules 1–2),
    /// rendering one overflow line past each budget for the clipped depth cue
    /// (rule 5), plus the credit slot after the final line.
    private func computeSlots(lines: [LrcLine], focus: Int, stage: CGSize, measureW: CGFloat, fs: CGFloat) -> [Slot] {
        guard !lines.isEmpty else { return [] }
        // focus == -1 is the virtual intro slot: nothing above it (the upward
        // walk starts at -2 and skips), the whole song below it.
        let f = focus < 0 ? -1 : min(focus, lines.count - 1)
        // Spacing loosens slightly as the stage grows (theater feel).
        let gap = (6 + min(2.5, max(0, stage.height / fs - 260) * 0.02)) * fs
        let heroFont = OverlayMetrics.heroFont(fs: fs)
        let lineFont = OverlayMetrics.lineFont(fs: fs)
        let heroSize = 22 * fs
        let lineSize = 15 * fs
        let heroText = f >= 0 ? lines[f].text : "♪"
        let heroH = heights.height(heroText, fontSize: heroSize, width: measureW) {
            OverlayMetrics.textHeight(heroText, font: heroFont, width: measureW)
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
    private func slotView(_ slot: Slot, lines: [LrcLine], focus: Int, playing: Int, softer: Bool, fs: CGFloat,
                          intro: (countdown: Int, first: Bool)?) -> some View {
        if slot.isCredit {
            Text(controller.status)
                .font(.system(size: 9.5 * fs, weight: .medium))
                .tracking(0.4 * fs)
                .foregroundStyle(textColor.opacity(0.4))
        } else if let intro, slot.id == focus {
            // Intro / mid-song instrumental: the countdown occupies the hero
            // slot; the surrounding lines stay visible and seekable.
            introSlot(countdown: intro.countdown, first: intro.first, fs: fs)
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
                .foregroundStyle(textColor.opacity(opacity))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true) // wrap, never truncate
                .shadow(color: haloColor.opacity(0.75), radius: 2, y: 1)
                .heroGlow(haloColor, fs: fs, on: isFocus && !softer)
            if showMarker {
                // A 4pt dot has no interior to carry contrast, so it takes the
                // text's colour *and* the text's rim — without the halo it is
                // the one mark on the card that a matching wallpaper erases.
                Circle()
                    .fill(textColor.opacity(0.9))
                    .frame(width: 4 * fs, height: 4 * fs)
                    .shadow(color: haloColor.opacity(0.75), radius: 2, y: 1)
                Text("playing")
                    .font(.system(size: 7.5 * fs, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.8))
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
            .foregroundStyle(textColor)
            .padding(.horizontal, 7 * fs)
            .padding(.vertical, 2 * fs)
            .background(chipBacking)
    }

    /// Backing for the two small filled chips (Find-lyrics, the scrub time).
    /// Both carry a label at 9–10.5pt, which is below the large-text bar, so
    /// the fill has to be a real surface rather than a tint: the halo's pole
    /// at 0.6 puts the label at ~5.7:1 even when the wallpaper behind it is
    /// the label's own colour. The rim is what the fill cannot do — on the
    /// pole where the fill matches the desktop (a dark chip on a dark
    /// wallpaper) it is the only thing left holding the chip's shape, which
    /// a button needs in order to look like one.
    private var chipBacking: some View {
        Capsule()
            .fill(haloColor.opacity(0.6))
            .overlay(Capsule().strokeBorder(textColor.opacity(0.3), lineWidth: 1))
    }

    /// Top/bottom dissolve for the lyric band. The fade span is line-height-
    /// aware — always ≥ ~1.3 lyric lines — so an overflowing line melts away
    /// gradually instead of ramping out inside a few points and reading as a
    /// hard cutout. The mid-stop eases the ramp (no perceptible edge).
    private func edgeFade(stageHeight: CGFloat, fs: CGFloat) -> LinearGradient {
        let span = min(0.35, (OverlayMetrics.lineUnit * 1.3 * fs) / max(1, stageHeight))
        return LinearGradient(stops: [
            .init(color: .clear, location: 0.0),
            .init(color: .black.opacity(0.4), location: span * 0.55),
            .init(color: .black, location: span),
            .init(color: .black, location: 1.0 - span),
            .init(color: .black.opacity(0.4), location: 1.0 - span * 0.55),
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
                .foregroundStyle(textColor.opacity(0.8))
            transportButton("plus", fs: fs) { controller.nudgeOffset(0.1) }
        }
    }

    private func transportButton(_ symbol: String, fs: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14 * fs, weight: .semibold))
                .foregroundStyle(textColor.opacity(0.92))
                .shadow(color: haloColor.opacity(0.6), radius: 2)
                .frame(width: 22 * fs, height: 20 * fs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chrome

    /// True when the Liquid Glass hover surface is in play (macOS 26 + SDK).
    private var glassActive: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    private func backgroundLayer(radius: CGFloat) -> some View {
        // The Background-opacity knob drives the *idle* face only. Hover uses a
        // fixed designed presence: with Liquid Glass the glass carries it (thin
        // scrim); the legacy material needs more help. The scrim and the
        // material's scheme both take the pole opposite the text, so a dark
        // text colour brings up a light card rather than dark-on-dark.
        let hoverScrim = glassActive ? 0.14 : 0.30
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(appearance.contrast.opacity(hovered ? hoverScrim : appearance.backgroundOpacity))
            hoverSurface(radius: radius)
                .opacity(hovered ? 1 : 0)
        }
        .environment(\.colorScheme, appearance.surfaceScheme)
        // The drop shadow stays black either way — shadows are cast light, not
        // a second surface.
        .shadow(color: .black.opacity(hovered ? 0.35 : 0), radius: 22, y: 9)
    }

    /// The hover face's surface: real Liquid Glass on macOS 26 (its own edge
    /// highlight and refraction — no hand-drawn sheen needed), the classic
    /// thin-material + sheen on 13–15. The idle face stays glass-free either
    /// way: glass has too much presence for the resting state.
    @ViewBuilder
    private func hoverSurface(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if compiler(>=6.2) // Xcode 26 toolchain (macOS 26 SDK)
        if #available(macOS 26.0, *) {
            // The *regular* Liquid Glass variant: its intrinsic frost gives
            // the hover face real substance — the clear variant read too
            // transparent. Regular carries the presence on its own, so the
            // scrim behind it stays thin.
            shape.fill(Color.clear)
                .glassEffect(.regular, in: shape)
        } else {
            legacyHoverSurface(shape)
        }
        #else
        legacyHoverSurface(shape)
        #endif
    }

    private func legacyHoverSurface(_ shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(.ultraThinMaterial).opacity(0.5)
            // The top-edge sheen is a lit edge on a dark card; on a light one
            // the same stroke in the text's pole reads as a fine border.
            shape.strokeBorder(
                LinearGradient(colors: [textColor.opacity(0.12), textColor.opacity(0.0)],
                               startPoint: .top, endPoint: .center),
                lineWidth: 1
            )
        }
    }
}

/// The stage's clip: tight top and bottom, `bleed` points of slack on each
/// side. Exists because `.clipped()` is all-or-nothing and only one of the two
/// axes here is a layout rule.
private struct SideBleedRect: Shape {
    let bleed: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: -bleed, dy: 0))
    }
}

private extension View {
    /// The hero slot's bloom: the same pole as the tight legibility rim, just
    /// wide and soft. Emphasis deepens what the text is read against instead
    /// of laying a colour on top of it — a pale bloom under pale text can only
    /// register on a wallpaper darker than itself, which is exactly the case
    /// where the focus line was already winning. This way the two poles fail
    /// in opposite directions: the bloom pools shadow under light text on a
    /// bright desktop, and lifts dark text on a dim one.
    ///
    /// Deliberately lighter than the rim it extends. The rim has to *define* a
    /// glyph edge, but the bloom only has to weight the slot the eye is already
    /// being pulled to by a 22pt bold line — and a wide shadow at rim strength
    /// stops reading as depth and starts reading as a dark smear behind the
    /// lyrics. Radius comes from `OverlayMetrics` so the blur can't grow into
    /// the card's clip. One tuning point shared by the focus line and the intro
    /// countdown, so retuning one can't strand the other.
    func heroGlow(_ halo: Color, fs: CGFloat, on: Bool = true) -> some View {
        shadow(color: on ? halo.opacity(0.18) : .clear,
               radius: on ? OverlayMetrics.heroGlowRadius(fs: fs) : 0)
    }
}
