'use strict';

// Fetches synced lyrics from LRCLIB (https://lrclib.net) and parses the
// returned .lrc into an array of timestamped lines. LRCLIB is free and
// key-less; we send a descriptive User-Agent as their docs request.

const PkgName = 'lrclrclrc';
const UserAgent = `${PkgName} v0.1.0 (https://github.com/jtanudjaja/lrclrclrc)`;
const BASE = 'https://lrclib.net/api';

async function httpGetJson(url) {
  const res = await fetch(url, {
    headers: { 'User-Agent': UserAgent, Accept: 'application/json' },
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`LRCLIB ${res.status} ${res.statusText}`);
  return res.json();
}

/**
 * Parse an LRC string into sorted { time, text } lines.
 * Handles multi-timestamp lines like `[00:12.34][01:02.00] text`.
 * @param {string} lrc
 * @returns {Array<{time:number, text:string}>}
 */
function parseLrc(lrc) {
  if (!lrc || typeof lrc !== 'string') return [];
  const out = [];
  const tag = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g;

  for (const line of lrc.split(/\r?\n/)) {
    tag.lastIndex = 0;
    const stamps = [];
    let m;
    while ((m = tag.exec(line)) !== null) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      const fracStr = m[3] || '0';
      const frac = parseInt(fracStr, 10) / Math.pow(10, fracStr.length);
      stamps.push(min * 60 + sec + frac);
    }
    if (stamps.length === 0) continue; // metadata line like [ar:...] or no tag
    const text = line.replace(tag, '').trim();
    for (const time of stamps) out.push({ time, text });
  }
  out.sort((a, b) => a.time - b.time);
  return out;
}

/**
 * Look up lyrics for a track. Tries the exact signature endpoint first,
 * then falls back to search. Returns synced lines when available, else
 * plain lines with time=null.
 *
 * @param {{title:string, artist:string, album?:string, duration?:number}} track
 * @returns {Promise<{synced:boolean, lines:Array<{time:number|null,text:string}>, source:string}|null>}
 */
async function fetchLyrics(track) {
  const { title, artist, album = '', duration = 0 } = track;
  if (!title || !artist) return null;

  const q = new URLSearchParams({
    track_name: title,
    artist_name: artist,
  });
  if (album) q.set('album_name', album);
  if (duration) q.set('duration', String(Math.round(duration)));

  // 1) Exact match by signature.
  let rec = await httpGetJson(`${BASE}/get?${q.toString()}`);

  // 2) Fall back to fuzzy search and take the best-scoring hit.
  if (!rec) {
    const sq = new URLSearchParams({ track_name: title, artist_name: artist });
    const results = await httpGetJson(`${BASE}/search?${sq.toString()}`);
    if (Array.isArray(results) && results.length) {
      rec =
        results.find((r) => r.syncedLyrics) ||
        results.find((r) => r.plainLyrics) ||
        results[0];
    }
  }

  if (!rec) return null;

  if (rec.syncedLyrics) {
    const lines = parseLrc(rec.syncedLyrics);
    if (lines.length) {
      return { synced: true, lines, source: 'lrclib' };
    }
  }

  if (rec.plainLyrics) {
    const lines = rec.plainLyrics
      .split(/\r?\n/)
      .map((t) => ({ time: null, text: t.trim() }));
    return { synced: false, lines, source: 'lrclib' };
  }

  return null;
}

module.exports = { fetchLyrics, parseLrc };
