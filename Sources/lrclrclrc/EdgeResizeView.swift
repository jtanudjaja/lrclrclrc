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
    private var cursorPushed = false

    // MARK: - Resize cursors

    // macOS 15 has public frame-resize cursors (the modern in/out arrows every
    // resizable window shows). On 13–14 the straight edges fall back to the
    // classic system double arrows and the diagonals are drawn to match.
    private static let horizontal: NSCursor = {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .left, directions: [.inward, .outward])
        }
        return .resizeLeftRight
    }()

    private static let vertical: NSCursor = {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .top, directions: [.inward, .outward])
        }
        return .resizeUpDown
    }()

    private static let diagonalNWSE: NSCursor = {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .topLeft, directions: [.inward, .outward])
        }
        return drawnDiagonal(nwse: true)
    }()

    private static let diagonalNESW: NSCursor = {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .topRight, directions: [.inward, .outward])
        }
        return drawnDiagonal(nwse: false)
    }()

    /// A double-headed diagonal arrow in the system style (white stroke over a
    /// dark outline so it reads on any background).
    private static func drawnDiagonal(nwse: Bool) -> NSCursor {
        let side: CGFloat = 24
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let a = nwse ? NSPoint(x: 6, y: 18) : NSPoint(x: 6, y: 6)
            let b = nwse ? NSPoint(x: 18, y: 6) : NSPoint(x: 18, y: 18)
            let path = NSBezierPath()
            path.move(to: a)
            path.line(to: b)
            path.append(arrowHead(at: a, from: b))
            path.append(arrowHead(at: b, from: a))
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.lineWidth = 4.5
            NSColor.black.withAlphaComponent(0.85).setStroke()
            path.stroke()
            path.lineWidth = 2
            NSColor.white.setStroke()
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
    }

    private static func arrowHead(at tip: NSPoint, from tail: NSPoint) -> NSBezierPath {
        let dx = tip.x - tail.x, dy = tip.y - tail.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len, uy = dy / len   // toward the tip
        let px = -uy, py = ux              // perpendicular
        let back: CGFloat = 5, spread: CGFloat = 3.5
        let base = NSPoint(x: tip.x - ux * back, y: tip.y - uy * back)
        let head = NSBezierPath()
        head.move(to: NSPoint(x: base.x + px * spread, y: base.y + py * spread))
        head.line(to: tip)
        head.line(to: NSPoint(x: base.x - px * spread, y: base.y - py * spread))
        return head
    }

    /// The cursor matching a grabbed edge/corner (used to hold it during drags).
    private func cursor(for e: Edge) -> NSCursor {
        let horizontalHit = e.contains(.left) || e.contains(.right)
        let verticalHit = e.contains(.top) || e.contains(.bottom)
        switch (horizontalHit, verticalHit) {
        case (true, true):
            let nwse = (e.contains(.left) && e.contains(.top)) || (e.contains(.right) && e.contains(.bottom))
            return nwse ? Self.diagonalNWSE : Self.diagonalNESW
        case (true, false): return Self.horizontal
        case (false, true): return Self.vertical
        default: return .arrow
        }
    }

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

        // Edges: ↔ / ↕ double arrows.
        addCursorRect(NSRect(x: 0, y: t, width: t, height: h - 2 * t), cursor: Self.horizontal)
        addCursorRect(NSRect(x: w - t, y: t, width: t, height: h - 2 * t), cursor: Self.horizontal)
        addCursorRect(NSRect(x: t, y: 0, width: w - 2 * t, height: t), cursor: Self.vertical)
        addCursorRect(NSRect(x: t, y: h - t, width: w - 2 * t, height: t), cursor: Self.vertical)

        // Corners: true diagonal double arrows, like any resizable macOS
        // window. (AppKit y is bottom-up: top-left rect is at y = h − t.)
        addCursorRect(NSRect(x: 0, y: h - t, width: t, height: t), cursor: Self.diagonalNWSE)     // top-left ⤡
        addCursorRect(NSRect(x: w - t, y: 0, width: t, height: t), cursor: Self.diagonalNWSE)     // bottom-right ⤡
        addCursorRect(NSRect(x: w - t, y: h - t, width: t, height: t), cursor: Self.diagonalNESW) // top-right ⤢
        addCursorRect(NSRect(x: 0, y: 0, width: t, height: t), cursor: Self.diagonalNESW)         // bottom-left ⤢
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        activeEdge = edge(at: local)
        startFrame = panel?.frame ?? .zero
        // Hold the resize cursor for the whole drag so it doesn't flicker back
        // to an arrow when the mouse outruns the cursor rects.
        if !activeEdge.isEmpty {
            cursor(for: activeEdge).push()
            cursorPushed = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        let wasResizing = !activeEdge.isEmpty
        activeEdge = []
        // Deferred floor: the width just changed, so the live minimum may have
        // risen — recompute and grow now that the drag has ended.
        if wasResizing { (panel as? OverlayPanel)?.settleAfterResize() }
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
