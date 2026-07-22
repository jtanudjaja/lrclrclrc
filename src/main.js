'use strict';

const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  ipcMain,
  screen,
  nativeImage,
} = require('electron');
const path = require('path');

const { getNowPlaying } = require('./appleMusic');
const { fetchLyrics } = require('./lyrics');

const POLL_MS = 1000; // how often we ask Music where it is

let overlayWindow = null;
let tray = null;
let pollTimer = null;
let clickThrough = false;

// Remembers the last track so we only hit LRCLIB when the song actually
// changes, plus a tiny in-memory cache keyed by persistent track id.
let lastTrackId = null;
const lyricsCache = new Map();

function createOverlay() {
  const { workArea } = screen.getPrimaryDisplay();
  const width = 620;
  const height = 140;

  overlayWindow = new BrowserWindow({
    width,
    height,
    x: Math.round(workArea.x + (workArea.width - width) / 2),
    y: Math.round(workArea.y + workArea.height - height - 40),
    frame: false,
    transparent: true,
    hasShadow: false,
    resizable: false,
    movable: true,
    skipTaskbar: true,
    fullscreenable: false,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  // Float above normal windows and follow the user across Spaces and
  // full-screen apps.
  overlayWindow.setAlwaysOnTop(true, 'screen-saver');
  overlayWindow.setVisibleOnAllWorkspaces(true, {
    visibleOnFullScreen: true,
  });

  overlayWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

  overlayWindow.once('ready-to-show', () => overlayWindow.show());
}

function setClickThrough(on) {
  clickThrough = on;
  if (!overlayWindow) return;
  // forward:true still lets hover effects work while passing clicks through.
  overlayWindow.setIgnoreMouseEvents(on, { forward: true });
  overlayWindow.webContents.send('clickthrough-changed', on);
  rebuildTrayMenu();
}

function send(channel, payload) {
  if (overlayWindow && !overlayWindow.isDestroyed()) {
    overlayWindow.webContents.send(channel, payload);
  }
}

async function tick() {
  let np;
  try {
    np = await getNowPlaying();
  } catch (e) {
    send('status', { status: 'error', message: e.message });
    return;
  }

  if (np.status !== 'ok') {
    lastTrackId = null;
    send('status', { status: np.status });
    return;
  }

  // Always push the current playback position so the renderer can keep the
  // highlighted line in sync.
  send('position', {
    position: np.position,
    playerState: np.playerState,
    duration: np.duration,
  });

  if (np.trackId === lastTrackId) return; // same song, nothing new to load
  lastTrackId = np.trackId;

  send('track', {
    title: np.title,
    artist: np.artist,
    album: np.album,
  });

  if (lyricsCache.has(np.trackId)) {
    send('lyrics', lyricsCache.get(np.trackId));
    return;
  }

  send('status', { status: 'loading' });
  try {
    const result = await fetchLyrics({
      title: np.title,
      artist: np.artist,
      album: np.album,
      duration: np.duration,
    });
    const payload = result || { synced: false, lines: [], source: null };
    lyricsCache.set(np.trackId, payload);
    // Guard against a race where the track changed while we were fetching.
    if (np.trackId === lastTrackId) send('lyrics', payload);
  } catch (e) {
    send('status', { status: 'error', message: e.message });
  }
}

function startPolling() {
  if (pollTimer) return;
  tick();
  pollTimer = setInterval(tick, POLL_MS);
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

function trayIcon() {
  // A tiny generated dot so the app has a menu-bar presence without shipping
  // a binary asset. Template image adapts to light/dark menu bars.
  const img = nativeImage.createFromDataURL(
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAWklEQVR4nO3QsQ2AMAxE0Z8oe2QIRmEHZmEHRmEXhqBFQqLCFEjxSfZJr7Fk2wAAAAAAAADwPzOzUdKQdEo6JC2SVvfeb9uSNknmZjbn3M3sqarXWvsBAAB44wYUxQr7bXcT+wAAAABJRU5ErkJggg=='
  );
  img.setTemplateImage(true);
  return img;
}

function rebuildTrayMenu() {
  if (!tray) return;
  const menu = Menu.buildFromTemplate([
    {
      label: overlayWindow && overlayWindow.isVisible()
        ? 'Hide overlay'
        : 'Show overlay',
      click: () => {
        if (!overlayWindow) return;
        overlayWindow.isVisible() ? overlayWindow.hide() : overlayWindow.show();
        rebuildTrayMenu();
      },
    },
    {
      label: 'Click-through (ignore mouse)',
      type: 'checkbox',
      checked: clickThrough,
      click: (item) => setClickThrough(item.checked),
    },
    { type: 'separator' },
    { label: 'Quit lrclrclrc', click: () => app.quit() },
  ]);
  tray.setContextMenu(menu);
}

function createTray() {
  tray = new Tray(trayIcon());
  tray.setToolTip('lrclrclrc — Apple Music lyrics overlay');
  rebuildTrayMenu();
}

// Renderer asks to toggle click-through (e.g. via a hover button).
ipcMain.on('set-clickthrough', (_e, on) => setClickThrough(!!on));
ipcMain.on('quit-app', () => app.quit());

app.whenReady().then(() => {
  // No Dock icon — this lives in the menu bar.
  if (app.dock) app.dock.hide();

  createOverlay();
  createTray();
  startPolling();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createOverlay();
  });
});

app.on('window-all-closed', () => {
  // Menu-bar app: stay alive even with the overlay hidden.
});

app.on('before-quit', stopPolling);
