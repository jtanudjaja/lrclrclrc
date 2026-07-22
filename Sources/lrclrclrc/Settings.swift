import AppKit

/// Small UserDefaults-backed store for persisted app state, so the overlay's
/// position/size and the toggle states survive relaunches.
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let overlayFrame = "overlayFrame"
        static let clickThrough = "clickThrough"
        static let displayMode = "displayMode"
        static let source = "source"
        static let fontScale = "fontScale"
        static let backgroundOpacity = "backgroundOpacity"
        static let accent = "accent"
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

    /// Raw value of PlayerSourceKind ("auto" / "appleMusic" / "spotify").
    static var source: String {
        get { defaults.string(forKey: Key.source) ?? PlayerSourceKind.auto.rawValue }
        set { defaults.set(newValue, forKey: Key.source) }
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

    static var accent: String {
        get { defaults.string(forKey: Key.accent) ?? AccentChoice.blue.rawValue }
        set { defaults.set(newValue, forKey: Key.accent) }
    }

    static var alwaysShowControls: Bool {
        get { defaults.bool(forKey: Key.alwaysShowControls) }
        set { defaults.set(newValue, forKey: Key.alwaysShowControls) }
    }
}
