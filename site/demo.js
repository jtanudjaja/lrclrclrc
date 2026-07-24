/* Hero demo: a teleprompter that behaves like the real overlay — the current
   line is pinned to the exact centre of the stage, neighbours dim out, and the
   whole stack slides rather than the highlight jumping.

   The "song" is fictional and the lines are written for this page. No real
   lyrics are reproduced here. */

(function () {
  const stack = document.getElementById('lines');
  const mbLine = document.getElementById('mbLine');
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
  const els = SONG.map(([, text]) => {
    const el = document.createElement('div');
    el.className = 'line';
    el.textContent = text;
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
      el.classList.toggle('is-current', n === i);
      el.classList.toggle('is-near', Math.abs(n - i) === 1);
    });
    // Pin line i to the stage centre: the stack's top sits at 50%, so shift up
    // by i whole lines plus half of one.
    const h = lineHeight();
    stack.style.transform = `translateY(${-(i * h + h / 2)}px)`;
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
