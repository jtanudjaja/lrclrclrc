/* Hero demo: a teleprompter that behaves like the real overlay — the current
   line is pinned to the exact centre of the stage, neighbours dim out, and the
   whole stack slides rather than the highlight jumping.

   The "song" is fictional and the lines are written for this page. No real
   lyrics are reproduced here. */

(function () {
  const stack = document.getElementById('lines');
  const mbLine = document.getElementById('mbLine');
  const card = document.getElementById('card');
  if (!stack) return;

  // [seconds held, text]
  const SONG = [
    [2.4, 'we drove until the radio gave out'],
    [2.8, 'and the map ran out of names'],
    [2.6, 'you said the quiet part out loud'],
    [3.0, 'and the whole street learned it too'],
    [2.4, '♪'],
    [2.6, 'so keep the window down a while'],
    [2.8, 'let the night do all the talking'],
    [3.0, 'we were never going to sleep tonight'],
    [2.5, 'we were only ever going to drive'],
    [2.4, '♪'],
  ];

  // Build the stack once; only the transform and classes change after this.
  // The inner span is what the karaoke sweep paints: a gradient clipped to the
  // glyphs, slid across them over the life of the line. It needs its own box —
  // the .line is a flex row as wide as the card, and a gradient sized to that
  // would sweep the padding as well as the words.
  const els = SONG.map(([, text]) => {
    const el = document.createElement('div');
    el.className = 'line';
    const inner = document.createElement('span');
    inner.className = 'ln';
    inner.textContent = text;
    el.appendChild(inner);
    stack.appendChild(el);
    return el;
  });

  const lineHeight = () => els[0].getBoundingClientRect().height || 34;

  // Start a few lines in, so the stage opens with context above and below the
  // hero line rather than a half-empty card.
  let i = 3;
  let timer = null;

  function render() {
    els.forEach((el, n) => {
      // The sweep has to finish a little early: a fill that completes exactly
      // as the line changes never looks finished, it looks cut off.
      if (n === i) el.style.setProperty('--sweep', (SONG[i][0] * 0.88).toFixed(2) + 's');
      el.classList.toggle('is-current', n === i);
      el.classList.toggle('is-near', Math.abs(n - i) === 1);
    });
    // Pin line i to the stage centre: the stack's top sits at 50%, so shift up
    // by i whole lines plus half of one.
    const h = lineHeight();
    stack.style.transform = `translateY(${-(i * h + h / 2)}px)`;

    // Album art drifts through a hue per line, and the card takes a matching
    // bloom off it — the way a real overlay picks up colour from the artwork.
    // Unitless: the CSS multiplies it by 1deg in one place and reads it as a
    // bare hue angle in the other.
    // Kept inside ±60°: a full rotation sends the artwork through greens and
    // yellows that read as a bug rather than as a different album.
    if (card) card.style.setProperty('--hue', ((i * 47) % 120) - 60);

    document.dispatchEvent(new CustomEvent('lrc:line', {
      detail: { index: i, text: SONG[i][1], hold: SONG[i][0] }
    }));

    if (mbLine) mbLine.textContent = '♫  ' + SONG[i][1];
  }

  function advance() {
    i = (i + 1) % SONG.length;
    render();
    schedule();
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(advance, SONG[i][0] * 1000);
  }

  render();

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
  const paused = () => document.hidden || reduced.matches;

  function sync() {
    if (paused()) clearTimeout(timer);
    else schedule();
  }

  document.addEventListener('visibilitychange', sync);
  reduced.addEventListener('change', sync);
  window.addEventListener('resize', render);
  sync();
})();
