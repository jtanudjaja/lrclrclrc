import AppKit
import SwiftUI
import Combine
import ServiceManagement

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
    private var fullLyricsWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var utilityWindows: [NSWindow] = []
    private let appearance = Appearance()

    private var displayMode: DisplayMode = .overlay
    private var modeItems: [DisplayMode: NSMenuItem] = [:]
    private var lyricsCancellable: AnyCancellable?
    private var offsetCancellable: AnyCancellable?

    private var sourceItems: [PlayerSourceKind: NSMenuItem] = [:]
    private var offsetItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?

    private let statusIcon = NSImage(
        systemSymbolName: "music.note.list",
        accessibilityDescription: "lrclrclrc"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingView(rootView: OverlayView(controller: controller, appearance: appearance))
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

        setupMainMenu()
        setupStatusItem()
        controller.start()
        restoreState()

        // Keep the menu's offset readout in sync (offset changes per track and
        // from the overlay's own timing controls).
        offsetCancellable = controller.$offset
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateOffsetTitle() }

        if !Settings.hasOnboarded { showOnboarding() }
    }

    private func showOnboarding() {
        Settings.hasOnboarded = true // show exactly once
        let view = OnboardingView(controller: controller) { [weak self] in
            self?.onboardingWindow?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        registerUtilityWindow(window)
        present(window)
    }

    /// Reapply persisted state on launch (the panel restores its own frame).
    private func restoreState() {
        if Settings.clickThrough { setClickThrough(true) }
        let mode = DisplayMode(rawValue: Settings.displayMode) ?? .overlay
        setDisplayMode(mode)

        let kind = controller.currentSource
        for (k, item) in sourceItems { item.state = (k == kind) ? .on : .off }
        updateOffsetTitle()
    }

    /// An accessory app has no application menu, so the standard editing key
    /// equivalents (⌘X/C/V/A/Z) aren't routed to the first responder — which
    /// breaks pasting into the Find Lyrics text box. A minimal main menu with
    /// an Edit submenu restores them (the bar itself stays hidden).
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(prefs)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit lrclrclrc",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = statusIcon

        let menu = NSMenu()

        // Where lyrics show (radio): Overlay / Menu Bar / Hidden.
        let displaySubmenu = NSMenu()
        displaySubmenu.addItem(modeItem("Overlay", .overlay))
        displaySubmenu.addItem(modeItem("Menu Bar", .menuBar))
        displaySubmenu.addItem(modeItem("Hidden", .hidden))
        menu.addItem(submenu("Show Lyrics In", displaySubmenu))

        // Which player to follow (radio): Auto / Apple Music / Spotify.
        let sourceSubmenu = NSMenu()
        sourceSubmenu.addItem(sourceItem("Auto", .auto))
        sourceSubmenu.addItem(sourceItem("Apple Music", .appleMusic))
        sourceSubmenu.addItem(sourceItem("Spotify", .spotify))
        menu.addItem(submenu("Source", sourceSubmenu))

        menu.addItem(makeItem("Full Lyrics…", #selector(openFullLyrics), "f"))
        menu.addItem(makeItem("Find Lyrics…", #selector(openFindLyrics), "l"))
        menu.addItem(makeItem("Preferences…", #selector(openPreferences), ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Text Larger", #selector(enlarge), "+"))
        menu.addItem(makeItem("Text Smaller", #selector(shrink), "-"))

        // Timing offset (fix lyrics that run early/late).
        let timingSubmenu = NSMenu()
        timingSubmenu.addItem(makeItem("Lyrics Earlier", #selector(lyricsEarlier), ""))
        timingSubmenu.addItem(makeItem("Lyrics Later", #selector(lyricsLater), ""))
        timingSubmenu.addItem(.separator())
        let offset = NSMenuItem(title: offsetTitle(), action: nil, keyEquivalent: "")
        offset.isEnabled = false
        offsetItem = offset
        timingSubmenu.addItem(offset)
        timingSubmenu.addItem(makeItem("Reset Timing", #selector(resetTiming), ""))
        menu.addItem(submenu("Timing", timingSubmenu))

        let ct = makeItem("Click-Through (ignore mouse)", #selector(toggleClickThrough), "t")
        clickThroughItem = ct
        menu.addItem(ct)

        let login = makeItem("Launch at Login", #selector(toggleLaunchAtLogin), "")
        launchAtLoginItem = login
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit lrclrclrc", #selector(quit), "q"))
        item.menu = menu

        statusItem = item
        updateLaunchAtLoginState()
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }

    private func modeItem(_ title: String, _ mode: DisplayMode) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mode.rawValue
        modeItems[mode] = item
        return item
    }

    private func sourceItem(_ title: String, _ kind: PlayerSourceKind) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectSource(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = kind.rawValue
        sourceItems[kind] = item
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
        updateActivationPolicy()
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

    // Text Larger / Smaller drive the same fontScale as the Preferences slider.
    @objc private func enlarge() { appearance.fontScale = min(2.0, appearance.fontScale + 0.1) }
    @objc private func shrink() { appearance.fontScale = max(0.7, appearance.fontScale - 0.1) }

    // MARK: - Source

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = PlayerSourceKind(rawValue: raw) else { return }
        chooseSource(kind)
    }

    // MARK: - Timing

    @objc private func lyricsEarlier() { controller.nudgeOffset(0.25); updateOffsetTitle() }
    @objc private func lyricsLater() { controller.nudgeOffset(-0.25); updateOffsetTitle() }
    @objc private func resetTiming() { controller.resetOffset(); updateOffsetTitle() }

    private func offsetTitle() -> String {
        String(format: "Offset: %+.2f s", controller.offset)
    }

    private func updateOffsetTitle() {
        offsetItem?.title = offsetTitle()
    }

    // MARK: - Launch at login

    @objc private func toggleLaunchAtLogin() {
        chooseLaunchAtLogin(!isLaunchAtLoginOn)
    }

    private func updateLaunchAtLoginState() {
        launchAtLoginItem?.state = isLaunchAtLoginOn ? .on : .off
    }

    @objc private func openFullLyrics() {
        if let window = fullLyricsWindow { present(window); return }
        let window = NSWindow(contentViewController: NSHostingController(rootView: FullLyricsView(controller: controller)))
        window.title = "Lyrics"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 380, height: 520))
        window.center()
        fullLyricsWindow = window
        registerUtilityWindow(window)
        present(window)
    }

    // MARK: - Preferences

    @objc private func openPreferences() {
        if let window = preferencesWindow { present(window); return }
        let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView(appearance: appearance, actions: self)))
        window.title = "lrclrclrc Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        preferencesWindow = window
        registerUtilityWindow(window)
        present(window)
    }

    // MARK: - Window presentation

    /// Utility windows (Preferences, lyrics, onboarding) need the app to be a
    /// regular app while open so they're ⌘Tab-able and focusable; drop back to a
    /// menu-bar accessory once they all close.
    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func registerUtilityWindow(_ window: NSWindow) {
        utilityWindows.append(window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.updateActivationPolicy() }
        }
    }

    /// Regular (Dock icon + ⌘Tab) while the overlay or any window is visible;
    /// menu-bar accessory otherwise.
    private func updateActivationPolicy() {
        let overlayVisible = panel?.isVisible ?? false
        let anyWindow = utilityWindows.contains { $0.isVisible }
        NSApp.setActivationPolicy((overlayVisible || anyWindow) ? .regular : .accessory)
    }

    @objc private func openFindLyrics() {
        if let window = findLyricsWindow { present(window); return }
        let window = NSWindow(contentViewController: NSHostingController(rootView: FindLyricsView(controller: controller)))
        window.title = "Find Lyrics"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        findLyricsWindow = window
        registerUtilityWindow(window)
        present(window)
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

// MARK: - Preferences actions (shared by the menu and the Preferences window)

extension AppDelegate: PreferencesActions {
    var currentSource: PlayerSourceKind { controller.currentSource }
    var currentDisplayMode: DisplayMode { displayMode }
    var isClickThroughOn: Bool { clickThrough }
    var isLaunchAtLoginOn: Bool { SMAppService.mainApp.status == .enabled }

    func chooseSource(_ kind: PlayerSourceKind) {
        controller.setSource(kind)
        for (k, item) in sourceItems { item.state = (k == kind) ? .on : .off }
    }

    func chooseDisplayMode(_ mode: DisplayMode) { setDisplayMode(mode) }

    func chooseClickThrough(_ on: Bool) { setClickThrough(on) }

    func chooseLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("lrclrclrc: launch-at-login failed: \(error)")
        }
        updateLaunchAtLoginState()
    }
}
