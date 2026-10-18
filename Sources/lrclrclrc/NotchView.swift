import SwiftUI

/// The lyric slab: the notch, grown a chin.
///
/// One opaque black shape, flush with the top of the screen and square where
/// it meets it, so it reads as the housing itself getting deeper rather than
/// as a window parked underneath. Only the part below the housing can be seen
/// at all, so that's the only part that carries text.
///
/// Three states, one shape:
///
/// *Collapsed* is the design, not a fallback — the slab is exactly the
/// housing's size and vanishes into it. Nothing playing means nothing on
/// screen; the notch is just a notch again.
///
/// *Chin* is one line of lyric, the slab as wide as the words need. A line
/// too long for the wings scrolls rather than shrinking (`SlabLine`).
///
/// *Stage* is what hover opens: the line playing with the line before and
/// after it. Hover arrives from `NotchHoverMonitor`, because this window never
/// takes a mouse event.
struct NotchView: View {
    @ObservedObject var dock: NotchDock
    @ObservedObject var hover: NotchHoverMonitor
    @ObservedObject var controller: LyricsController
    @ObservedObject var appearance: Appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let geometry = dock.geometry {
                slab(geometry)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The window deliberately overlaps the notch, which is the one safe
        // area macOS inserts for: without this the whole slab would be pushed
        // down below the housing it's supposed to grow out of.
        .ignoresSafeArea()
    }

    // MARK: - The slab

    private func slab(_ geometry: NotchGeometry) -> some View {
        let scale = NotchMetrics.scale(appearance.fontScale)
        let chin = self.chin
        // The stage is a lyric's own context, so only a lyric has one: an
        // aside (a lookup in flight, a countdown) has nothing to expand into.
        let open = hover.isInside && chin.isLyric

        let chinWidth = chin.text.map { NotchMetrics.slabWidth(for: $0, scale: scale, in: geometry) }
            ?? geometry.collapsedWidth
        let width = open
            ? NotchMetrics.stageWidth(focus: controller.currentLine,
                                      context: [controller.prevLine, controller.nextLine],
                                      chinWidth: chinWidth, scale: scale, in: geometry)
            : chinWidth
        let depth = chin.isCollapsed ? 0
            : open ? NotchMetrics.stageHeight(scale: scale)
            : NotchMetrics.chinHeight(scale: scale)
        // Screen coordinates, housing included: hovering the notch itself is
        // the gesture that opens the stage.
        let zone: CGRect = chin.isCollapsed ? .zero : CGRect(
            x: geometry.housingCenterX - width / 2,
            y: geometry.screen.frame.maxY - (geometry.housingHeight + depth),
            width: width,
            height: geometry.housingHeight + depth
        )

        return UnevenRoundedRectangle(
            bottomLeadingRadius: NotchMetrics.cornerRadius,
            bottomTrailingRadius: NotchMetrics.cornerRadius,
            style: .continuous
        )
        // Opaque black, and not the card's background-opacity knob: the slab's
        // whole job is to pass for the bezel, and a translucent one stops
        // being the notch and starts being a window near it.
        .fill(.black)
        .frame(width: width, height: geometry.housingHeight + depth)
        .overlay(alignment: .bottom) {
            Group {
                if open {
                    stage(width: width, scale: scale)
                } else if let text = chin.text {
                    chinRow(text, aside: chin.isAside, width: width, scale: scale)
                }
            }
            .frame(width: width, height: depth)
            // Text rides past its row while it scrolls; this is what keeps it
            // off the housing above and the rounded corners below.
            .clipped()
        }
        // Lifts the slab off a bright wallpaper. Collapsed there is nothing to
        // lift — a shadow under the housing would be a dark smudge across the
        // menu bar, which is the one thing this mode must never look like.
        .shadow(color: .black.opacity(chin.isCollapsed ? 0 : 0.28), radius: 9, y: 3)
        .animation(motion, value: width)
        .animation(motion, value: depth)
        .onAppear { hover.zone = zone }
        .onChange(of: zone) { hover.zone = $0 }
    }

    /// The resting face: one line, centred, scrolling if it has to.
    private func chinRow(_ text: String, aside: Bool, width: CGFloat, scale: CGFloat) -> some View {
        let font = NotchMetrics.chinFont(scale: scale)
        let room = max(0, width - NotchMetrics.padH * 2)
        return SlabLine(
            text: text,
            size: NotchMetrics.chinFontSize * scale,
            weight: .semibold,
            color: ink.opacity(aside ? 0.55 : 1),
            room: room,
            travel: max(0, OverlayMetrics.textWidth(text, font: font) - room),
            animated: !reduceMotion
        )
        // Keyed to the line rather than its words, so a new row is an
        // insertion that can fade in and start its own scroll instead of a
        // Text whose glyphs morph — and a lyric that repeats itself back to
        // back still counts as a new line.
        .id("\(controller.currentLineIndex)·\(text)")
        .frame(maxHeight: .infinity)
    }

    /// The hover face: the line playing, held between the two it sits between.
    private func stage(width: CGFloat, scale: CGFloat) -> some View {
        let room = max(0, width - NotchMetrics.padH * 2)
        return VStack(spacing: NotchMetrics.stageGap) {
            contextRow(controller.prevLine, room: room, scale: scale)
            focusRow(controller.currentLine, room: room, scale: scale)
            contextRow(controller.nextLine, room: room, scale: scale)
        }
        .frame(maxHeight: .infinity)
    }

    private func focusRow(_ raw: String, room: CGFloat, scale: CGFloat) -> some View {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = text.isEmpty ? "♪" : text
        let font = NotchMetrics.focusFont(scale: scale)
        return SlabLine(
            text: shown,
            size: NotchMetrics.focusFontSize * scale,
            weight: .semibold,
            color: ink,
            room: room,
            travel: max(0, OverlayMetrics.textWidth(shown, font: font) - room),
            animated: !reduceMotion
        )
        .id("focus·" + shown)
        .frame(height: NotchMetrics.row(font))
    }

    /// The line before and after. Empty at the start and end of a song; the
    /// row keeps its height either way, so the line being read never moves.
    /// These two truncate rather than scroll — three lines sliding at once is
    /// a surface nobody can read, and the one that matters is the middle.
    private func contextRow(_ text: String, room: CGFloat, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: NotchMetrics.contextFontSize * scale))
            .foregroundStyle(ink.opacity(0.4))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: room, height: NotchMetrics.row(NotchMetrics.contextFont(scale: scale)))
    }

    /// The slab is black, so a dark text colour would be invisible on it: the
    /// user's colour applies when it's a light one, and the lone dark preset
    /// (Ink, which exists for bright backdrops the slab doesn't have) falls
    /// back to white.
    private var ink: Color {
        appearance.textColor.isLight ? appearance.textColor : .white
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)
    }

    // MARK: - What the slab has to say

    private enum Chin: Equatable {
        case collapsed
        case lyric(String)
        /// Dimmed, because it's the player talking rather than the song: a
        /// lookup in flight, an instrumental countdown, a permission wall.
        case aside(String)

        var text: String? {
            switch self {
            case .collapsed: return nil
            case .lyric(let text), .aside(let text): return text
            }
        }

        var isCollapsed: Bool { self == .collapsed }

        var isLyric: Bool {
            if case .lyric = self { return true }
            return false
        }

        var isAside: Bool {
            if case .aside = self { return true }
            return false
        }
    }

    /// The notch is a lyrics surface. The empty states the card designs a whole
    /// stage for — nothing playing, no lyrics for this track — aren't worth
    /// covering the menu bar for, so they collapse the slab instead; the card,
    /// the menu-bar icon and the Find Lyrics window are all still where they
    /// were. The one exception is the permission wall: with automation access
    /// denied nothing in the app works, and a silent notch would read as a
    /// broken mode rather than as something to go and fix.
    private var chin: Chin {
        if controller.longIdle { return .collapsed }
        switch controller.stagePhase {
        case .idle, .notFound:
            return .collapsed
        case .permission:
            return .aside("Music access needed")
        case .searching:
            return .aside("Finding lyrics…")
        case .intro(let countdown, _):
            return .aside(countdown > 0 ? "♪ \(countdown)" : "♪")
        case .synced, .unsynced:
            let line = controller.currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            // An instrumental marker is a timed line with no words; the card
            // shows ♪ for it and so does the slab.
            return .lyric(line.isEmpty ? "♪" : line)
        }
    }
}

/// One row of slab text, with its own marquee.
///
/// A line too long for the slab slides left to show its tail instead of
/// shrinking or ending in an ellipsis: the words are the product, so the width
/// budget is allowed to cost *time* rather than content. Each new line gets a
/// fresh instance (rows are keyed by their text), so every pass starts from
/// the beginning and the outgoing line holds its position while it fades.
private struct SlabLine: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let color: Color
    /// Width inside the slab's padding.
    let room: CGFloat
    /// How far the line has to slide to show its end; 0 when it fits.
    let travel: CGFloat
    let animated: Bool

    @State private var offset: CGFloat = 0

    var body: some View {
        if travel > 0 && !animated {
            // Reduce Motion: nothing slides, so the tail is simply out of
            // reach and the line ends in an ellipsis.
            line
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: room)
        } else {
            line
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
                // Leading while it scrolls (the line starts at its first word),
                // centred when it fits.
                .frame(width: room, alignment: travel > 0 ? .leading : .center)
                .onAppear {
                    guard travel > 0 else { return }
                    withAnimation(
                        .linear(duration: NotchMetrics.marqueeDuration(travel: travel))
                            .delay(NotchMetrics.marqueeLeadIn)
                    ) {
                        offset = -travel
                    }
                }
        }
    }

    private var line: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
    }
}
