import AppKit

/// A borderless, transparent, always-on-top panel that follows the user across
/// Spaces and stays visible over full-screen apps.
final class OverlayPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 150),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .screenSaver // above normal windows
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true // drag the card to reposition
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Freeform resize (drag any edge), bounded so it stays usable. The
        // minimum is derived from the current text size so the lyric band always
        // has room for at least 3 lines plus the header and footer.
        maxSize = NSSize(width: 1400, height: 520)
        applyMinimum(for: Settings.fontScale)

        self.contentView = contentView

        // Restore the last position/size, else default to bottom-center. Either
        // way the frame is clamped to the current text-size minimum.
        if let saved = Settings.overlayFrame {
            setFrame(sanitized(saved), display: false)
        } else {
            let w = max(frame.width, minSize.width)
            let hgt = max(frame.height, minSize.height)
            setFrame(NSRect(x: frame.minX, y: frame.minY, width: w, height: hgt), display: false)
            positionBottomCenter()
        }

        // Persist the frame whenever the user moves or resizes it.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(persistFrame),
                           name: NSWindow.didMoveNotification, object: self)
        center.addObserver(self, selector: #selector(persistFrame),
                           name: NSWindow.didResizeNotification, object: self)
        // Re-clamp onto a visible screen if the display setup changes.
        center.addObserver(self, selector: #selector(screensChanged),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func persistFrame() {
        Settings.overlayFrame = frame
    }

    @objc private func screensChanged() {
        setFrame(sanitized(frame), display: true)
    }

    /// Clamp a restored frame to the size bounds and keep it on a screen.
    private func sanitized(_ rect: NSRect) -> NSRect {
        var r = rect
        r.size.width = min(max(r.width, minSize.width), maxSize.width)
        r.size.height = min(max(r.height, minSize.height), maxSize.height)
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(r) }
        if !visible, let vf = NSScreen.main?.visibleFrame {
            r.origin = NSPoint(x: vf.origin.x + (vf.width - r.width) / 2,
                               y: vf.origin.y + 40)
        }
        return r
    }

    /// Grow/shrink the panel by a factor, keeping the bottom-center anchored so
    /// it doesn't wander off screen. Used by the menu's Larger/Smaller items.
    func scaleBy(_ factor: CGFloat) {
        var f = frame
        let newWidth = min(max(f.width * factor, minSize.width), maxSize.width)
        let newHeight = min(max(f.height * factor, minSize.height), maxSize.height)
        let centerX = f.midX
        let bottom = f.minY
        f.size = NSSize(width: newWidth, height: newHeight)
        f.origin.x = centerX - newWidth / 2
        f.origin.y = bottom
        setFrame(f, display: true, animate: true)
    }

    /// Set the resize floor from the current text size (without moving the
    /// window). Clamped so it never exceeds the maximum.
    func applyMinimum(for fontScale: Double) {
        let m = OverlayMetrics.minContentSize(fontScale: fontScale)
        minSize = NSSize(width: min(m.width, maxSize.width),
                         height: min(m.height, maxSize.height))
    }

    /// React to a text-size change: raise/lower the floor and, if the window is
    /// now below it, grow it to fit — keeping the bottom-centre anchored so the
    /// card doesn't jump. This is what guarantees ≥3 lyric lines stay visible as
    /// the user bumps the text larger.
    func updateForFontScale(_ fontScale: Double) {
        applyMinimum(for: fontScale)
        let f = frame
        guard f.width < minSize.width || f.height < minSize.height else { return }
        let newW = max(f.width, minSize.width)
        let newH = max(f.height, minSize.height)
        var grown = f
        grown.origin.x = f.midX - newW / 2
        grown.origin.y = f.minY // keep the bottom edge pinned
        grown.size = NSSize(width: newW, height: newH)
        setFrame(sanitized(grown), display: true, animate: true)
    }

    // Never steal focus from the app the user is actually working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        let x = visible.origin.x + (visible.width - size.width) / 2
        let y = visible.origin.y + 40
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
