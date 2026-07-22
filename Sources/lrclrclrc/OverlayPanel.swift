import AppKit

/// A borderless, transparent, always-on-top panel that follows the user across
/// Spaces and stays visible over full-screen apps.
final class OverlayPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
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

        self.contentView = contentView
        positionBottomCenter()
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
