import AppKit

// AppKit lifecycle (rather than the SwiftUI `App` lifecycle) so we can own a
// borderless floating NSPanel and a menu-bar status item directly.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar agent: no Dock icon
app.run()
