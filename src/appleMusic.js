'use strict';

// Reads the currently playing track from the macOS Music app via AppleScript.
//
// We shell out to `osascript`. Fields are joined with the ASCII "unit
// separator" character (0x1F) because it never appears in track metadata,
// so titles/artists that contain commas, newlines, quotes, etc. stay intact.

const { execFile } = require('child_process');

const SEP = String.fromCharCode(31); // matches `ASCII character 31` below

const SCRIPT = `
set d to (ASCII character 31)
tell application "System Events"
  set isRunning to (exists (processes where name is "Music"))
end tell
if not isRunning then return "not-running"
tell application "Music"
  set s to (player state as string)
  if s is not "playing" and s is not "paused" then return "stopped" & d & s
  try
    set t to current track
    set nm to name of t
    set ar to artist of t
    set al to album of t
    set dur to duration of t
    set pos to player position
    set pid to (persistent ID of t)
    return "ok" & d & nm & d & ar & d & al & d & (dur as string) & d & (pos as string) & d & s & d & pid
  on error
    return "stopped" & d & s
  end try
end tell
`;

function runOsascript() {
  return new Promise((resolve, reject) => {
    execFile(
      'osascript',
      ['-e', SCRIPT],
      { timeout: 4000 },
      (err, stdout) => {
        if (err) return reject(err);
        resolve(String(stdout).replace(/\n$/, ''));
      }
    );
  });
}

/**
 * @typedef {Object} NowPlaying
 * @property {'ok'|'stopped'|'not-running'} status
 * @property {string} [title]
 * @property {string} [artist]
 * @property {string} [album]
 * @property {number} [duration]  seconds
 * @property {number} [position]  seconds
 * @property {'playing'|'paused'} [playerState]
 * @property {string} [trackId]   persistent ID, stable per library track
 */

/** @returns {Promise<NowPlaying>} */
async function getNowPlaying() {
  let raw;
  try {
    raw = await runOsascript();
  } catch (e) {
    // osascript missing (non-mac), Music not scriptable, or timeout.
    return { status: 'not-running', error: e.message };
  }

  const parts = raw.split(SEP);
  const head = parts[0];

  if (head === 'not-running') return { status: 'not-running' };
  if (head === 'stopped') return { status: 'stopped' };
  if (head !== 'ok') return { status: 'stopped' };

  const [, title, artist, album, dur, pos, state, trackId] = parts;
  return {
    status: 'ok',
    title: title || '',
    artist: artist || '',
    album: album || '',
    duration: Number(dur) || 0,
    position: Number(pos) || 0,
    playerState: state === 'playing' ? 'playing' : 'paused',
    trackId: trackId || `${artist}::${title}`,
  };
}

module.exports = { getNowPlaying };
