# lrclrclrc

A floating, always-on-top **lyrics overlay for Apple Music and Spotify on
macOS**, written as a native **SwiftUI / AppKit** menu-bar app. It watches
whatever's playing, pulls time-synced lyrics from [LRCLIB](https://lrclib.net)
(free, no API key), and highlights each line in a translucent panel that stays
above your other apps and follows you across Spaces and full-screen apps.

> **macOS only** (13 Ventura or later). Track detection talks to Apple Music /
> Spotify over AppleScript, so it needs one of them running.

## How it works

Three moving parts, matching the three hard problems of a lyrics overlay:

1. **What's playing** — `MusicWatcher.swift` runs a small AppleScript
   (`NSAppleScript`) to read the current track's title, artist, album,
   duration, and *playback position*, once a second.
2. **The lyrics** — `LyricsService.swift` queries LRCLIB with that track
   signature (exact `/api/get`, falling back to `/api/search`). `LRCParser.swift`
   turns the returned `.lrc` into timestamped lines. Apple's own synced lyrics
   are licensed and locked in the Music app, so — like every DIY overlay — this
   leans on a third-party source, and sync quality varies by song.
3. **The overlay** — `OverlayPanel.swift` is a borderless, transparent `NSPanel`
   pinned with `level = .screenSaver` and
   `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, …]`.
   `LyricsController.swift` extrapolates the 1 Hz position samples at ~10fps so
   the highlighted line advances smoothly.

## Build & run

You need **Xcode Command Line Tools** (`xcode-select --install`) — full Xcode is
optional. Then just:

```bash
make run       # build and launch (build + relaunch each time)
```

Other targets: `make build` (compile only), `make dmg` (package a `.dmg`),
`make debug`, `make clean`. Or call the scripts directly:
`bash scripts/build-app.sh && open lrclrclrc.app`.

Because the app is **built locally**, it carries no download quarantine, so
macOS runs it straight away — no Gatekeeper "unidentified developer" / malware
prompt. (That prompt only appears for apps downloaded from the internet.)

On first launch macOS asks permission to control the **Music** app — click
**OK**, or track detection stays empty (re-enable later under System Settings →
Privacy & Security → Automation).

The app has **no Dock icon** — it lives in the menu bar (the ♫ icon). From there
you can show/hide the overlay, toggle click-through, and quit.

### Controls (menu-bar ♫ icon)

- **Show Lyrics In** — one picker for where lyrics appear: **Overlay** (the
  floating card), **Menu Bar** (the current line in the menu bar, ♫ icon hidden
  for room), or **Hidden**. In Overlay mode, **drag** the card to move it, drag
  its edges/corners to resize (lyrics scale with it), and hover it to reveal
  **⏮ ⏯ ⏭ playback controls** (when the window is big enough).
- **Source** — which player to follow: **Auto** (whichever is playing), **Apple
  Music**, or **Spotify**.
- **Find Lyrics…** — when a song has no lyrics, open lrclib.net to look it up,
  then paste the `.lrc` (timed) or plain text; it's remembered for that track.
- **Larger / Smaller** — step the overlay size.
- **Timing** — nudge lyrics **earlier/later** (±0.25s) to fix drift, or reset.
- **Click-Through** — the overlay ignores the mouse so clicks land behind it.
- **Launch at Login** — start automatically when you log in.

If macOS Automation permission is denied, the overlay shows a **Grant
Automation access** button that opens the right System Settings pane.

The overlay's **position and size** and these toggle states are remembered
between launches (stored in `UserDefaults`), so you set things up once.

### Open in Xcode instead

`File → Open…` and pick `Package.swift`, then Run. (Running via
`scripts/build-app.sh` is preferred, since it produces the `.app` with the
Info.plist and entitlements the automation permission needs.)

## Publish a release

`.github/workflows/release.yml` builds the app, packages a `.dmg`, and attaches
it to a GitHub Release. Cut one by pushing a tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The DMG appears under the repo's **Releases**. (You can also build a DMG
locally: `bash scripts/build-app.sh && bash scripts/make-dmg.sh`.)

> Downloaded builds are **unsigned** (no Apple Developer ID), so whoever installs
> one must clear the quarantine once:
> ```bash
> xattr -cr /Applications/lrclrclrc.app
> ```
> Making double-click-clean installs for *anyone* requires an Apple Developer
> account ($99/yr) for signing + notarization. Building locally needs none of this.

## Continuous integration

`.github/workflows/ci.yml` runs on every push/PR to `main`: it builds the
package on macOS, assembles the `.app`, verifies the code signature, and
uploads a `.dmg` as a build artifact (downloadable from the Actions run).

## Project layout

```
Package.swift
Sources/lrclrclrc/
  main.swift             AppKit entry point (menu-bar agent)
  AppDelegate.swift      Status item + overlay panel wiring
  OverlayPanel.swift     Borderless always-on-top NSPanel
  OverlayView.swift      SwiftUI glass lyric card
  LyricsController.swift Polling + smooth line syncing
  MusicWatcher.swift     AppleScript track/position reader
  LyricsService.swift    LRCLIB fetch
  LRCParser.swift        .lrc parser
bundling/
  Info.plist             LSUIElement + NSAppleEventsUsageDescription
  lrclrclrc.entitlements apple-events automation entitlement
scripts/build-app.sh     compile + bundle + ad-hoc sign
```

## License

MIT
