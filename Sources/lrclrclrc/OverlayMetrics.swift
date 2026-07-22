import CoreGraphics

/// Single source of truth for the overlay's vertical layout, shared by the
/// SwiftUI card (`OverlayView`) and the panel's size constraints
/// (`OverlayPanel`). Keeping the numbers in one place means the "always fit N
/// lyric lines + header + footer" rule can't drift between what we *render* and
/// what we *allow the window to be resized to*.
///
/// The card is three stacked components, each reacting to **window height** and
/// **text size** (every value scales with `fontScale`):
///   • **header**  — title · artist (top)
///   • **lyrics**  — the middle band, guaranteed at least `minLyricLines`
///   • **footer**  — "synced · LRCLIB" credit + transport / timing controls
enum OverlayMetrics {
    // Base heights in points at fontScale = 1. Everything is multiplied by the
    // current fontScale at the call site.
    static let vPadding: CGFloat = 28        // 14 top + 14 bottom
    static let headerH: CGFloat = 22
    static let statusH: CGFloat = 16
    static let controlsSyncedH: CGFloat = 52 // transport + timing rows
    static let controlsPlainH: CGFloat = 28  // transport row only
    static let lineUnit: CGFloat = 25.5      // one lyric line ≈ lineSize(15) * 1.7
    static let stackSpacing: CGFloat = 20    // summed inter-component gaps

    /// Hard floor: the lyric band must always be able to show at least this many
    /// lines at the current text size.
    static let minLyricLines = 3

    /// Base minimum width — the transport row needs ~240pt; the rest leaves room
    /// for the header and for lyric lines to wrap comfortably.
    static let minWidthBase: CGFloat = 300

    // Component visibility thresholds. These are a graceful-degradation net for
    // the rare case where the window is somehow smaller than the enforced
    // minimum (e.g. a tiny external display); normally `minContentSize` keeps
    // the window big enough that all three components are always present.
    static func headerVisible(height: CGFloat, fs: CGFloat) -> Bool { height >= 92 * fs }
    static func statusVisible(height: CGFloat, fs: CGFloat) -> Bool { height >= 148 * fs }
    static func controlsFit(height: CGFloat, width: CGFloat, fs: CGFloat) -> Bool {
        height >= 188 * fs && width >= 240 * fs
    }

    /// The minimum content size for a given text size: enough for the full
    /// header + footer + `minLyricLines` lyric lines + padding. The window is
    /// never allowed to be resized (or auto-grown) below this.
    static func minContentSize(fontScale: Double) -> CGSize {
        let fs = CGFloat(fontScale)
        let height = (vPadding + headerH + statusH + controlsSyncedH
                      + lineUnit * CGFloat(minLyricLines) + stackSpacing) * fs
        return CGSize(width: (minWidthBase * fs).rounded(),
                      height: height.rounded())
    }
}
