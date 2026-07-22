import AppKit

/// Small UserDefaults-backed store for persisted app state, so the overlay's
/// position/size and the toggle states survive relaunches.
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let overlayFrame = "overlayFrame"
        static let clickThrough = "clickThrough"
        static let menuBarLyrics = "menuBarLyrics"
        static let overlayHidden = "overlayHidden"
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

    static var menuBarLyrics: Bool {
        get { defaults.bool(forKey: Key.menuBarLyrics) }
        set { defaults.set(newValue, forKey: Key.menuBarLyrics) }
    }

    static var overlayHidden: Bool {
        get { defaults.bool(forKey: Key.overlayHidden) }
        set { defaults.set(newValue, forKey: Key.overlayHidden) }
    }
}
