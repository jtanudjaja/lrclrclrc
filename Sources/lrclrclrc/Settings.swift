import AppKit

/// Small UserDefaults-backed store for persisted app state, so the overlay's
/// position/size and the toggle states survive relaunches.
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let overlayFrame = "overlayFrame"
        static let clickThrough = "clickThrough"
        static let displayMode = "displayMode"
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
}
