import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: OverlayPanel?
    private let controller = LyricsController()
    private var clickThrough = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingView(rootView: OverlayView(controller: controller))
        hosting.autoresizingMask = [.width, .height]

        let panel = OverlayPanel(contentView: hosting)
        panel.orderFrontRegardless()
        self.panel = panel

        setupStatusItem()
        controller.start()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "music.note.list",
            accessibilityDescription: "lrclrclrc"
        )

        let menu = NSMenu()
        menu.addItem(makeItem("Show / Hide Overlay", #selector(toggleOverlay), "h"))
        menu.addItem(makeItem("Click-Through (ignore mouse)", #selector(toggleClickThrough), "t"))
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
        statusItem?.menu?.item(at: 1)?.state = clickThrough ? .on : .off
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
