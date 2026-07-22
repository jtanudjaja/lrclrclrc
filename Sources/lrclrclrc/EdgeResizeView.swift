import AppKit

/// Transparent overlay that gives a borderless panel real resize behavior:
/// it shows the resize cursor along the edges/corners and drags to resize,
/// while letting the interior pass through to the SwiftUI content (so the
/// card still drags-to-move and reacts to hover).
final class EdgeResizeView: NSView {
    private struct Edge: OptionSet {
        let rawValue: Int
        static let left = Edge(rawValue: 1 << 0)
        static let right = Edge(rawValue: 1 << 1)
        static let top = Edge(rawValue: 1 << 2)
        static let bottom = Edge(rawValue: 1 << 3)
    }

    private let thickness: CGFloat = 8
    private weak var panel: NSWindow?
    private var activeEdge: Edge = []
    private var startFrame: NSRect = .zero

    init(window: NSWindow) {
        self.panel = window
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // Only claim the thin border region; the interior falls through so the
    // SwiftUI card keeps its own mouse handling.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        return edge(at: local).isEmpty ? nil : self
    }

    private func edge(at p: NSPoint) -> Edge {
        var e: Edge = []
        if p.x <= thickness { e.insert(.left) }
        if p.x >= bounds.width - thickness { e.insert(.right) }
        if p.y <= thickness { e.insert(.bottom) } // AppKit y is bottom-up
        if p.y >= bounds.height - thickness { e.insert(.top) }
        return e
    }

    override func resetCursorRects() {
        let t = thickness
        let w = bounds.width, h = bounds.height
        guard w > 2 * t, h > 2 * t else { return }

        // Edges.
        addCursorRect(NSRect(x: 0, y: t, width: t, height: h - 2 * t), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: w - t, y: t, width: t, height: h - 2 * t), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: t, y: 0, width: w - 2 * t, height: t), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: t, y: h - t, width: w - 2 * t, height: t), cursor: .resizeUpDown)

        // Corners (no public diagonal cursor; crosshair reads as a grab point).
        let corner = NSCursor.crosshair
        addCursorRect(NSRect(x: 0, y: 0, width: t, height: t), cursor: corner)
        addCursorRect(NSRect(x: w - t, y: 0, width: t, height: t), cursor: corner)
        addCursorRect(NSRect(x: 0, y: h - t, width: t, height: t), cursor: corner)
        addCursorRect(NSRect(x: w - t, y: h - t, width: t, height: t), cursor: corner)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        activeEdge = edge(at: local)
        startFrame = panel?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel, !activeEdge.isEmpty else { return }
        let mouse = NSEvent.mouseLocation // screen coordinates
        let minS = panel.minSize, maxS = panel.maxSize
        var f = startFrame

        if activeEdge.contains(.right) {
            f.size.width = clamp(mouse.x - startFrame.minX, minS.width, maxS.width)
        }
        if activeEdge.contains(.left) {
            let right = startFrame.maxX
            let width = clamp(right - mouse.x, minS.width, maxS.width)
            f.origin.x = right - width
            f.size.width = width
        }
        if activeEdge.contains(.top) {
            let bottom = startFrame.minY
            f.size.height = clamp(mouse.y - bottom, minS.height, maxS.height)
            f.origin.y = bottom
        }
        if activeEdge.contains(.bottom) {
            let top = startFrame.maxY
            let height = clamp(top - mouse.y, minS.height, maxS.height)
            f.origin.y = top - height
            f.size.height = height
        }

        panel.setFrame(f, display: true)
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }
}
