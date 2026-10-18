import AppKit

/// Hover, for a window that takes no mouse events.
///
/// The slab covers the middle of the menu bar, so it can never be the window
/// the pointer lands on: `ignoresMouseEvents` is the whole reason the bar, the
/// status items and everything underneath stay as clickable as before. But a
/// window that ignores mouse events also gets no tracking areas and no
/// `onHover` — so the pointer is watched from outside instead, against the
/// rect the slab is actually drawn in. The slab opens on hover without ever
/// taking a click.
///
/// Mouse monitors need no permission (unlike keyboard ones, which require
/// Input Monitoring), so there is nothing here for the user to approve.
final class NotchHoverMonitor: ObservableObject {
    @Published private(set) var isInside = false

    /// The screen rect the pointer has to be inside, in screen coordinates.
    /// The view keeps it current as the slab animates, because the slab's
    /// drawn size is the only honest hover target — and `.zero` while it's
    /// collapsed, which is how a notch with nothing playing stays unhoverable.
    var zone: CGRect = .zero {
        didSet { if zone != oldValue { evaluate() } }
    }

    /// Opening waits for the pointer to settle; closing never waits. The slab
    /// sits over the middle of the menu bar, which is somewhere the pointer
    /// crosses on its way to the status items — without the dwell, every one
    /// of those trips would pop the stage open behind it.
    private static let dwell: TimeInterval = 0.12

    /// A pointer can also leave without moving — warped by another app, or
    /// carried off by a display change. Cheap insurance against a stage stuck
    /// open, and it only runs while one is.
    private static let guardInterval: TimeInterval = 0.4

    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var guardTimer: Timer?

    /// Runs only while the slab is on screen: the notch mode is one of four,
    /// and the other three have no reason to watch the pointer at all.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard monitors.isEmpty else { return }
            // Global catches the pointer while it's over another app, which is
            // every case that matters, since the slab itself never receives
            // the event. Local covers the one exception: this app's own
            // windows (Preferences) passing under the notch.
            let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { [weak self] _ in
                self?.evaluate()
            }) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { [weak self] event in
                self?.evaluate()
                return event
            }) {
                monitors.append(local)
            }
            evaluate()
        } else {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
            close()
        }
    }

    private func evaluate() {
        guard !zone.isEmpty, zone.contains(NSEvent.mouseLocation) else { close(); return }
        guard !isInside, openWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.openWork = nil
            // Re-checked at the end of the dwell: the pointer may have been
            // passing through, and the zone may have moved out from under it.
            guard !self.zone.isEmpty, self.zone.contains(NSEvent.mouseLocation) else { return }
            self.isInside = true
            self.guardTimer?.invalidate()
            self.guardTimer = Timer.scheduledTimer(
                withTimeInterval: Self.guardInterval, repeats: true
            ) { [weak self] _ in self?.evaluate() }
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: work)
    }

    private func close() {
        openWork?.cancel()
        openWork = nil
        guardTimer?.invalidate()
        guardTimer = nil
        if isInside { isInside = false }
    }
}
