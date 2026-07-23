import AppKit

/// Small UserDefaults-backed store for persisted app state, so the overlay's
/// position/size and the toggle states survive relaunches.
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let overlayFrame = "overlayFrame"
        static let clickThrough = "clickThrough"
        static let displayMode = "displayMode"
        static let disabledSources = "disabledSources"
        static let sourceAppPaths = "sourceAppPaths"
        static let selectedSource = "selectedSource"
        static let fontScale = "fontScale"
        static let backgroundOpacity = "backgroundOpacity"
        static let textColor = "textColor"
        static let alwaysShowControls = "alwaysShowControls"
        static let hasOnboarded = "hasOnboarded"
    }

    static var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }

    /// Overlay window frame (position + size), stored as a string.
    static var overlayFrame: NSRect? {
        get {
            guard let s = defaults.string(forKey: Key.overlayFrame) else { return nil }
            let r = NSRectFromString(s)
            return (r.width > 0 && r.height > 0) ? r : nil
        }
        set {
            guard let r = newValue else { return }
            defaults.set(NSStringFromRect(r), forKey: Key.overlayFrame)
        }
    }

    static var clickThrough: Bool {
        get { defaults.bool(forKey: Key.clickThrough) }
        set { defaults.set(newValue, forKey: Key.clickThrough) }
    }

    /// Raw value of DisplayMode ("overlay" / "menuBar" / "hidden").
    static var displayMode: String {
        get { defaults.string(forKey: Key.displayMode) ?? DisplayMode.overlay.rawValue }
        set { defaults.set(newValue, forKey: Key.displayMode) }
    }

    /// Raw values of the players the user has switched *off*. Storing the
    /// opt-outs rather than the opt-ins is what lets a player installed later be
    /// followed automatically: unknown means "yes, if it's there".
    static var disabledSources: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.disabledSources) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.disabledSources) }
    }

    /// Which enabled player the lyrics follow, as a PlayerSourceKind raw value.
    /// nil means automatic: whichever enabled player is actually playing.
    static var selectedSource: String? {
        get { defaults.string(forKey: Key.selectedSource) }
        set { defaults.set(newValue, forKey: Key.selectedSource) }
    }

    /// Where a player lives when LaunchServices can't find it and the user
    /// pointed us at it by hand, keyed by PlayerSourceKind raw value.
    static func sourceAppPath(for kind: PlayerSourceKind) -> String? {
        (defaults.dictionary(forKey: Key.sourceAppPaths) as? [String: String])?[kind.rawValue]
    }

    static func setSourceAppPath(_ path: String?, for kind: PlayerSourceKind) {
        var map = (defaults.dictionary(forKey: Key.sourceAppPaths) as? [String: String]) ?? [:]
        map[kind.rawValue] = path
        defaults.set(map, forKey: Key.sourceAppPaths)
    }

    // MARK: - Appearance

    static var fontScale: Double {
        get { let v = defaults.double(forKey: Key.fontScale); return v == 0 ? 1.0 : v }
        set { defaults.set(newValue, forKey: Key.fontScale) }
    }

    static var backgroundOpacity: Double {
        get { defaults.object(forKey: Key.backgroundOpacity) as? Double ?? 0.08 }
        set { defaults.set(newValue, forKey: Key.backgroundOpacity) }
    }

    /// Lyric/chrome text colour as "#RRGGBB".
    static var textColor: String {
        get { defaults.string(forKey: Key.textColor) ?? "#FFFFFF" }
        set { defaults.set(newValue, forKey: Key.textColor) }
    }

    static var alwaysShowControls: Bool {
        get { defaults.bool(forKey: Key.alwaysShowControls) }
        set { defaults.set(newValue, forKey: Key.alwaysShowControls) }
    }
}
