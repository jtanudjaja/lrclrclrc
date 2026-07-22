import AppKit
import SwiftUI
import Combine

/// Where lyrics are shown. The overlay and the menu bar are mutually exclusive,
/// so this is one setting rather than two toggles.
enum DisplayMode: String {
    case overlay
    case menuBar
    case hidden
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: OverlayPanel?
    private let controller = LyricsController()

    private var clickThrough = false
    private var clickThroughItem: NSMenuItem?

    private var findLyricsWindow: NSWindow?

    private var displayMode: DisplayMode = .overlay
    private var modeItems: [DisplayMode: NSMenuItem] = [:]
    private var lyricsCancellable: AnyCancellable?

    private let statusIcon = NSImage(
        systemSymbolName: "music.note.list",
        accessibilityDescription: "lrclrclrc"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingView(rootView: OverlayView(controller: controller))
        hosting.autoresizingMask = [.width, .height]

        // Container: SwiftUI card at the bottom, resize overlay on top.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 150))
        hosting.frame = container.bounds
        container.addSubview(hosting)

        let panel = OverlayPanel(contentView: container)
        self.panel = panel

        let resizer = EdgeResizeView(window: panel)
        resizer.frame = container.bounds
        resizer.autoresizingMask = [.width, .height]
        container.addSubview(resizer, positioned: .above, relativeTo: hosting)

        setupStatusItem()
        controller.start()
        restoreState()
    }

    /// Reapply persisted state on launch (the panel restores its own frame).
    private func restoreState() {
        if Settings.clickThrough { setClickThrough(true) }
        let mode = DisplayMode(rawValue: Settings.displayMode) ?? .overlay
        setDisplayMode(mode)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = statusIcon

        let menu = NSMenu()

        // Merged display-mode picker (radio): Overlay / Menu Bar / Hidden.
        let displaySubmenu = NSMenu()
        displaySubmenu.addItem(modeItem("Overlay", .overlay))
        displaySubmenu.addItem(modeItem("Menu Bar", .menuBar))
        displaySubmenu.addItem(modeItem("Hidden", .hidden))
        let displayParent = NSMenuItem(title: "Show Lyrics In", action: nil, keyEquivalent: "")
        displayParent.submenu = displaySubmenu
        menu.addItem(displayParent)

        menu.addItem(makeItem("Find Lyrics…", #selector(openFindLyrics), "l"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Larger", #selector(enlarge), "+"))
        menu.addItem(makeItem("Smaller", #selector(shrink), "-"))

        let ct = makeItem("Click-Through (ignore mouse)", #selector(toggleClickThrough), "t")
        clickThroughItem = ct
        menu.addItem(ct)

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit lrclrclrc", #selector(quit), "q"))
        item.menu = menu

        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func modeItem(_ title: String, _ mode: DisplayMode) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mode.rawValue
        modeItems[mode] = item
        return item
    }

    // MARK: - Display mode

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: raw) else { return }
        setDisplayMode(mode)
    }

    private func setDisplayMode(_ mode: DisplayMode) {
        displayMode = mode
        Settings.displayMode = mode.rawValue
        for (m, item) in modeItems { item.state = (m == mode) ? .on : .off }

        switch mode {
        case .overlay:
            stopMenuBarLyrics()
            panel?.orderFrontRegardless()
        case .menuBar:
            panel?.orderOut(nil)
            startMenuBarLyrics()
        case .hidden:
            stopMenuBarLyrics()
            panel?.orderOut(nil)
        }
    }

    // MARK: - Overlay controls

    @objc private func toggleClickThrough() {
        setClickThrough(!clickThrough)
    }

    private func setClickThrough(_ on: Bool) {
        clickThrough = on
        panel?.ignoresMouseEvents = on
        clickThroughItem?.state = on ? .on : .off
        Settings.clickThrough = on
    }

    @objc private func enlarge() { panel?.scaleBy(1.15) }
    @objc private func shrink() { panel?.scaleBy(0.87) }

    @objc private func openFindLyrics() {
        if let window = findLyricsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: FindLyricsView(controller: controller))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Find Lyrics"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        findLyricsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu-bar lyrics

    private func startMenuBarLyrics() {
        lyricsCancellable = controller.$currentLine
            .receive(on: RunLoop.main)
            .sink { [weak self] line in self?.updateMenuBarText(line) }
        updateMenuBarText(controller.currentLine)
    }

    private func stopMenuBarLyrics() {
        lyricsCancellable?.cancel()
        lyricsCancellable = nil
        statusItem?.button?.attributedTitle = NSAttributedString(string: "")
        statusItem?.button?.image = statusIcon
    }

    private func updateMenuBarText(_ line: String) {
        guard displayMode == .menuBar, let button = statusItem?.button else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            button.image = statusIcon
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            // Hide the icon to give the text the whole width; a smaller font
            // fits more before macOS truncates it.
            button.image = nil
            let maxLength = 72
            let shown = trimmed.count > maxLength
                ? String(trimmed.prefix(maxLength - 1)) + "…"
                : trimmed
            button.attributedTitle = NSAttributedString(
                string: shown,
                attributes: [.font: NSFont.systemFont(ofSize: 12)]
            )
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
