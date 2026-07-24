# lrclrclrc

A floating lyrics overlay for **Apple Music and Spotify on macOS**, written as a
native **SwiftUI / AppKit** menu-bar app. It watches whatever's playing, pulls
time-synced lyrics from [LRCLIB](https://lrclib.net) (free, no API key), and
highlights each line on a translucent card that floats above your other windows.

The project page (source in [`site/`](site/)) is at
<https://jtanudjaja.github.io/lrclrclrc/>.

> **macOS only** (13 Ventura or later). Track detection talks to Apple Music /
> Spotify over AppleScript, so it needs one of them running.

## How it works

Three moving parts, matching the three hard problems of a lyrics overlay:

1. **What's playing** — `MusicWatcher.swift` runs small AppleScripts
   (`NSAppleScript`) to read the current track's title, artist, album, duration,
   *playback position*, and cover art. Polling is once a second while a track is
   playing (~3s when idle), and the players' change notifications wake it
   instantly.
2. **The lyrics** — `LyricsService.swift` queries LRCLIB with that track
   signature (exact `/api/get`, falling back to `/api/search` and picking the
   closest-duration synced candidate). `LRCParser.swift` turns the returned
   `.lrc` into timestamped lines, and `DiskLyricsCache.swift` keeps them in
   `~/Library/Caches/lrclrclrc/` so repeat plays are instant and an LRCLIB
   outage isn't fatal. Apple's own synced lyrics are licensed and locked in the
   Music app, so — like every DIY overlay — this leans on a third-party source,
   and sync quality varies by song.
3. **The overlay** — `OverlayPanel.swift` is a transparent `NSPanel` with hidden
   chrome. By default it's an ordinary, activatable window at `.floating` level
   (the FaceTime model): above your normal windows, but natively focusable and
   natively resizable, cursors included. Turning on **Click-Through** swaps in
   the passive profile — `.screenSaver` level, non-activating, mouse-transparent,
   `[.canJoinAllSpaces, .fullScreenAuxiliary, …]` — so it rides over full-screen
   apps as pure scenery. `LyricsController.swift` extrapolates the 1 Hz position
   samples at ~10fps so the highlighted line advances smoothly.

## Build & run

You need **Xcode Command Line Tools** (`xcode-select --install`) — full Xcode is
optional. Then just:

```bash
make run
```

Other targets: `make build` (compile + assemble only), `make install` (copy the
app into `/Applications` and launch it), `make dmg` (package a `.dmg`),
`make debug`, `make clean`. Or call the scripts directly:
`bash scripts/build-app.sh && open lrclrclrc.app`.

Because the app is **built locally**, it carries no download quarantine, so
macOS runs it straight away — no Gatekeeper "unidentified developer" / malware
prompt. (That prompt only appears for apps downloaded from the internet.)

On first launch a short **welcome wizard** runs: it asks macOS for permission to
control **Music** / **Spotify** (click **OK**, or track detection stays empty)
and lets you pick which player to follow. You can re-enable the permission later
under System Settings → Privacy & Security → Automation; if it's denied, the
overlay itself shows a **Grant Automation access** button that opens the right
pane.

The app lives in the menu bar (the ♫ icon) — from there you can change where
lyrics show, pick a player, and quit.

### The overlay card

- **Drag the header** to move the card (it's the title bar), drag any **edge or
  corner** to resize — a taller card shows more lyric lines.
- **Click a line, or scrub vertically**, to seek playback there.
- **Hover** to reveal the header (art, title, artist, source chip) and the
  footer: **⏮ ⏯ ⏭** transport controls plus a live **−/＋ timing nudge**
  (±0.1s) with the current offset shown. "Always show controls" in Preferences
  keeps them visible.
- With nothing playing for ~30s the card fades back to near-invisible.

### Menu-bar menu (♫)

- **Show Lyrics In** — **Overlay** (the floating card), **Menu Bar** (the
  current line in the menu bar, ♫ hidden for room), or **Hidden**.
- **Follow** — **Automatic** (whichever enabled player is playing), or pin a
  specific one. The list only offers players enabled in Preferences.
- **Full Lyrics…** (⌘F) — the whole song, scrollable, current line highlighted;
  click any timed line to **seek** playback there.
- **Find Lyrics…** (⌘L) — when a song has no lyrics, open lrclib.net to look it
  up, then paste the `.lrc` (timed) or plain text; it's remembered for that
  track.
- **Preferences…** — the window below (⌘, also opens it while the app is
  active).
- **Timing** — nudge lyrics **earlier/later** in coarse ±0.25s steps, with a
  live offset readout and **Reset Timing**. The offset is remembered **per
  song**, so each track keeps its own correction.
- **Click-Through (ignore mouse)** (⌘T) — the overlay ignores the mouse so
  clicks land behind it, and it goes fully passive (see above).
- **Launch at Login** — start automatically when you log in.

### Preferences (⌘,)

One window, resizable, remembering its own frame:

- **Source** — which enabled player the lyrics follow (or Automatic).
- **Music Apps** — enable/disable Apple Music and Spotify. Apps installed on
  this Mac are enabled automatically; turn on one that wasn't found and the app
  asks you to point at it.
- **Lyrics** — overlay / menu bar / hidden.
- **Appearance** — text size, background opacity when not hovered, text color
  (light presets for dark wallpaper and art, dark presets for a bright desktop,
  plus a custom picker), always-show-controls.
- **Behavior** — launch at login, click-through.
- **Reset to Defaults…** — settings only; per-song data (sync offsets, manual
  lyrics, cached lyrics) is kept.

The overlay's **position and size** and every toggle are stored in
`UserDefaults`, so you set things up once.

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

- `.github/workflows/ci.yml` runs on every push/PR to `main`: builds the package
  on macOS, assembles the `.app`, verifies the code signature, and uploads a
  `.dmg` as a build artifact (downloadable from the Actions run).
- `.github/workflows/pages.yml` deploys `site/` to GitHub Pages when the site
  changes. It needs the repo's Pages source set to **GitHub Actions**.

## Project layout

```
Package.swift
Sources/lrclrclrc/
  main.swift              AppKit entry point (menu-bar agent)
  AppDelegate.swift       Status item, menu, windows, overlay wiring
  OverlayPanel.swift      Transparent floating window (+ passive profile)
  OverlayView.swift       SwiftUI glass lyric card
  OverlayMetrics.swift    Live minimum-size / layout math
  Appearance.swift        Text size, opacity, color (the two-pole palette)
  LyricsController.swift  Polling, smooth line syncing, transport, offsets
  MusicWatcher.swift      AppleScript track/position/artwork reader
  LyricsService.swift     LRCLIB fetch
  LRCParser.swift         .lrc parser
  DiskLyricsCache.swift   ~/Library/Caches lyric store
  LRUCache.swift          In-memory cache
  OffsetStore.swift       Per-song timing offsets
  OverrideStore.swift     Per-song pasted lyrics
  Artwork.swift           Thread-safe ImageIO album-art decode
  Settings.swift          UserDefaults-backed state
  PreferencesView.swift   Preferences window
  FullLyricsView.swift    Whole-song window (click to seek)
  FindLyricsView.swift    Paste-your-own-lyrics window
  OnboardingView.swift    First-run wizard
  WindowDragSurface.swift Header/footer drag handle
bundling/
  Info.plist              LSUIElement + NSAppleEventsUsageDescription
  lrclrclrc.entitlements  apple-events automation entitlement
  icon.icns               App icon
scripts/
  build-app.sh            compile + bundle + ad-hoc sign
  make-dmg.sh             package the .dmg
  make-icon.swift         generate icon.icns
site/                     the project page (static; see site/README.md)
```

## License

MIT
