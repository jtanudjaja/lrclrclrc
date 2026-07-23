import SwiftUI
import AppKit

/// Quick-pick text colours, built in OKLCh and checked by rendering the card
/// over real backdrops: a white page of black body text, a dark IDE with
/// syntax colour, a bright multi-colour site, album art, mid grey, near-black.
///
/// What those renders settle:
///
/// Legibility is decided by the *backdrop's* lightness, not by the colour's
/// chroma. Over a white page every light colour fails — white included, since
/// the card is nearly transparent at rest and the text lands on the page's own
/// black type. Over an IDE or album art the dark ones fail just as completely.
/// No single colour survives both, which is why the presets split into a light
/// group and a dark one either side of the picker's divider. Chasing a single
/// survives-everywhere set only produces near-whites: safe, indistinguishable,
/// and useless as a *choice*.
///
/// Within a family, hue is free — so it is taste, and one swatch each is
/// enough: five hues that stay apart at a glance, not a spectrum. The tints are
/// cut at OKLCh L=0.80 with each hue at 85% of its sRGB gamut chroma — even
/// perceived brightness, as vivid as the gamut allows without clipping a
/// channel flat. Below that lightness colour muddies against dark art; above
/// it, blue and violet wash out as the gamut narrows toward white.
///
/// Hues are the ones that survived being looked at, not an even 72° sweep:
/// even spacing puts a hue at ~117°, which renders olive. Cyan and coral went
/// too, sitting close enough to green and gold to spend a swatch on a
/// near-duplicate.
///
/// Ink is the only dark preset. Over a bright backdrop the job is legibility
/// rather than taste, and a tinted dark (navy, plum) is a wheel colour away —
/// so the row keeps one entry that always works instead of a second family.
struct TextColorPreset: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
    var color: Color { Color(hex: hex) ?? .white }

    /// For dark wallpaper, album art, video, dark editors — the card's usual home.
    static let light: [TextColorPreset] = [
        TextColorPreset(name: "White", hex: "#FFFFFF"),
        TextColorPreset(name: "Gold", hex: "#F3AF43"),
        TextColorPreset(name: "Green", hex: "#4CDE79"),
        TextColorPreset(name: "Blue", hex: "#92C3F5"),
        TextColorPreset(name: "Violet", hex: "#C7AFF6"),
        TextColorPreset(name: "Pink", hex: "#F69DD0"),
    ]

    /// For a bright desktop, a document, or a light-themed app underneath.
    static let dark: [TextColorPreset] = [
        TextColorPreset(name: "Ink", hex: "#121213"),
    ]
}

/// User-tunable look of the overlay. Published so the overlay updates live;
/// each change persists to UserDefaults.
final class Appearance: ObservableObject {
    @Published var fontScale: Double { didSet { Settings.fontScale = fontScale } }
    @Published var backgroundOpacity: Double { didSet { Settings.backgroundOpacity = backgroundOpacity } }
    @Published var textColor: Color { didSet { Settings.textColor = textColor.hexString } }
    @Published var alwaysShowControls: Bool { didSet { Settings.alwaysShowControls = alwaysShowControls } }

    /// The pole opposite the text: black under a light colour, white under a
    /// dark one. Everything the text has to be read *against* rides on this —
    /// the legibility halo and the card's own scrim — so picking a dark text
    /// colour flips the card light instead of leaving dark-on-dark once the
    /// hover face comes up.
    var contrast: Color { textColor.isLight ? .black : .white }

    /// The halo behind the text, so a custom colour stays readable over any
    /// wallpaper. Also the hero line's bloom and the backing under the small
    /// filled chips: there is no third colour in the overlay, because anything
    /// that sits *behind* the text has exactly one correct pole and it is this
    /// one. A tinted accent bloom could only be brighter or darker than the
    /// wallpaper by luck; this is right on every wallpaper by construction.
    var textShadow: Color { contrast }

    /// Materials (Liquid Glass, the legacy thin material) shade themselves from
    /// the colour scheme rather than a tint, so the card's scheme has to follow
    /// the same flip.
    var surfaceScheme: ColorScheme { textColor.isLight ? .dark : .light }

    /// Mirrors the click-through toggle (persisted by AppDelegate) so the
    /// overlay can drop its footer reserve when controls are unreachable.
    @Published var clickThroughActive: Bool

    init() {
        fontScale = Settings.fontScale
        backgroundOpacity = Settings.backgroundOpacity
        textColor = Color(hex: Settings.textColor) ?? .white
        alwaysShowControls = Settings.alwaysShowControls
        clickThroughActive = Settings.clickThrough
    }
}

extension Color {
    /// sRGB "#RRGGBB" — the persisted form of the text colour.
    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let parts = [c.redComponent, c.greenComponent, c.blueComponent]
            .map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
    }

    /// Perceived brightness above the midpoint (unconvertible colours read as
    /// light, matching the white default).
    var isLight: Bool {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return true }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.5
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let n = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((n >> 16) & 0xFF) / 255,
                  green: Double((n >> 8) & 0xFF) / 255,
                  blue: Double(n & 0xFF) / 255)
    }
}
