import AppKit

/// Resize-cursor display for the overlay. The window's *behavior* is native
/// (titled frame, window-server resizing), but cursor *display* over our
/// full-size content is driven from SwiftUI's onContinuousHover — the one
/// channel proven to win against the hosting view's own cursor management.
/// System frame-resize cursors on macOS 15+; drawn equivalents on 13–14.
enum ResizeCursors {
    static let horizontal: NSCursor = {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .left, directions: [.inward, .outward])
        }
        return .resizeLeftRight
    }()

    static let vertical: NSCursor = {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .top, directions: [.inward, .outward])
        }
        return .resizeUpDown
    }()

    static let diagonalNWSE: NSCursor = {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .topLeft, directions: [.inward, .outward])
        }
        return drawnDiagonal(nwse: true)
    }()

    static let diagonalNESW: NSCursor = {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .topRight, directions: [.inward, .outward])
        }
        return drawnDiagonal(nwse: false)
    }()

    /// Cursor for a point in SwiftUI-local (top-left origin) coordinates, or
    /// nil when the point isn't in the edge band.
    ///
    /// The band is deliberately generous (18pt): the titled frame *steals*
    /// mouse events in the outermost few points (that's how its native drag-
    /// resize works), so hover events stop arriving there — the cursor we set
    /// just before the steal zone is the one that persists through it. A thin
    /// band left almost no reachable pixels, which read as "no cursor at all".
    static func cursor(at p: CGPoint, in size: CGSize, thickness t: CGFloat = 18) -> NSCursor? {
        let left = p.x <= t
        let right = p.x >= size.width - t
        let top = p.y <= t          // visual top (SwiftUI y-down)
        let bottom = p.y >= size.height - t
        switch ((left || right), (top || bottom)) {
        case (true, true):
            let nwse = (left && top) || (right && bottom)
            return nwse ? diagonalNWSE : diagonalNESW
        case (true, false): return horizontal
        case (false, true): return vertical
        default: return nil
        }
    }

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
}
