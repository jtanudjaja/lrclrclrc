import AppKit
import Combine

/// The window the slab lives in: a fixed, transparent, click-through stage
/// pinned to the top of the notched display, above the menu bar.
///
/// Three choices worth naming.
///
/// *Fixed.* The slab's width is the lyric's width, so it changes every line;
/// resizing a window at that rate hands the animation to the window server,
/// which can't ease it. A stage sized once for the widest slab the geometry
/// allows lets SwiftUI animate inside a window that never moves — every state
/// change is a spring, not a resize.
///
/// *Click-through, always.* The stage covers the middle of the menu bar, which
/// is nearly always empty — but "nearly always" is no place for a window that
/// swallows clicks, and `ignoresMouseEvents` is what keeps the bar, the status
/// items and whatever is underneath exactly as reachable as before. Nothing is
/// lost: every control the slab could raise on hover is already one click away
/// on the menu-bar icon.
///
/// *Level `.statusBar`* (25) is one above the menu bar's own (`.mainMenu`, 24)
/// and far below an open menu's (`.popUpMenu`, 101) — so the slab covers the
/// bar, and any menu the user pulls down covers the slab.
final class NotchPanel: NSPanel {
    private var dockCancellable: AnyCancellable?

    init(contentView: NSView, dock: NotchDock) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the slab casts its own, inside the view
        ignoresMouseEvents = true
        isFloatingPanel = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        self.contentView = contentView
        dockCancellable = dock.$geometry.sink { [weak self] in self?.dock(to: $0) }
    }

    /// Centred on the housing, with the window's top edge at the screen's own:
    /// the slab reaches up into the bezel, so there's no inset to respect.
    private func dock(to geometry: NotchGeometry?) {
        // No screen to dock to (a closed lid mid-change). Leaving the frame
        // alone is the quiet answer — the view draws nothing without geometry,
        // and ordering the window out here would fight whoever owns its
        // visibility (the display mode).
        guard let geometry else { return }
        let size = NSSize(width: geometry.maxSlabWidth,
                          height: NotchMetrics.windowHeight(for: geometry))
        let screen = geometry.screen.frame
        setFrame(
            NSRect(x: (geometry.housingCenterX - size.width / 2).rounded(),
                   y: screen.maxY - size.height,
                   width: size.width, height: size.height),
            display: true
        )
    }

    // Scenery takes no events and never holds focus.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
