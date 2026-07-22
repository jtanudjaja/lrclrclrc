'use strict';

// State
let lines = []; // [{ time:number|null, text:string }]
let synced = false;
let currentIndex = -1;

// Playback clock: we get a position sample roughly once a second from the
// main process, then extrapolate locally at 60fps so the highlight advances
// smoothly instead of jumping once per poll.
let anchorPos = 0; // seconds, from Music
let anchorAt = 0; // performance.now() when we took the sample
let playing = false;

const el = {
  body: document.body,
  title: document.getElementById('title'),
  artist: document.getElementById('artist'),
  prev: document.getElementById('line-prev'),
  current: document.getElementById('line-current'),
  next: document.getElementById('line-next'),
  status: document.getElementById('status'),
};

function estimatedPosition() {
  if (!playing) return anchorPos;
  return anchorPos + (performance.now() - anchorAt) / 1000;
}

function indexForTime(t) {
  // Last line whose timestamp is <= t.
  let lo = 0;
  let hi = lines.length - 1;
  let ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (lines[mid].time <= t) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

function renderAt(index) {
  const cur = lines[index];
  const prev = lines[index - 1];
  const next = lines[index + 1];

  el.current.textContent = cur ? cur.text : synced ? '♪' : '';
  el.prev.textContent = prev ? prev.text : '';
  el.next.textContent = next ? next.text : '';

  el.current.classList.toggle('plain', !synced);
}

function frame() {
  if (synced && lines.length) {
    const t = estimatedPosition();
    const idx = indexForTime(t);
    if (idx !== currentIndex) {
      currentIndex = idx;
      renderAt(idx);
    }
  }
  requestAnimationFrame(frame);
}

// ---- Wire up main-process events -------------------------------------

window.lrc.onTrack((t) => {
  el.title.textContent = t.title || '';
  el.artist.textContent = t.artist || '';
});

window.lrc.onLyrics((data) => {
  lines = Array.isArray(data.lines) ? data.lines : [];
  synced = !!data.synced && lines.some((l) => l.time !== null);
  currentIndex = -1;

  if (!lines.length) {
    el.current.textContent = '— no lyrics found —';
    el.prev.textContent = '';
    el.next.textContent = '';
    el.current.classList.add('plain');
    el.status.textContent = '';
    return;
  }

  if (synced) {
    el.status.textContent = 'synced · LRCLIB';
    renderAt(indexForTime(estimatedPosition()));
  } else {
    // Plain lyrics: no timing, so just show the opening lines statically.
    el.status.textContent = 'unsynced · LRCLIB';
    el.prev.textContent = '';
    el.current.textContent = lines[0].text;
    el.next.textContent = lines[1] ? lines[1].text : '';
    el.current.classList.add('plain');
  }
});

window.lrc.onPosition((p) => {
  anchorPos = p.position;
  anchorAt = performance.now();
  playing = p.playerState === 'playing';
});

window.lrc.onStatus((s) => {
  switch (s.status) {
    case 'loading':
      el.status.textContent = 'looking up lyrics…';
      break;
    case 'not-running':
      el.title.textContent = 'lrclrclrc';
      el.artist.textContent = 'Apple Music isn’t running';
      el.current.textContent = '';
      el.prev.textContent = '';
      el.next.textContent = '';
      el.status.textContent = '';
      break;
    case 'stopped':
      el.artist.textContent = 'Nothing playing';
      el.current.textContent = '';
      el.prev.textContent = '';
      el.next.textContent = '';
      break;
    case 'error':
      el.status.textContent = `error: ${s.message || 'unknown'}`;
      break;
  }
});

window.lrc.onClickThrough((on) => {
  el.body.classList.toggle('clickthrough', on);
});

// ---- Controls --------------------------------------------------------

document.getElementById('btn-clickthrough').addEventListener('click', () => {
  const on = !el.body.classList.contains('clickthrough');
  window.lrc.setClickThrough(on);
});

document.getElementById('btn-quit').addEventListener('click', () => {
  window.lrc.quit();
});

requestAnimationFrame(frame);
