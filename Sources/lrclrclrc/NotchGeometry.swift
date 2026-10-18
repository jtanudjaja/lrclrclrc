import AppKit

/// Where the camera housing is, and how much room the slab may claim around it.
///
/// macOS never hands the notch over directly: `safeAreaInsets.top` is its
/// height and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are the two
/// strips of menu bar either side of it, so the housing is what's left in
/// between. Its centre comes from those strips rather than from `midX` — they
/// differ by a point on real hardware, and a point off-centre shows when the
/// slab is only as wide as the housing it's meant to disappear into.
struct NotchGeometry {
    /// The display the slab docks to.
    let screen: NSScreen

    /// The band at the top of the screen the chin has to stay below: the
    /// camera housing where there is one, the menu bar's own height where
    /// there isn't. Nothing drawn inside it can be read — behind the housing
    /// there is no display at all — so in the layout it's only the slab's
    /// reach up into the bezel.
    let housingHeight: CGFloat

    /// The housing's width; 0 on a Mac without a notch.
    let housingWidth: CGFloat

    /// Screen x the slab centres on.
    let housingCenterX: CGFloat

    /// Points of menu bar the slab may cover on each side of the housing.
    let wing: CGFloat

    var hasNotch: Bool { housingWidth > 0 }

    /// The widest the slab can ever get — and so the stage window's width,
    /// which is fixed at exactly this (see `NotchPanel`).
    var maxSlabWidth: CGFloat { housingWidth + wing * 2 }

    /// Collapsed, the slab is exactly the housing, which on a notched Mac
    /// hides it behind the camera — that's the whole trick: a notch mode that
    /// spends most of its life looking like a notch. Without a notch there's
    /// nothing to hide behind, so collapsed means gone.
    var collapsedWidth: CGFloat { housingWidth }

    /// The built-in notched display when there is one. The ask is literally
    /// "in the black bar", so an external monitor never wins this vote even
    /// when it's the main screen; everywhere else the mode degrades honestly
    /// into a tab hanging from the middle of the menu bar.
    static func current() -> NotchGeometry? {
        let notched = NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil }
        guard let screen = notched ?? NSScreen.main else { return nil }
        let frame = screen.frame

        let housingHeight: CGFloat
        let housingWidth: CGFloat
        let centerX: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            housingHeight = left.height
            housingWidth = max(0, frame.width - left.width - right.width)
            centerX = left.maxX + housingWidth / 2
        } else {
            // No notch: the menu bar is the band to stay out of. `visibleFrame`
            // also excludes the Dock, so only its top edge is read here. The
            // floor is for the case where the menu bar is auto-hidden and the
            // difference comes back as zero — the slab would otherwise start
            // its text at the very top of the screen.
            housingHeight = max(24, frame.maxY - screen.visibleFrame.maxY)
            housingWidth = 0
            centerX = frame.midX
        }

        // How much menu bar the slab may take on each side. The menus live at
        // the far left and the status items at the far right, so the middle is
        // nearly always empty — but "nearly always" is why this is a budget
        // and not the whole bar: ~170pt a side stays clear of both ends on
        // every built-in display, and a long lyric shrinks (and finally
        // truncates) rather than growing into them.
        let wing = max(0, min(170, (frame.width - housingWidth) / 2 - 24))

        return NotchGeometry(screen: screen, housingHeight: housingHeight,
                             housingWidth: housingWidth, housingCenterX: centerX, wing: wing)
    }
}

/// The slab's layout math, in one place for the same reason `OverlayMetrics`
/// exists: the window's size, the view's drawing and the pointer's hover
/// target all have to agree, and every text height is measured at the real
/// font rather than guessed.
enum NotchMetrics {
    static let chinFontSize: CGFloat = 13.5
    static let focusFontSize: CGFloat = 15
    static let contextFontSize: CGFloat = 12
    static let padH: CGFloat = 18
    static let padV: CGFloat = 7
    /// Between the stage's three rows.
    static let stageGap: CGFloat = 5
    /// The chin's bottom corners. Close to the housing's own radius, which is
    /// what makes the two read as one piece rather than a box under a curve.
    static let cornerRadius: CGFloat = 13
    /// Headroom in the window for the slab's drop shadow, which paints past
    /// the shape itself and would otherwise be clipped by the window edge.
    static let shadowRoom: CGFloat = 20

    /// The overlay's text-size knob, held to a range the notch can carry. The
    /// slab's width is fixed by the menu bar around it, so past ~1.2x a bigger
    /// font only costs words — the knob still *reads* here, inside the room
    /// that exists.
    static let maxScale: CGFloat = 1.2

    /// Marquee pace, in points per second, and the pause before it starts.
    /// A line gets read from its beginning first, then walks at about the
    /// speed of reading — fast enough to reach the end inside the few seconds
    /// a lyric is on screen, slow enough to follow.
    static let marqueeSpeed: Double = 46
    static let marqueeLeadIn: Double = 0.9
    /// However long the line, the pass ends inside this. A synced line holds
    /// the screen for a few seconds at most, and a tail that was still
    /// crawling when the next line arrived was never going to be read —
    /// better to hurry the rare monster than to never finish it.
    static let marqueeMaxPass: Double = 4

    static func scale(_ fontScale: Double) -> CGFloat {
        min(max(CGFloat(fontScale), 0.9), maxScale)
    }

    static func chinFont(scale: CGFloat) -> NSFont {
        .systemFont(ofSize: chinFontSize * scale, weight: .semibold)
    }

    static func focusFont(scale: CGFloat) -> NSFont {
        .systemFont(ofSize: focusFontSize * scale, weight: .semibold)
    }

    static func contextFont(scale: CGFloat) -> NSFont {
        .systemFont(ofSize: contextFontSize * scale)
    }

    /// How long one scroll of `travel` points takes.
    static func marqueeDuration(travel: CGFloat) -> Double {
        min(Double(travel) / marqueeSpeed, marqueeMaxPass)
    }

    /// One row of this font, measured.
    static func row(_ font: NSFont) -> CGFloat {
        OverlayMetrics.textHeight("Ag", font: font, width: 10_000)
    }

    /// The resting slab: one row of text and its padding.
    static func chinHeight(scale: CGFloat) -> CGFloat {
        (row(chinFont(scale: scale)) + padV * 2).rounded()
    }

    /// The hover slab: the line playing, with the line before and after it.
    static func stageHeight(scale: CGFloat) -> CGFloat {
        (row(focusFont(scale: scale)) + row(contextFont(scale: scale)) * 2
            + stageGap * 2 + padV * 2).rounded()
    }

    /// Wide enough to hold the line, never narrower than the housing (a slab
    /// inside the notch is a slab nobody can see), never wider than the wings.
    /// A line past that budget keeps its words and scrolls instead — see
    /// `SlabLine` — so this is a width cap, not a limit on what can be read.
    static func slabWidth(for text: String, scale: CGFloat, in geometry: NotchGeometry) -> CGFloat {
        width(OverlayMetrics.textWidth(text, font: chinFont(scale: scale)), in: geometry)
    }

    /// The hover stage's width: its widest row, and never narrower than the
    /// chin it grew out of. That floor is load-bearing — the hover target is
    /// the slab's own rect, so a stage that pulled in at the sides could lose
    /// the pointer that opened it and flicker shut under the user's hand.
    static func stageWidth(focus: String, context: [String], chinWidth: CGFloat,
                           scale: CGFloat, in geometry: NotchGeometry) -> CGFloat {
        let focusRow = OverlayMetrics.textWidth(focus, font: focusFont(scale: scale))
        let contextRow = context
            .map { OverlayMetrics.textWidth($0, font: contextFont(scale: scale)) }
            .max() ?? 0
        return max(width(max(focusRow, contextRow), in: geometry), chinWidth)
    }

    private static func width(_ content: CGFloat, in geometry: NotchGeometry) -> CGFloat {
        min(max(content + padH * 2, geometry.housingWidth), geometry.maxSlabWidth).rounded()
    }

    /// The stage window's height: the deepest the slab can get — the hover
    /// stage at the top of the scale range — plus the shadow's room. Sized for
    /// the maximum rather than for the current state on purpose: the window
    /// then never resizes, so opening, closing and every line change is a
    /// SwiftUI animation instead of a window-server one.
    static func windowHeight(for geometry: NotchGeometry) -> CGFloat {
        geometry.housingHeight + stageHeight(scale: maxScale) + shadowRoom
    }
}

/// The live geometry, republished when the display setup changes — a monitor
/// plugged in, a resolution switch, a lid closed. The housing's size and
/// centre are screen facts, and a stale copy either parks the chin off-centre
/// or sizes the window for a screen that's gone.
final class NotchDock: ObservableObject {
    @Published private(set) var geometry: NotchGeometry?

    init() {
        geometry = NotchGeometry.current()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func refresh() {
        geometry = NotchGeometry.current()
    }
}
