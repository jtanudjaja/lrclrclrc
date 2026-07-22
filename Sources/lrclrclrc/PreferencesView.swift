import SwiftUI

/// Cross-cutting settings the Preferences window drives, implemented by the
/// AppDelegate (which owns the panel, status item, and login-item state).
protocol PreferencesActions: AnyObject {
    var currentSource: PlayerSourceKind { get }
    var currentDisplayMode: DisplayMode { get }
    var isClickThroughOn: Bool { get }
    var isLaunchAtLoginOn: Bool { get }
    func chooseSource(_ kind: PlayerSourceKind)
    func chooseDisplayMode(_ mode: DisplayMode)
    func chooseClickThrough(_ on: Bool)
    func chooseLaunchAtLogin(_ on: Bool)
    /// Restore every setting to its default (keeps per-song data: offsets,
    /// manual lyrics, caches).
    func resetToDefaults()
}

struct PreferencesView: View {
    @ObservedObject var appearance: Appearance
    let actions: PreferencesActions

    @State private var source: PlayerSourceKind
    @State private var display: DisplayMode
    @State private var clickThrough: Bool
    @State private var launchAtLogin: Bool
    @State private var confirmingReset = false

    init(appearance: Appearance, actions: PreferencesActions) {
        self.appearance = appearance
        self.actions = actions
        _source = State(initialValue: actions.currentSource)
        _display = State(initialValue: actions.currentDisplayMode)
        _clickThrough = State(initialValue: actions.isClickThroughOn)
        _launchAtLogin = State(initialValue: actions.isLaunchAtLoginOn)
    }

    var body: some View {
        Form {
            Section("Lyrics") {
                Picker("Follow", selection: $source) {
                    Text("Auto").tag(PlayerSourceKind.auto)
                    Text("Apple Music").tag(PlayerSourceKind.appleMusic)
                    Text("Spotify").tag(PlayerSourceKind.spotify)
                }
                .onChange(of: source) { actions.chooseSource($0) }

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
                    Text("Background opacity")
                    Slider(value: $appearance.backgroundOpacity, in: 0.0...0.5)
                }
                Picker("Accent", selection: $appearance.accent) {
                    ForEach(AccentChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
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
                        source = actions.currentSource
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
        .frame(width: 420, height: 500)
    }
}
