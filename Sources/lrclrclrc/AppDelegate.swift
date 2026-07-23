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
    private var fontScaleCancellable: AnyCancellable?
    private var linesCancellable: AnyCancellable?

    private let sourceSubmenu = NSMenu()
    private var offsetItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?

    private let statusIcon = NSImage(
        systemSymbolName: "music.note.list",
        accessibilityDescription: "lrclrclrc"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingView(rootView: OverlayView(controller: controller, appearance: appearance))
        hosting.autoresizingMask = [.width, .height]

        // Container for the SwiftUI card.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 150))
        hosting.frame = container.bounds
        container.addSubview(hosting)

        let panel = OverlayPanel(contentView: container)
        self.panel = panel
        // The card is chrome, not a window the user manages — keep it out of
        // the Window menu that the real windows live in.
        panel.isExcludedFromWindowsMenu = true
        // Resizing is fully native: an ordinary activatable titled window
        // gets the system's own edge handling and resize cursors (including
        // the slightly-outside grab area), exactly like any other app's
        // window. No custom edge view, no custom cursor display.

        setupMainMenu()
        setupStatusItem()
        controller.start()
        restoreState()

        // Keep the menu's offset readout in sync (offset changes per track and
        // from the overlay's own timing controls).
        offsetCancellable = controller.$offset
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateOffsetTitle() }

        // The live floor (spec Part 3): recompute whenever text size or the
        // track's lyrics change, and after an edge drag ends (deferred growth).
        // Debounced: the slider fires continuously and each floor recompute
        // measures every line of the track — visuals stay live regardless,
        // only the min-size math waits for the drag to settle.
        fontScaleCancellable = appearance.$fontScale
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshFloor(growNow: true) }
        linesCancellable = controller.$allLines
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshFloor(growNow: true) }
        // Deferred floor settle at the end of a native live resize.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.refreshFloor(growNow: true) }
        refreshFloor(growNow: true)

        // The stage's "no lyrics found" state offers a Find Lyrics… shortcut.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("lrclrclrc.openFindLyrics"), object: nil, queue: .main
        ) { [weak self] _ in self?.openFindLyrics() }

        if !Settings.hasOnboarded { showOnboarding() }
    }

    /// Recompute the live minimum/maximum window size from the current text
    /// size, width, lyrics, and click-through state (spec Part 3, rule 4).
    private func refreshFloor(growNow: Bool) {
        guard let panel else { return }
        let minSize = OverlayMetrics.minContentSize(
            fontScale: appearance.fontScale,
            cardWidth: panel.frame.width,
            lines: controller.allLines,
            clickThrough: clickThrough,
            screenHeight: (panel.screen ?? NSScreen.main)?.visibleFrame.height
        )
        panel.updateFloor(minSize, growNow: growNow)
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

        rebuildSourceMenu()
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

        // The standard Window menu is what makes an ordinary window behave
        // ordinarily: ⌘W to close, ⌘M to minimize, zoom, and a live list of
        // open windows. (Close sits here rather than in a File menu — this app
        // has no documents, so it has no File menu.)
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

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

        // Which enabled player to follow (radio). Enabling players is a
        // Preferences job; this menu only ever offers what's already enabled.
        rebuildSourceMenu()
        menu.addItem(submenu("Follow", sourceSubmenu))

        menu.addItem(makeItem("Full Lyrics…", #selector(openFullLyrics), "f"))
        menu.addItem(makeItem("Find Lyrics…", #selector(openFindLyrics), "l"))
        menu.addItem(makeItem("Preferences…", #selector(openPreferences), ""))
        menu.addItem(.separator())

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

    /// Rebuilt rather than restated: enabling a player in Preferences changes
    /// what this menu is allowed to offer, not just which row is ticked.
    private func rebuildSourceMenu() {
        sourceSubmenu.removeAllItems()

        // Automatic is the default and the only entry that means anything with
        // two players open, so it leads.
        let auto = NSMenuItem(title: "Automatic", action: #selector(selectSource(_:)), keyEquivalent: "")
        auto.target = self
        auto.state = controller.followedSource == nil ? .on : .off
        auto.toolTip = "Follow whichever enabled player is playing."
        sourceSubmenu.addItem(auto)

        let enabled = controller.enabledSources
        if !enabled.isEmpty { sourceSubmenu.addItem(.separator()) }
        for kind in enabled {
            let item = NSMenuItem(title: kind.displayName,
                                  action: #selector(selectSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.state = controller.followedSource == kind ? .on : .off
            sourceSubmenu.addItem(item)
        }

        if enabled.isEmpty {
            let hint = NSMenuItem(title: "No music app enabled", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            sourceSubmenu.addItem(.separator())
            sourceSubmenu.addItem(hint)
        }
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
        // Click-through carries the whole passive overlay profile (top level,
        // non-activating, mouse-transparent), not just ignoresMouseEvents.
        panel?.applyProfile(passive: on)
        clickThroughItem?.state = on ? .on : .off
        Settings.clickThrough = on
        // The overlay drops its footer reserve when controls are unreachable,
        // and the floor shrinks/grows to match.
        appearance.clickThroughActive = on
        refreshFloor(growNow: true)
    }

    // MARK: - Sources

    /// No represented object = the Automatic row.
    @objc private func selectSource(_ sender: NSMenuItem) {
        let kind = (sender.representedObject as? String).flatMap(PlayerSourceKind.init(rawValue:))
        controller.followSource(kind)
        rebuildSourceMenu()
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
        let view = PreferencesView(appearance: appearance, controller: controller, actions: self)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "lrclrclrc Preferences"
        // An ordinary window in every respect the window server cares about:
        // all three traffic lights, freely resizable, zoomable, minimizable to
        // the Dock, and listed in the Window menu.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        // There is only ever one Preferences window — nothing to tab with.
        window.tabbingMode = .disallowed
        window.setContentSize(NSSize(width: 420, height: 520))
        window.contentMinSize = NSSize(width: 380, height: 320)
        // AppKit persists the frame under this name, so size and position
        // survive both reopening and relaunches; centre only the first time.
        // Restore first, *then* register the name: assigning an autosave name
        // writes the current frame under it, which would clobber the saved one.
        let autosave = "lrclrclrc.preferences"
        if !window.setFrameUsingName(autosave) { window.center() }
        _ = window.setFrameAutosaveName(autosave)
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
    var currentDisplayMode: DisplayMode { displayMode }
    var isClickThroughOn: Bool { clickThrough }
    var isLaunchAtLoginOn: Bool { SMAppService.mainApp.status == .enabled }

    func chooseSourceEnabled(_ kind: PlayerSourceKind, enabled: Bool) {
        controller.setSourceEnabled(enabled, for: kind)
        rebuildSourceMenu()
    }

    func chooseFollowedSource(_ kind: PlayerSourceKind?) {
        controller.followSource(kind)
        rebuildSourceMenu()
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

    /// Every setting back to its default. Per-song data (sync offsets, manual
    /// lyrics, cached lyrics) is deliberately kept — that's content, not
    /// configuration.
    func resetToDefaults() {
        appearance.fontScale = 1.0
        appearance.backgroundOpacity = 0.08
        appearance.textColor = .white
        appearance.alwaysShowControls = false
        setClickThrough(false)
        if isLaunchAtLoginOn { chooseLaunchAtLogin(false) }
        controller.resetSources()
        rebuildSourceMenu()
        setDisplayMode(.overlay)
        panel?.resetFrame()
        refreshFloor(growNow: true)
    }
}
