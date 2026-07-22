import AppKit

/// A borderless, transparent, always-on-top panel that follows the user across
/// Spaces and stays visible over full-screen apps.
final class OverlayPanel: NSPanel {
    init(contentView: NSView) {
        // A *titled* window with invisible chrome, not a borderless one: the
        // system's resize machinery (edges, cursors, the slightly-outside grab
        // region) lives in the window frame, and a borderless window whose
        // content covers everything has no frame left to own the edges — which
        // is why custom resize code never felt native. Full-size content +
        // transparent titlebar + hidden buttons looks identical to borderless
        // while resizing exactly like every other app's window.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 150),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

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

        // Freeform resize (drag any edge). There is no maximum — the screen is
        // the practical bound and making the card huge is the user's call. The
        // real minimum comes from the live floor (AppDelegate.refreshFloor) as
        // soon as launch wiring completes; this is a first-frame placeholder.
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

        // Cursor display through the native drag itself. The titled frame's
        // drag machinery runs fine while the app is inactive, but its cursor
        // display does not (cursorUpdate delivery is gated on activation),
        // and hover events die the moment the frame starts eating the drag —
        // so without this, a resize grabbed from outside the hover band runs
        // with a plain arrow. Set the grabbed edge's cursor at drag start and
        // re-assert it on every resize tick so nothing can wipe it mid-drag.
        center.addObserver(self, selector: #selector(liveResizeBegan),
                           name: NSWindow.willStartLiveResizeNotification, object: self)
        center.addObserver(self, selector: #selector(liveResizeTicked),
                           name: NSWindow.didResizeNotification, object: self)
        center.addObserver(self, selector: #selector(liveResizeEnded),
                           name: NSWindow.didEndLiveResizeNotification, object: self)
    }

    // MARK: - Resize cursor during the native edge drag

    private var liveResizeCursor: NSCursor?

    @objc private func liveResizeBegan() {
        liveResizeCursor = ResizeCursors.cursor(nearFrame: frame, screenPoint: NSEvent.mouseLocation)
        liveResizeCursor?.set()
    }

    @objc private func liveResizeTicked() {
        liveResizeCursor?.set()
    }

    @objc private func liveResizeEnded() {
        guard liveResizeCursor != nil else { return }
        liveResizeCursor = nil
        // Hand back to the hover pipeline: keep the arrows if the pointer
        // ended on an edge, plain arrow otherwise.
        (ResizeCursors.cursor(nearFrame: frame, screenPoint: NSEvent.mouseLocation) ?? .arrow).set()
    }

    // Move/resize notifications fire per frame during a drag; writing
    // UserDefaults at that rate is churn — debounce to the drag's end.
    private var persistWork: DispatchWorkItem?

    @objc private func persistFrame() {
        persistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Settings.overlayFrame = self.frame
        }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
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

    /// Apply a new live floor. `growNow` also grows the window immediately if
    /// it is below the new minimum (text-size bump, long-lined track); omitted
    /// during a live edge drag so the app never fights the user's hand.
    func updateFloor(_ newMin: CGSize, growNow: Bool) {
        minSize = NSSize(width: newMin.width, height: newMin.height)
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

    /// Back to the default size and bottom-center position (Preferences reset).
    /// The floor still applies — refreshFloor grows it right after if needed.
    func resetFrame() {
        var f = frame
        f.size = NSSize(width: max(620, minSize.width), height: max(240, minSize.height))
        setFrame(f, display: true)
        positionBottomCenter()
    }

    func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        let x = visible.origin.x + (visible.width - size.width) / 2
        let y = visible.origin.y + 40
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
