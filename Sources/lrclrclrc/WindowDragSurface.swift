import SwiftUI
import AppKit

/// Explicit window-drag handle: an AppKit view that starts a native window
/// drag on mouse-down. Placed behind the overlay's header, which acts as the
/// card's title bar. (Whole-background window dragging is off so the lyric
/// stage's scrub gesture actually receives its drags.)
final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct WindowDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView { WindowDragNSView() }
    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}
