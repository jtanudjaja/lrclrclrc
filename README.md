# lrclrclrc

Time-synced lyrics floating above everything else, for **Apple Music and
Spotify on macOS**.

[![CI](https://github.com/jtanudjaja/lrclrclrc/actions/workflows/ci.yml/badge.svg)](https://github.com/jtanudjaja/lrclrclrc/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

A native **SwiftUI / AppKit** menu-bar app with no third-party dependencies. It
watches whatever's playing, pulls time-synced lyrics from
[LRCLIB](https://lrclib.net) (free, no API key), and highlights each line on a
translucent card that floats above your other windows.

Project page: <https://jtanudjaja.github.io/lrclrclrc/> (source in [`site/`](site/)).

## Requirements

- **macOS 13 Ventura or later** — macOS only; there is no Windows or Linux build.
- **Apple Music or Spotify** installed and running. Track detection talks to
  them over AppleScript, so one of them has to be open.
- **Xcode Command Line Tools** to build (`xcode-select --install`). Full Xcode
  is optional.

## Install

Build it locally — three lines:

```bash
git clone https://github.com/jtanudjaja/lrclrclrc.git
cd lrclrclrc
make install
```

That compiles the app, copies it to `/Applications`, and launches it. Use
`make run` to launch it from the build directory instead, without installing.

Because a locally built app carries no download quarantine, macOS runs it
straight away — no Gatekeeper "unidentified developer" prompt. That prompt only
appears for apps downloaded from the internet, which is why there's no download
button: builds published to **Releases** are unsigned (no Apple Developer ID)
and have to be un-quarantined by hand after install:

```bash
xattr -cr /Applications/lrclrclrc.app
```

Double-click-clean installs for *anyone* would need an Apple Developer account
($99/yr) for signing and notarization. Building locally needs none of it.

### First launch

A short **welcome wizard** runs: it asks macOS for permission to control
**Music** / **Spotify** (click **OK**, or track detection stays empty) and lets
you pick which player to follow.

The app then lives in the menu bar (the ♫ icon) — from there you can change
where lyrics show, pick a player, and quit.

## Using it

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
  clicks land behind it, and it goes fully passive (see
  [How it works](#how-it-works)).
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

## Privacy

The app talks to exactly one server: **lrclib.net**. Each lookup sends the
current track's **title, artist, album, and duration** as query parameters,
plus a `lrclrclrc/<version>` User-Agent. Nothing else leaves your Mac — no
analytics, no accounts, no crash reporting, no other network calls.

Everything else is local: lyrics are cached in `~/Library/Caches/lrclrclrc/`,
and settings, per-song timing offsets, and pasted lyrics live in `UserDefaults`.
Deleting the cache directory is safe; it refills on demand.

## Troubleshooting

**No track ever shows up.** macOS Automation permission was denied. The overlay
shows a **Grant Automation access** button that opens the right pane, or go to
System Settings → Privacy & Security → Automation and enable **Music** /
**Spotify** under lrclrclrc. If the app was never listed there, `tccutil reset
AppleEvents` makes macOS ask again on relaunch — note that it clears the
automation permission for *every* app, not just this one.

**A song has no lyrics.** LRCLIB simply may not have it. Use **Find Lyrics…**
(⌘L) to look it up and paste an `.lrc` — it's remembered for that track.

**Lyrics run early or late.** Use the ±0.1s nudge in the card footer, or the
±0.25s steps in the **Timing** menu. The correction is saved per song.

**Nothing is highlighted, or lines don't advance.** Only *synced* lyrics
advance; a plain-text result has no timestamps. The source chip in the card
header shows what was found.

**The card is in the way.** Turn on **Click-Through** (⌘T) so clicks pass
through it, or set **Show Lyrics In → Menu Bar / Hidden**.

## Development

```bash
make            # same as make run
make build      # compile + assemble lrclrclrc.app
make run        # build, then (re)launch
make install    # build, copy into /Applications, launch
make dmg        # build and package lrclrclrc.dmg
make debug      # debug configuration
make clean      # remove build outputs
```

Or call the scripts directly:
`bash scripts/build-app.sh && open lrclrclrc.app`.

**In Xcode:** `File → Open…` and pick `Package.swift`, then Run. Building via
`scripts/build-app.sh` is preferred, since it produces the `.app` with the
Info.plist and entitlements the automation permission needs.

There is no test suite yet; CI is a build gate.

### Project layout

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
  icon.icns               App icon (generated, not tracked)
scripts/
  build-app.sh            compile + bundle + ad-hoc sign
  make-dmg.sh             package the .dmg
  make-icon.swift         generate icon.icns
site/                     the project page (static; see site/README.md)
```

### Continuous integration

- `.github/workflows/ci.yml` runs on every push/PR to `main`: builds the package
  on macOS, assembles the `.app`, verifies the code signature, and uploads a
  `.dmg` as a build artifact (downloadable from the Actions run).
- `.github/workflows/pages.yml` deploys `site/` to GitHub Pages when the site
  changes. It needs the repo's Pages source set to **GitHub Actions**.

### Publishing a release

`.github/workflows/release.yml` builds the app, packages a `.dmg`, and attaches
it to a GitHub Release. Cut one by pushing a tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The DMG appears under the repo's **Releases**. You can also build one locally:
`bash scripts/build-app.sh && bash scripts/make-dmg.sh`.

## Contributing

Issues and pull requests are welcome.

- **Bugs** — include your macOS version, which player (Music or Spotify), and
  the track that reproduces it. Sync problems are often song-specific.
- **Pull requests** — branch off `main`, keep `make build` green (CI runs it on
  macOS), and match the surrounding style: no third-party dependencies, and
  comments that explain *why* rather than restate the code.
- **Scope** — this is a lyrics overlay for macOS. Features that need a signing
  identity, a server, or a new dependency are unlikely to land.
- **Docs** — if you change the menu, Preferences, or the timing steps, update
  this README and the matching copy in `site/` (see
  [`site/README.md`](site/README.md)).

Please don't paste song lyrics into issues, PRs, or the demo page — the app
fetches them at runtime, and this repo keeps none.

## Acknowledgements

- **[LRCLIB](https://lrclib.net)** — the free, no-API-key lyrics database this
  app depends on. If you find it useful, consider contributing lyrics back.
- Built entirely on Apple's own frameworks — SwiftUI, AppKit, Combine, ImageIO.
  No third-party packages.

## License

MIT © 2026 Jonathan Tanudjaja — see [LICENSE](LICENSE).

Lyrics fetched at runtime belong to their respective rights holders; this
project neither bundles nor redistributes any.
