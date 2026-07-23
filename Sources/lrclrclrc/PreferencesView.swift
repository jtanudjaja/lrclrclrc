import SwiftUI

/// Cross-cutting settings the Preferences window drives, implemented by the
/// AppDelegate (which owns the panel, status item, and login-item state).
protocol PreferencesActions: AnyObject {
    var currentDisplayMode: DisplayMode { get }
    var isClickThroughOn: Bool { get }
    var isLaunchAtLoginOn: Bool { get }
    func chooseSourceEnabled(_ kind: PlayerSourceKind, enabled: Bool)
    func chooseFollowedSource(_ kind: PlayerSourceKind?)
    func chooseDisplayMode(_ mode: DisplayMode)
    func chooseClickThrough(_ on: Bool)
    func chooseLaunchAtLogin(_ on: Bool)
    /// Restore every setting to its default (keeps per-song data: offsets,
    /// manual lyrics, caches).
    func resetToDefaults()
}

struct PreferencesView: View {
    @ObservedObject var appearance: Appearance
    /// Observed for `sourceStates`: ticking a player we couldn't find can turn
    /// it into one we can, so the list has to redraw from the controller rather
    /// than from a local copy.
    @ObservedObject var controller: LyricsController
    let actions: PreferencesActions

    @State private var display: DisplayMode
    @State private var clickThrough: Bool
    @State private var launchAtLogin: Bool
    @State private var confirmingReset = false

    init(appearance: Appearance, controller: LyricsController, actions: PreferencesActions) {
        self.appearance = appearance
        self.controller = controller
        self.actions = actions
        _display = State(initialValue: actions.currentDisplayMode)
        _clickThrough = State(initialValue: actions.isClickThroughOn)
        _launchAtLogin = State(initialValue: actions.isLaunchAtLoginOn)
    }

    var body: some View {
        Form {
            // Which of the enabled apps to follow comes first: it's the choice
            // people actually revisit. What's *enabled* is setup, so it sits
            // underneath and feeds this picker its options.
            Section("Source") {
                Picker("Follow", selection: Binding(
                    get: { controller.followedSource },
                    set: { actions.chooseFollowedSource($0) }
                )) {
                    Text("Automatic").tag(PlayerSourceKind?.none)
                    ForEach(controller.enabledSources, id: \.self) { kind in
                        Text(kind.displayName).tag(PlayerSourceKind?.some(kind))
                    }
                }
                .disabled(controller.enabledSources.isEmpty)
            }

            Section {
                ForEach(controller.sourceStates) { state in
                    sourceToggle(state)
                }
            } header: {
                Text("Music Apps")
            } footer: {
                Text("Apps installed on this Mac are enabled automatically. Turn on one that wasn't found and lrclrclrc will ask where it is.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Lyrics") {
                Picker("Show in", selection: $display) {
                    Text("Overlay").tag(DisplayMode.overlay)
                    Text("Menu Bar").tag(DisplayMode.menuBar)
                    Text("Hidden").tag(DisplayMode.hidden)
                }
                .onChange(of: display) { actions.chooseDisplayMode($0) }
            }

            Section("Appearance") {
                VStack(alignment: .leading) {
                    Text("Text size")
                    Slider(value: $appearance.fontScale, in: 0.7...2.0)
                }
                VStack(alignment: .leading) {
                    Text("Background opacity (when not hovered)")
                    Slider(value: $appearance.backgroundOpacity, in: 0.0...0.5)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("Text color")
                    textColorRow
                }
                Toggle("Always show controls", isOn: $appearance.alwaysShowControls)
            }

            Section("Behavior") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { actions.chooseLaunchAtLogin($0) }
                Toggle("Click-through (ignore mouse)", isOn: $clickThrough)
                    .onChange(of: clickThrough) { actions.chooseClickThrough($0) }
            }

            Section {
                Button("Reset to Defaults…", role: .destructive) {
                    confirmingReset = true
                }
                .confirmationDialog(
                    "Reset all settings to their defaults?",
                    isPresented: $confirmingReset
                ) {
                    Button("Reset", role: .destructive) {
                        actions.resetToDefaults()
                        // Re-read the states this window mirrors locally.
                        display = actions.currentDisplayMode
                        clickThrough = actions.isClickThroughOn
                        launchAtLogin = actions.isLaunchAtLoginOn
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Appearance, behavior, source, display mode, and the overlay's position and size return to their defaults. Per-song data — sync offsets and manual lyrics — is kept.")
                }
            }
        }
        .formStyle(.grouped)
        // The window owns its size now (it's resizable and remembers its
        // frame) — the view only states what it needs to stay usable.
        .frame(minWidth: 380, idealWidth: 420, maxWidth: .infinity,
               minHeight: 320, idealHeight: 520, maxHeight: .infinity)
    }

    /// A player's checkbox. The row isn't greyed out when the app is missing —
    /// that checkbox *is* the way to go find it — so it says so instead.
    private func sourceToggle(_ state: SourceState) -> some View {
        Toggle(isOn: Binding(
            get: { state.isEnabled },
            set: { actions.chooseSourceEnabled(state.kind, enabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.kind.displayName)
                if !state.isInstalled {
                    Text("Not found on this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// One row: the light presets, then Ink past the divider, then the wheel.
    /// Which side to use isn't taste — light text is unreadable over a white
    /// page and Ink over album art — so the divider groups them and the
    /// tooltips say which is for what. A wheel colour matches no swatch, so
    /// nothing reads as selected.
    private var textColorRow: some View {
        let current = appearance.textColor.hexString
        return HStack(spacing: 8) {
            ForEach(TextColorPreset.light) { preset in
                swatch(preset, selected: preset.hex == current,
                       hint: "for dark wallpaper, art, or video")
            }
            Divider().frame(height: 16)
            ForEach(TextColorPreset.dark) { preset in
                swatch(preset, selected: preset.hex == current,
                       hint: "for a bright desktop or document")
            }
            Divider().frame(height: 16)
            ColorPicker("Custom text color", selection: $appearance.textColor, supportsOpacity: false)
                .labelsHidden()
                .help("Custom…")
        }
    }

    private func swatch(_ preset: TextColorPreset, selected: Bool, hint: String) -> some View {
        Circle()
            .fill(preset.color)
            .frame(width: 18, height: 18)
            // Own outline so a near-white swatch still reads as a disc on the
            // form's light background.
            .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 0.5))
            .overlay(
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(-3)
                    .opacity(selected ? 1 : 0)
            )
            .contentShape(Circle())
            .onTapGesture { appearance.textColor = preset.color }
            .help(preset.name)
            .accessibilityLabel(preset.name)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
