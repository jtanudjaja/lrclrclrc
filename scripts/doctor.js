'use strict';

// `npm run doctor` — verifies each piece of the pipeline independently so you
// can see exactly what works and what doesn't, without launching the overlay.
//
//   1. Environment    — are we on macOS with osascript available?
//   2. Track detection — can we read the current track from the Music app?
//   3. Lyrics lookup   — does LRCLIB return synced lyrics for that track?
//
// Each check prints PASS / WARN / FAIL and, on failure, the most likely fix.
// Exit code is non-zero if any hard check fails.

const os = require('os');
const { execFileSync } = require('child_process');
const { getNowPlaying } = require('../src/appleMusic');
const { fetchLyrics } = require('../src/lyrics');

const C = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  dim: '\x1b[2m',
  bold: '\x1b[1m',
};
const tag = {
  pass: `${C.green}PASS${C.reset}`,
  warn: `${C.yellow}WARN${C.reset}`,
  fail: `${C.red}FAIL${C.reset}`,
};

function line(status, label, detail) {
  console.log(`  ${status}  ${C.bold}${label}${C.reset}${detail ? ' — ' + detail : ''}`);
}
function hint(text) {
  console.log(`        ${C.dim}↳ ${text}${C.reset}`);
}

async function main() {
  console.log(`\n${C.bold}lrclrclrc doctor${C.reset}\n`);
  let hardFailure = false;

  // ---- 1. Environment ------------------------------------------------
  const platform = os.platform();
  if (platform !== 'darwin') {
    line(tag.fail, 'Environment', `this is ${platform}, not macOS`);
    hint('Track detection uses AppleScript against the Music app, so this only');
    hint('works on a Mac. Nothing below can pass here.');
    console.log('');
    process.exit(1);
  }
  let hasOsascript = true;
  try {
    execFileSync('which', ['osascript'], { stdio: 'pipe' });
  } catch {
    hasOsascript = false;
  }
  if (!hasOsascript) {
    line(tag.fail, 'Environment', 'osascript not found on PATH');
    process.exit(1);
  }
  line(tag.pass, 'Environment', 'macOS with osascript');

  // ---- 2. Track detection -------------------------------------------
  let np;
  try {
    np = await getNowPlaying();
  } catch (e) {
    line(tag.fail, 'Track detection', e.message);
    np = { status: 'error' };
  }

  switch (np.status) {
    case 'ok':
      line(
        tag.pass,
        'Track detection',
        `${np.title} — ${np.artist}  ${C.dim}(${np.position.toFixed(1)}s / ${np.duration.toFixed(0)}s, ${np.playerState})${C.reset}`
      );
      break;
    case 'not-running':
      line(tag.warn, 'Track detection', 'the Music app isn’t running');
      hint('Open Music and press play, then run `npm run doctor` again.');
      hint('If Music IS playing, macOS may be blocking Automation — grant it in');
      hint('System Settings → Privacy & Security → Automation → (your terminal).');
      break;
    case 'stopped':
      line(tag.warn, 'Track detection', 'Music is open but nothing is playing');
      hint('Press play in Music, then re-run.');
      break;
    default:
      line(tag.fail, 'Track detection', 'could not read the current track');
      hint('Most likely Automation permission was denied. Grant it in');
      hint('System Settings → Privacy & Security → Automation.');
      hardFailure = true;
  }

  // ---- 3. Lyrics lookup ---------------------------------------------
  // Use the live track if we have one; otherwise a known-good fixture so the
  // network path still gets exercised.
  const usingFixture = np.status !== 'ok';
  const query = usingFixture
    ? { title: 'The Nights', artist: 'Avicii', album: 'The Days / Nights', duration: 176 }
    : { title: np.title, artist: np.artist, album: np.album, duration: np.duration };

  if (usingFixture) {
    console.log(`        ${C.dim}(no live track — testing LRCLIB with a known song instead)${C.reset}`);
  }

  try {
    const res = await fetchLyrics(query);
    if (!res || !res.lines.length) {
      line(tag.warn, 'Lyrics lookup', `LRCLIB has no lyrics for “${query.title}”`);
      hint('The network path works, but this particular song isn’t in LRCLIB.');
      hint('Try another track — coverage varies.');
    } else if (res.synced) {
      const first = res.lines.find((l) => l.text) || res.lines[0];
      line(tag.pass, 'Lyrics lookup', `${res.lines.length} synced lines from LRCLIB`);
      hint(`e.g. [${first.time.toFixed(2)}s] “${first.text}”`);
    } else {
      line(tag.warn, 'Lyrics lookup', `only plain (unsynced) lyrics available — ${res.lines.length} lines`);
      hint('The overlay will show them, but without line-by-line timing.');
    }
  } catch (e) {
    line(tag.fail, 'Lyrics lookup', e.message);
    hint('LRCLIB was unreachable. Check your internet connection or a proxy/');
    hint('firewall that might be blocking lrclib.net.');
    hardFailure = true;
  }

  console.log('');
  if (hardFailure) {
    console.log(`${C.red}Some checks failed — see the hints above.${C.reset}\n`);
    process.exit(1);
  }
  console.log(`${C.green}Pipeline looks healthy.${C.reset} Run \`npm start\` to launch the overlay.\n`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
