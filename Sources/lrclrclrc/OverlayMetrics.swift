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
    // Vertical padding and the inter-zone gaps now belong to the tier — see
    // `Tier.vPad` and `tierHeight` — because both ease off as the card shrinks.
    static let footerH: CGFloat = 32         // one row: transport leading, timing trailing
    static let lineUnit: CGFloat = 25.5      // nominal context-line slot (15pt font * 1.7)
    static let hPadding: CGFloat = 48        // 24 leading + 24 trailing
    // The one-row footer needs ~195pt — transport 86 (3 × 22pt hit targets +
    // 2 × 10 gaps), timing 96 (2 × 22 + 2 × 6 + the 40pt readout floor), and
    // the spacer's 12pt minimum between them. 250 − 48 padding = 202
    // available, so a too-narrow footer is impossible by construction (no
    // squeezed variant) in the tiers that have one.
    //
    // Below ~220 the active row starts wrapping an extra time for ordinary
    // lyrics, and the height the floor then demands outruns the width saved —
    // the card gets *larger* in area. 250 sits clear of both limits.
    static let minWidthBase: CGFloat = 250

    /// Blur radius for the hero line's bloom, sized against the side inset so
    /// the pool stays inside the card's rounded clip at any window width. A
    /// narrow window is the case that matters: the focus line then runs the
    /// full content width, so its bloom starts at the padding rather than
    /// somewhere in the middle of it and the whole inset is all the room it
    /// gets.
    static func heroGlowRadius(fs: CGFloat) -> CGFloat { (hPadding / 2) / 3 * fs }

    /// How far past its nominal radius the bloom actually paints. A Core
    /// Graphics shadow carries visible alpha to roughly three times its radius,
    /// so anything that clips the band has to be held off by this much to cut
    /// nothing — see the band's mask in `OverlayView`.
    static func heroGlowBleed(fs: CGFloat) -> CGFloat { heroGlowRadius(fs: fs) * 3 }

    // MARK: - Fonts (sizes must match what OverlayView renders)

    static func heroFont(fs: CGFloat) -> NSFont { .systemFont(ofSize: 22 * fs, weight: .bold) }
    static func lineFont(fs: CGFloat) -> NSFont { .systemFont(ofSize: 15 * fs) }
    static func headerFont(fs: CGFloat) -> NSFont { .systemFont(ofSize: 11 * fs, weight: .semibold) }
    static func headerArtistFont(fs: CGFloat) -> NSFont { .systemFont(ofSize: 10 * fs) }
    static func sourceChipFont(fs: CGFloat) -> NSFont { .systemFont(ofSize: 8.5 * fs, weight: .semibold) }

    // MARK: - Header furniture (art tile, source chip)

    /// The art tile's side. Deliberately under `headerAllowance` — the tile
    /// rides *inside* the two rows the floor already reserves for the title and
    /// artist, so adding it can never grow the header or shrink the stage.
    static let artTile: CGFloat = 26
    static let artGap: CGFloat = 8

    /// Content width the header actually gets, after the card's own padding.
    static func headerWidth(cardWidth: CGFloat, fs: CGFloat) -> CGFloat {
        max(0, cardWidth - hPadding * fs)
    }

    /// The title is the header's job; the tile and the chip are furniture
    /// around it. When furniture and title compete for a narrow row the
    /// furniture loses, so the title never truncates and never has to wrap into
    /// a row it wouldn't otherwise need — a header that grows takes its extra
    /// row from the stage, which is the one thing on the card that shouldn't
    /// pay for decoration.
    ///
    /// The floor for a title too long to fit on one row at any of these widths:
    /// it's wrapping regardless, so the choice is only how much of the row it
    /// keeps, and half of it is enough to stay the header's subject.
    private static let titleFloor: CGFloat = 0.5

    /// Room the title column has left once the furniture has taken its width.
    private static func titleColumn(cardWidth: CGFloat, fs: CGFloat,
                                    art: Bool, chip: CGFloat) -> CGFloat {
        headerWidth(cardWidth: cardWidth, fs: fs)
            - (art ? (artTile + artGap) * fs : 0)
            - (chip > 0 ? chip + artGap * fs : 0)
    }

    /// One unwrapped row of this title.
    private static func titleRowWidth(_ title: String, fs: CGFloat) -> CGFloat {
        textWidth(title, font: headerFont(fs: fs))
    }

    /// True when the art tile fits. The tile is cheap (34pt beside a title
    /// column measured in hundreds) and it's the element that identifies the
    /// track, so it yields only on a row too cramped to carry it at all —
    /// unlike the chip, it may cost a wrapping title a row.
    static func artFits(title: String, cardWidth: CGFloat, fs: CGFloat) -> Bool {
        let content = headerWidth(cardWidth: cardWidth, fs: fs)
        let column = titleColumn(cardWidth: cardWidth, fs: fs, art: true, chip: 0)
        return column >= min(titleRowWidth(title, fs: fs), content * titleFloor)
    }

    /// Laid-out width of the source chip, tracking and padding included.
    static func sourceChipWidth(_ name: String, fs: CGFloat) -> CGFloat {
        let label = name.uppercased()
        return textWidth(label, font: sourceChipFont(fs: fs))
            + 0.6 * fs * CGFloat(label.count)  // tracking, which textWidth omits
            + 14 * fs                          // horizontal padding
            + 2                                // capsule border
    }

    /// True when the chip fits *after* the tile has taken its width, and the
    /// title still lands on one row beside it.
    ///
    /// The chip is held to a stricter test than the tile because it's worth
    /// less: it names a player the user already chose, and it's wide — most of
    /// a hundred points for "APPLE MUSIC". So it is never allowed to be the
    /// reason a title wraps. A long title simply doesn't get a chip until the
    /// card is wide enough to carry both, which is the same answer at every
    /// width rather than a threshold that pops it in and out mid-song.
    static func sourceChipFits(_ name: String, title: String,
                               cardWidth: CGFloat, fs: CGFloat) -> Bool {
        guard !name.isEmpty else { return false }
        let art = artFits(title: title, cardWidth: cardWidth, fs: fs)
        let column = titleColumn(cardWidth: cardWidth, fs: fs, art: art,
                                 chip: sourceChipWidth(name, fs: fs))
        return column >= titleRowWidth(title, fs: fs)
    }

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

    /// The floor's header term: a fixed two-row reserve (title row + artist
    /// row), pre-reserved *ahead* of any track change so switching songs never
    /// resizes the window because of the header. A rarer taller header (a title
    /// wrapping past two rows) borrows from the flexible stage instead.
    static func headerAllowance(fs: CGFloat) -> CGFloat {
        let titleRow = textHeight("Ag", font: headerFont(fs: fs), width: 10_000)
        let artistRow = textHeight("Ag", font: headerArtistFont(fs: fs), width: 10_000)
        return titleRow + artistRow + 8 * fs
    }

    // MARK: - The tier ladder
    //
    // The card sheds furniture as it shrinks, in order of how recoverable each
    // piece is elsewhere. Nothing here is a safety net — every tier is a
    // designed layout, and the renderer picks one by reading the geometry it
    // was actually given.
    //
    // What is *not* negotiable is the active row. It is a floor term, never a
    // budget item: every tier reserves its full wrapped height, and the fade's
    // opaque band is clamped to contain it (`edgeFadeSpan`). Context lines,
    // chrome and padding all yield first.

    enum Tier: Int, Comparable {
        case bare = 0    // the active row, alone
        case minimal     // + context lines
        case compact     // + header (one row)
        case snug        // + footer
        case full        // + artist row, two context lines

        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }

        /// Header rows: 2 carries the artist, 1 is title-only, 0 is gone.
        var headerRows: Int {
            switch self {
            case .full: return 2
            case .snug, .compact: return 1
            case .minimal, .bare: return 0
            }
        }

        var hasFooter: Bool { self >= .snug }

        /// Context lines *guaranteed* — a taller card simply fits more, since
        /// the teleprompter fills whatever budget it's handed.
        var contextLines: Int {
            switch self {
            case .full: return 2
            case .snug, .compact, .minimal: return 1
            case .bare: return 0
            }
        }

        /// Vertical padding eases off with the card: 14pt above and below is
        /// most of a Bare card, and reads as a border rather than as breathing
        /// room.
        var vPad: CGFloat {
            switch self {
            case .full, .snug: return 14
            case .compact: return 10
            case .minimal, .bare: return 7
            }
        }
    }

    /// Height this tier needs, given the active row's measured height. The
    /// hero term is passed in rather than measured here so the caller can
    /// reuse one measurement across all five tiers.
    static func tierHeight(_ tier: Tier, heroHeight: CGFloat, fs: CGFloat, clickThrough: Bool) -> CGFloat {
        let header = tier.headerRows == 2 ? headerAllowance(fs: fs)
                   : tier.headerRows == 1 ? headerTitleRow(fs: fs) : 0
        let footer = (tier.hasFooter && !clickThrough) ? footerH * fs : 0
        // One 5pt gap per zone that's actually present, matching the card's
        // VStack spacing.
        let gaps = ((tier.headerRows > 0 ? 1 : 0) + (footer > 0 ? 1 : 0)) * 5 * fs
        return tier.vPad * 2 * fs
            + header + footer + gaps
            + heroHeight
            + lineUnit * fs * CGFloat(tier.contextLines)
    }

    /// The richest tier this geometry can carry without cutting the active row.
    static func tier(height: CGFloat, heroHeight: CGFloat, fs: CGFloat, clickThrough: Bool) -> Tier {
        let ladder: [Tier] = [.full, .snug, .compact, .minimal]
        for t in ladder where height >= tierHeight(t, heroHeight: heroHeight, fs: fs, clickThrough: clickThrough) {
            return t
        }
        return .bare
    }

    /// One header row (title, no artist).
    static func headerTitleRow(fs: CGFloat) -> CGFloat {
        textHeight("Ag", font: headerFont(fs: fs), width: 10_000) + 3 * fs
    }

    // MARK: - The active row

    /// Tallest the active row can get in this track at this width. Measured
    /// over `candidates` — the handful of longest lines, picked once per track
    /// by `LyricsController` — rather than the whole song, because this runs on
    /// every step of a live resize and a full re-measure is O(lines) of text
    /// layout per frame.
    ///
    /// Always measured at the *nominal* hero font. The floor's job is to
    /// guarantee 22pt fits; the renderer's clamped-down size must never feed
    /// back into it, or the two chase each other downward.
    static func heroHeight(candidates: [String], cardWidth: CGFloat, fs: CGFloat) -> CGFloat {
        let mWidth = measureWidth(cardWidth: max(cardWidth, minWidthBase * fs), fs: fs)
        let font = heroFont(fs: fs)
        var tallest: CGFloat = 30 * fs // single-row fallback: no lyrics yet
        for text in candidates where !text.isEmpty {
            tallest = max(tallest, textHeight(text, font: font, width: mWidth))
        }
        return tallest
    }

    /// Half-span of the stage's top/bottom dissolve, as a fraction of the
    /// stage. Two existing terms — a cap, and a line-height-aware ramp — plus
    /// the one that protects the active row: the opaque band must always
    /// contain the hero slot. That third term only binds on a short stage (at
    /// 300pt it evaluates to ~0.45 and loses to the ramp), so the full-size
    /// card is unchanged.
    static func edgeFadeSpan(stageHeight: CGFloat, heroHeight: CGFloat, fs: CGFloat) -> CGFloat {
        let ramp = (lineUnit * 1.3 * fs) / max(1, stageHeight)
        let clearOfHero = max(0, (stageHeight - heroHeight) / 2) / max(1, stageHeight)
        return min(0.35, ramp, clearOfHero)
    }

    // MARK: - The live floor

    /// The absolute minimum: Bare padding around the active row, nothing else.
    ///
    /// Deliberately a single value rather than one floor per tier. Tiers are a
    /// *rendering* decision read from the geometry; if the floor also depended
    /// on the tier, and the tier on the height, `minSize` would feed back into
    /// the thing that chose it. This way `growToMinimum` keeps one meaning at
    /// every size: grow until the active row fits.
    static func minContentSize(
        fontScale: Double,
        cardWidth: CGFloat,
        heroCandidates: [String],
        screenHeight: CGFloat?
    ) -> CGSize {
        let fs = CGFloat(fontScale)
        let hero = heroHeight(candidates: heroCandidates, cardWidth: cardWidth, fs: fs)
        var height = Tier.bare.vPad * 2 * fs + hero
        if let screenH = screenHeight {
            height = min(height, screenH - 60)
        }
        return CGSize(width: (minWidthBase * fs).rounded(), height: height.rounded())
    }

}
