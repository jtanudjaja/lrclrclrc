import SwiftUI

/// Accent used for the current line's glow.
enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, purple, pink, teal, orange, white

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.60, green: 0.79, blue: 1.0)
        case .purple: return Color(red: 0.75, green: 0.65, blue: 1.0)
        case .pink: return Color(red: 1.0, green: 0.66, blue: 0.86)
        case .teal: return Color(red: 0.55, green: 0.92, blue: 0.88)
        case .orange: return Color(red: 1.0, green: 0.78, blue: 0.55)
        case .white: return .white
        }
    }
}

/// User-tunable look of the overlay. Published so the overlay updates live;
/// each change persists to UserDefaults.
final class Appearance: ObservableObject {
    @Published var fontScale: Double { didSet { Settings.fontScale = fontScale } }
    @Published var backgroundOpacity: Double { didSet { Settings.backgroundOpacity = backgroundOpacity } }
    @Published var accent: AccentChoice { didSet { Settings.accent = accent.rawValue } }
    @Published var alwaysShowControls: Bool { didSet { Settings.alwaysShowControls = alwaysShowControls } }

    /// Mirrors the click-through toggle (persisted by AppDelegate) so the
    /// overlay can drop its footer reserve when controls are unreachable.
    @Published var clickThroughActive: Bool

    init() {
        fontScale = Settings.fontScale
        backgroundOpacity = Settings.backgroundOpacity
        accent = AccentChoice(rawValue: Settings.accent) ?? .blue
        alwaysShowControls = Settings.alwaysShowControls
        clickThroughActive = Settings.clickThrough
    }
}
