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
        // Whole-background dragging would claim mouse-downs before the lyric
        // stage's scrub gesture could run — the header is the explicit drag
        // handle instead (WindowDragSurface), like a title bar.
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Freeform resize (drag any edge). Real bounds come from the live floor
        // (AppDelegate.refreshFloor) as soon as launch wiring completes; these
        // are just sane placeholders for the first frame.
        maxSize = NSSize(width: 1400, height: 560)
        minSize = NSSize(width: 320, height: 160)

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

    /// Called by EdgeResizeView when an edge drag ends: the deferred moment to
    /// recompute the live floor for the new width and grow into it (mid-drag,
    /// the stage's clipping absorbs any squeeze — spec Part 3, floor bounds).
    var onResizeSettle: (() -> Void)?
    func settleAfterResize() { onResizeSettle?() }

    /// Apply new live-floor bounds. `growNow` also grows the window immediately
    /// if it is below the new minimum (text-size bump, long-lined track);
    /// omitted during a live edge drag so the app never fights the user's hand.
    func updateSizeBounds(min newMin: CGSize, max newMax: CGSize, growNow: Bool) {
        maxSize = NSSize(width: newMax.width, height: newMax.height)
        minSize = NSSize(width: min(newMin.width, maxSize.width),
                         height: min(newMin.height, maxSize.height))
        if growNow { growToMinimum() }
    }

    /// Grow to satisfy the floor, keeping the bottom-centre anchored so the
    /// card doesn't jump; never shrinks (the user's chosen size is respected
    /// when the floor relaxes).
    private func growToMinimum() {
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
