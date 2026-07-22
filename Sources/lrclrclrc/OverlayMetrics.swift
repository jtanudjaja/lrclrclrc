import AppKit

/// Single source of truth for the overlay's layout math, shared by the SwiftUI
/// card (`OverlayView`) and the panel's size constraints (via `AppDelegate`).
///
/// The card is three zones — header (measured), stage (flexible), footer
/// (constant) — and the engine's rule is *measure, don't guess*: every text
/// height comes from the real font at the real width, so the minimum window
/// size ("the floor") is an honest sum and the cramped case can't exist.
enum OverlayMetrics {
    // Base metrics in points at fontScale = 1 (multiplied by fs at call sites).
    static let vPadding: CGFloat = 28        // 14 top + 14 bottom
    static let footerH: CGFloat = 32         // one row: transport centered, timing trailing
    static let lineUnit: CGFloat = 25.5      // nominal context-line slot (15pt font * 1.7)
    static let stackSpacing: CGFloat = 16    // summed inter-zone gaps
    // The one-row footer needs ~250pt; 320 − 48 padding = 272 available, so a
    // too-narrow footer is impossible by construction (no squeezed variant).
    static let minWidthBase: CGFloat = 320

    /// Floor guarantee: hero + this many context lines always fit.
    static let minContextLines = 2

    // MARK: - Fonts (sizes must match what OverlayView renders)

    static func heroFont(fs: CGFloat) -> NSFont { .systemFont(ofSize: 22 * fs, weight: .bold) }
    static func lineFont(fs: CGFloat) -> NSFont { .systemFont(ofSize: 15 * fs) }
    static func headerFont(fs: CGFloat) -> NSFont { .systemFont(ofSize: 11 * fs, weight: .semibold) }
    static func headerArtistFont(fs: CGFloat) -> NSFont { .systemFont(ofSize: 10 * fs) }

    // MARK: - Measurement

    /// Readable text column: never wider than ~30x the line font size.
    static func measureWidth(cardWidth: CGFloat, fs: CGFloat) -> CGFloat {
        min(max(80, cardWidth - 48 * fs), 450 * fs)
    }

    /// True wrapped height of a text at a width (the "measure, don't guess" core).
    static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let sample = text.isEmpty ? "♪" : text
        let attr = NSAttributedString(string: sample, attributes: [.font: font])
        let rect = attr.boundingRect(
            with: NSSize(width: max(10, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height)
    }

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    /// True when "♪ title · artist" fits the card on a single header row.
    static func headerFitsOneRow(title: String, artist: String, fs: CGFloat, cardWidth: CGFloat) -> Bool {
        let one = "♪  \(title)   ·   \(artist)"
        return textWidth(one, font: headerFont(fs: fs)) <= cardWidth - 48 * fs
    }

    /// The floor's header term: a fixed two-row reserve (title row + artist
    /// row), pre-reserved *ahead* of any track change so switching songs never
    /// resizes the window because of the header. A rarer taller header (a title
    /// wrapping past two rows) borrows from the flexible stage instead.
    static func headerAllowance(fs: CGFloat) -> CGFloat {
        let titleRow = textHeight("Ag", font: headerFont(fs: fs), width: 10_000)
        let artistRow = textHeight("Ag", font: headerArtistFont(fs: fs), width: 10_000)
        return titleRow + artistRow + 8 * fs
    }

    // MARK: - Sub-floor safety net
    // The floor normally guarantees every zone fits. These thresholds only
    // matter if the window is somehow forced below it (tiny display clamp).

    static func headerVisible(height: CGFloat, fs: CGFloat) -> Bool { height >= 92 * fs }
    static func controlsFit(height: CGFloat, width: CGFloat, fs: CGFloat) -> Bool {
        height >= 150 * fs && width >= 280 * fs
    }

    // MARK: - The live floor

    /// Minimum content size = padding + header allowance (2 rows, reserved
    /// ahead) + tallest line of *this song* wrapped at *this width* +
    /// `minContextLines` context lines + footer. Clamped to the screen so a
    /// pathological song can't outgrow the display.
    static func minContentSize(
        fontScale: Double,
        cardWidth: CGFloat,
        lines: [LrcLine],
        clickThrough: Bool,
        screenHeight: CGFloat?
    ) -> CGSize {
        let fs = CGFloat(fontScale)
        let mWidth = measureWidth(cardWidth: max(cardWidth, minWidthBase * fs), fs: fs)
        let hero = heroFont(fs: fs)

        var tallest: CGFloat = 30 * fs // single-row hero fallback (no lyrics yet)
        for line in lines where !line.text.isEmpty {
            tallest = max(tallest, textHeight(line.text, font: hero, width: mWidth))
        }

        var height = vPadding * fs
            + headerAllowance(fs: fs)
            + tallest
            + lineUnit * fs * CGFloat(minContextLines)
            + (clickThrough ? 0 : footerH * fs)
            + stackSpacing * fs
        if let screenH = screenHeight {
            height = min(height, screenH - 60)
        }
        return CGSize(width: (minWidthBase * fs).rounded(), height: height.rounded())
    }

    /// Maximum size scales with text size so the floor can never exceed it.
    static func maxContentSize(fontScale: Double) -> CGSize {
        let fs = max(1, CGFloat(fontScale))
        return CGSize(width: 1400 * fs, height: 560 * fs)
    }
}
