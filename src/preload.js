'use strict';

const { contextBridge, ipcRenderer } = require('electron');

// Minimal, explicit surface exposed to the renderer. No Node access leaks.
contextBridge.exposeInMainWorld('lrc', {
  // main -> renderer events
  onTrack: (cb) => ipcRenderer.on('track', (_e, d) => cb(d)),
  onLyrics: (cb) => ipcRenderer.on('lyrics', (_e, d) => cb(d)),
  onPosition: (cb) => ipcRenderer.on('position', (_e, d) => cb(d)),
  onStatus: (cb) => ipcRenderer.on('status', (_e, d) => cb(d)),
  onClickThrough: (cb) => ipcRenderer.on('clickthrough-changed', (_e, d) => cb(d)),

  // renderer -> main commands
  setClickThrough: (on) => ipcRenderer.send('set-clickthrough', on),
  quit: () => ipcRenderer.send('quit-app'),
});
