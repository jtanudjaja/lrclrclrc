# lrclrclrc

A floating, always-on-top **lyrics overlay for Apple Music on macOS**, built
with Electron. It watches whatever's playing in the Music app, pulls
time-synced lyrics from [LRCLIB](https://lrclib.net) (free, no API key), and
highlights each line in a translucent window that stays above your other apps
and follows you across Spaces and full-screen apps.

> **macOS only.** Track detection uses AppleScript against the Music app, so
> the overlay only does anything useful on a Mac with Apple Music.

## How it works

Three moving parts, matching the three hard problems of a lyrics overlay:

1. **What's playing** — `src/appleMusic.js` runs a small AppleScript via
   `osascript` to read the current track's title, artist, album, duration,
   and *playback position*, once a second.
2. **The lyrics** — `src/lyrics.js` queries LRCLIB with that track signature.
   It first tries the exact `/api/get` endpoint, then falls back to
   `/api/search`. Returned `.lrc` text is parsed into `{ time, text }` lines.
   Apple's own synced lyrics are licensed and locked in the Music app, so like
   every other DIY overlay this leans on a third-party source — sync quality
   therefore varies by song.
3. **The overlay** — `src/main.js` creates a borderless, transparent
   `BrowserWindow` pinned with `setAlwaysOnTop(true, 'screen-saver')` and
   `setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })`. The
   renderer (`renderer/`) extrapolates the 1 Hz position samples with a local
   60fps clock so the highlighted line advances smoothly.

## Run it

Use **Node 22 LTS** (an `.nvmrc` pins it). Bleeding-edge/odd Node releases can
break Electron's install step, so with [nvm](https://github.com/nvm-sh/nvm):

```bash
nvm use          # reads .nvmrc → Node 22 (run `nvm install 22` first time)
npm install
npm start
```

The app has **no Dock icon** — it lives in the menu bar (the small dot). During
development macOS asks the *terminal* for Automation permission; the packaged
app asks for itself. From the menu-bar icon you can show/hide the overlay,
toggle click-through, and quit. On first run macOS will ask permission to
control the **Music** app — grant it, otherwise track detection returns nothing.

### Controls

- **Drag** the card anywhere to reposition it.
- Hover the card to reveal the **☝︎ click-through** and **✕ quit** buttons.
- **Click-through** makes the overlay ignore the mouse so clicks land on the
  app behind it (it dims slightly to show it's passive). Toggle it back from
  the menu-bar icon.

## Check it works

Before (or instead of) launching the overlay, run the doctor to test each
piece of the pipeline independently and see exactly what's healthy:

```bash
npm run doctor
```

It checks, in order: you're on macOS with `osascript`; the Music app's current
track can be read; and LRCLIB returns synced lyrics for it (falling back to a
known song if nothing's playing). Each line reports `PASS` / `WARN` / `FAIL`
with a fix hint — so a denied Automation permission or a song LRCLIB doesn't
have shows up as a specific message instead of a blank overlay.

## Build an installable app

Package a universal (`arm64` + `x64`) macOS `.dmg` with electron-builder:

```bash
npm install
npm run dist        # → dist/lrclrclrc-<version>-universal.dmg
```

Open the DMG and drag **lrclrclrc** to Applications. Because the build isn't
signed with an Apple Developer ID, Gatekeeper blocks it on first launch —
**right-click the app → Open**, then confirm, to run it anyway. On launch macOS
prompts to allow it to control **Music**; grant it or track detection stays
empty.

The packaged app requests the `com.apple.security.automation.apple-events`
entitlement (see `build/entitlements.mac.plist`) and ships as an `LSUIElement`
agent so it has no Dock icon.

Other build targets:

```bash
npm run pack        # unpacked .app in dist/ (fast, for local testing)
```

## Continuous integration

`.github/workflows/ci.yml` runs on every push and PR to `main`:

- **check** (Ubuntu) — `npm run check`, a dependency-free `node --check` pass
  over every JS file plus a `package.json` parse check.
- **build-mac** (macOS) — builds the universal DMG (ad-hoc signed, since CI has
  no Developer ID) and uploads it as the `lrclrclrc-macos-dmg` artifact, so you
  can download an installable build straight from the Actions run.

Run the checks locally with `npm run check`.

## Project layout

```
src/
  main.js        Electron main: window, tray, polling loop, IPC
  preload.js     Safe contextBridge API exposed to the renderer
  appleMusic.js  osascript track/position reader
  lyrics.js      LRCLIB fetch + .lrc parser
renderer/
  index.html     Overlay markup
  overlay.css    Glass card styling
  overlay.js     Line syncing + rendering
```

## Notes & limitations

- **Sync accuracy** depends on the LRCLIB entry for the song; some are dead-on,
  some drift, some only have plain (unsynced) lyrics, some have none.
- Polling every second keeps it simple and robust. macOS also broadcasts a
  `com.apple.Music.playerInfo` distributed notification on track changes; a
  future version could subscribe to that for instant updates.
- No keys, no accounts, nothing to configure. LRCLIB is queried with a
  descriptive `User-Agent` as their docs request.

## License

MIT
