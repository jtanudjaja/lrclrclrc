import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: OverlayPanel?
    private let controller = LyricsController()

    private var clickThrough = false
    private var clickThroughItem: NSMenuItem?

    private var showMenuBarLyrics = false
    private var menuBarLyricsItem: NSMenuItem?
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

        panel.orderFrontRegardless()

        setupStatusItem()
        controller.start()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = statusIcon

        let menu = NSMenu()
        menu.addItem(makeItem("Show / Hide Overlay", #selector(toggleOverlay), "h"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Larger", #selector(enlarge), "+"))
        menu.addItem(makeItem("Smaller", #selector(shrink), "-"))

        let ct = makeItem("Click-Through (ignore mouse)", #selector(toggleClickThrough), "t")
        clickThroughItem = ct
        menu.addItem(ct)

        let mb = makeItem("Show Lyrics in Menu Bar", #selector(toggleMenuBarLyrics), "m")
        menuBarLyricsItem = mb
        menu.addItem(mb)

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

    // MARK: - Overlay controls

    @objc private func toggleOverlay() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func toggleClickThrough() {
        clickThrough.toggle()
        panel?.ignoresMouseEvents = clickThrough
        clickThroughItem?.state = clickThrough ? .on : .off
    }

    @objc private func enlarge() { panel?.scaleBy(1.15) }
    @objc private func shrink() { panel?.scaleBy(0.87) }

    // MARK: - Menu-bar lyrics

    @objc private func toggleMenuBarLyrics() {
        showMenuBarLyrics.toggle()
        menuBarLyricsItem?.state = showMenuBarLyrics ? .on : .off

        if showMenuBarLyrics {
            lyricsCancellable = controller.$currentLine
                .receive(on: RunLoop.main)
                .sink { [weak self] line in self?.updateMenuBarText(line) }
            updateMenuBarText(controller.currentLine)
        } else {
            lyricsCancellable?.cancel()
            lyricsCancellable = nil
            statusItem?.button?.title = ""
            statusItem?.button?.image = statusIcon
        }
    }

    private func updateMenuBarText(_ line: String) {
        guard showMenuBarLyrics, let button = statusItem?.button else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            button.image = statusIcon
            button.title = ""
        } else {
            button.image = nil
            let maxLength = 45
            button.title = trimmed.count > maxLength
                ? String(trimmed.prefix(maxLength - 1)) + "…"
                : trimmed
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
