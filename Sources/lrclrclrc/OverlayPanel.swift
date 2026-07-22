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

        // Freeform resize (drag any edge), bounded so it stays usable.
        minSize = NSSize(width: 320, height: 90)
        maxSize = NSSize(width: 1400, height: 520)

        self.contentView = contentView
        positionBottomCenter()
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
