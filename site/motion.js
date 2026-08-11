/* lrclrclrc — page motion.

   One idea runs through all of it: the page behaves like the thing it's
   selling. Read position is a scrubber, headings arrive the way lyric lines
   do, colour blooms behind the hero the way album art blooms on a desktop,
   and the menu bar keeps time with the demo playing in the hero.

   Everything here is additive. The <head> bootstrap only sets `html.motion`
   when the browser has JS and the reader hasn't asked for reduced motion, and
   the CSS hides nothing outside that class — so if this file never loads, the
   page is simply the static page. `data-motion="on"` is the receipt that tells
   the bootstrap's load-time check to leave the class alone.

   No dependencies, no build step. Same as everything else in site/. */

(function () {
  'use strict';

  const root = document.documentElement;
  if (!root.classList.contains('motion')) return;
  if (!('IntersectionObserver' in window)) { root.classList.remove('motion'); return; }
  root.dataset.motion = 'on';

  // Pointer-driven flourishes are for pointers. A finger has no hover state,
  // and running them on touch means a tilt that sticks where you last tapped.
  const fine = matchMedia('(hover: hover) and (pointer: fine)');

  const on = (el, ev, fn, opts) => el && el.addEventListener(ev, fn, opts);

  /* ─────────────────────────  1. REVEAL  ─────────────────────────
     Elements come in once and are then forgotten — unobserving is what keeps
     this from being a scroll handler that runs for the life of the page. */

  const revealed = new IntersectionObserver((entries, obs) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('in');
      obs.unobserve(e.target);
    }
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

  document.querySelectorAll('[data-reveal]').forEach(el => revealed.observe(el));

  document.querySelectorAll('[data-stagger]').forEach(group => {
    Array.prototype.forEach.call(group.children, (el, n) => {
      // Capped: a twelve-card grid with a linear ramp would leave the last card
      // arriving most of a second after the first, which reads as broken.
      el.style.setProperty('--d', Math.min(n, 7) * 65 + 'ms');
      revealed.observe(el);
    });
  });

  /* ───────────────────  2. LIVE: don't animate offscreen  ───────────────────
     Blurred blobs and pulsing shadows are the expensive kind of pretty. The
     CSS pauses them unless the element carries .live, and this is what grants
     it — so at most the section you're actually looking at is animating. */

  const liveness = new IntersectionObserver(entries => {
    for (const e of entries) e.target.classList.toggle('live', e.isIntersecting);
  }, { rootMargin: '80px' });

  document.querySelectorAll('.aurora, .hero-demo').forEach(el => liveness.observe(el));

  /* ─────────────────────  3. THE SCRUBBER  ─────────────────────
     --scroll drives the fill under the nav, and .scrolled condenses the bar
     itself. rAF-coalesced because scroll fires far faster than we paint. */

  const scrollDepth = () => {
    const span = root.scrollHeight - innerHeight;
    return span > 0 ? Math.min(1, Math.max(0, scrollY / span)) : 0;
  };

  let queued = false;
  function onScroll() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      root.style.setProperty('--scroll', scrollDepth().toFixed(4));
      root.classList.toggle('scrolled', scrollY > 12);
      queued = false;
    });
  }
  on(window, 'scroll', onScroll, { passive: true });
  on(window, 'resize', onScroll);
  onScroll();

  /* Which section you're in, lit in the nav — the same playhead idea, one
     level up from the scrubber. */
  const navLinks = new Map();
  document.querySelectorAll('.nav-links a[href^="#"]').forEach(a => {
    const target = document.getElementById(a.hash.slice(1));
    if (target) navLinks.set(target, a);
  });
  if (navLinks.size) {
    const here = new IntersectionObserver(entries => {
      for (const e of entries) {
        const link = navLinks.get(e.target);
        if (link) link.classList.toggle('is-active', e.isIntersecting);
      }
    }, { rootMargin: '-45% 0px -50% 0px' });
    navLinks.forEach((_, section) => here.observe(section));
  }

  /* ─────────────────  4. HERO DEMO: tilt and parallax  ─────────────────
     The fake desktop leans toward the cursor and the lyric card slides a few
     pixels against the lean, which is the whole trick — the card reads as
     floating in front of the desktop rather than printed on it. */

  const demo = document.querySelector('.hero-demo');
  const desktop = demo && demo.querySelector('.desktop');
  const lyricCard = demo && demo.querySelector('.card');

  if (desktop && fine.matches) {
    let raf = 0;

    const settle = () => {
      desktop.classList.remove('tracking');
      desktop.style.setProperty('--rx', '0deg');
      desktop.style.setProperty('--ry', '0deg');
      if (lyricCard) {
        lyricCard.style.setProperty('--tx', '0px');
        lyricCard.style.setProperty('--ty', '0px');
      }
    };

    on(demo, 'pointermove', e => {
      if (e.pointerType !== 'mouse' || raf) return;
      raf = requestAnimationFrame(() => {
        raf = 0;
        const r = desktop.getBoundingClientRect();
        const dx = (e.clientX - r.left) / r.width * 2 - 1;   // −1 … 1
        const dy = (e.clientY - r.top) / r.height * 2 - 1;
        desktop.classList.add('tracking');
        desktop.style.setProperty('--ry', (dx * 5.5).toFixed(2) + 'deg');
        desktop.style.setProperty('--rx', (-dy * 4.5).toFixed(2) + 'deg');
        if (lyricCard) {
          lyricCard.style.setProperty('--tx', (dx * 9).toFixed(1) + 'px');
          lyricCard.style.setProperty('--ty', (dy * 6).toFixed(1) + 'px');
        }
      });
    });

    on(demo, 'pointerleave', settle);
    on(window, 'blur', settle);
  }

  /* ─────────────────  5. CARDS: a light under the cursor  ─────────────────
     Each card's ::before is a radial glow parked at --mx/--my. Opacity is
     :hover's job in CSS; all this does is move the light. */

  if (fine.matches) {
    document.querySelectorAll('.feat, .steps li, .install-card, .note').forEach(card => {
      on(card, 'pointermove', e => {
        const r = card.getBoundingClientRect();
        card.style.setProperty('--mx', ((e.clientX - r.left) / r.width * 100).toFixed(1) + '%');
        card.style.setProperty('--my', ((e.clientY - r.top) / r.height * 100).toFixed(1) + '%');
      });
    });

    /* Buttons lean toward the cursor while it's over them. Three pixels and
       two: enough that the button feels answerable, not enough to move the
       target out from under the click. */
    document.querySelectorAll('.btn').forEach(btn => {
      on(btn, 'pointermove', e => {
        const r = btn.getBoundingClientRect();
        btn.style.setProperty('--bx', (((e.clientX - r.left) / r.width - .5) * 3).toFixed(1) + 'px');
        btn.style.setProperty('--by', (((e.clientY - r.top) / r.height - .5) * 2).toFixed(1) + 'px');
      });
      on(btn, 'pointerleave', () => {
        btn.style.setProperty('--bx', '0px');
        btn.style.setProperty('--by', '0px');
      });
    });
  }

  /* ───────────────  6. MENU MOCK: someone walking the menu  ───────────────
     The static screenshot of a menu says what's in it. A highlight moving down
     it, stopping to tick Click-Through on, says what it's like to use. */

  const mock = document.getElementById('menuMock');
  if (mock) {
    const rows = Array.prototype.slice.call(mock.querySelectorAll('.mm-row'));
    const check = document.getElementById('mmClickThrough');
    const clickThroughRow = check && check.closest('.mm-row');
    let at = -1, timer = 0, running = false;

    function step() {
      if (at >= 0 && rows[at]) rows[at].classList.remove('is-hot');
      at = (at + 1) % (rows.length + 3);   // a few beats of nothing, then round again
      const row = rows[at];
      if (row) {
        row.classList.add('is-hot');
        // Landing on Click-Through toggles it, because that's what you'd do.
        if (row === clickThroughRow && check) {
          check.textContent = check.textContent ? '' : '✓';
          check.classList.add('pop');
          setTimeout(() => check.classList.remove('pop'), 320);
        }
      }
      timer = setTimeout(step, row ? 900 : 1400);
    }

    const watch = new IntersectionObserver(entries => {
      const visible = entries[0].isIntersecting;
      if (visible && !running) { running = true; timer = setTimeout(step, 600); }
      else if (!visible && running) {
        running = false;
        clearTimeout(timer);
        if (rows[at]) rows[at].classList.remove('is-hot');
        at = -1;
      }
    }, { threshold: 0.35 });
    watch.observe(mock);

    // A real pointer beats the demo: stop performing the moment someone
    // reaches for it, and don't start again.
    on(mock, 'pointerenter', () => {
      running = true;                       // blocks the observer restarting it
      clearTimeout(timer);
      watch.disconnect();
      if (rows[at]) rows[at].classList.remove('is-hot');
    });
  }

  /* ─────────────────  7. THE COMMANDS TYPE THEMSELVES  ─────────────────
     Install is the one instruction on the page, so it gets the one flourish
     that's about instruction: the block writes itself out, once, when you
     first reach it. The height is pinned before the text is cleared, or the
     section collapses and the page jumps out from under you. */

  document.querySelectorAll('pre[data-type]').forEach(pre => {
    const code = pre.querySelector('code');
    if (!code) return;
    const full = code.textContent;

    const typeOut = () => {
      pre.style.minHeight = pre.getBoundingClientRect().height + 'px';
      code.textContent = '';
      pre.classList.add('typing');

      let n = 0;
      (function tick() {
        // One character at a time at roughly the speed someone types a command
        // they already know: about a second and a half for all three lines.
        // Faster and it's a flicker rather than a demonstration; slower and
        // the section stalls while you wait for a URL you weren't reading.
        // The beat at each newline is the pause before pressing return.
        n += 1;
        code.textContent = full.slice(0, n);
        if (n < full.length) {
          setTimeout(tick, full[n - 1] === '\n' ? 220 : 17);
        } else {
          setTimeout(() => pre.classList.remove('typing'), 1400);
        }
      })();
    };

    const watch = new IntersectionObserver((entries, obs) => {
      if (!entries[0].isIntersecting) return;
      obs.disconnect();
      typeOut();
    }, { threshold: 0.6 });
    watch.observe(pre);
  });

  /* ───────────────────────  8. FAQ: answers unfold  ───────────────────────
     <details> snaps open natively. This animates the height instead, which
     means intercepting the close so the element is still open while it
     collapses. Heights are measured, not guessed, so a reflowed answer at any
     width still lands exactly on its own content. */

  const EASE = { duration: 320, easing: 'cubic-bezier(.22,.8,.3,1)' };

  document.querySelectorAll('.faq details').forEach(d => {
    const body = d.querySelector('p');
    const summary = d.querySelector('summary');
    if (!body || !summary) return;
    let playing = null;

    // Both keyframes are always spelled out in pixels: an implicit from-frame
    // would start at height:auto, which doesn't interpolate. The bottom
    // padding travels with the height because the global border-box sizing
    // floors a box at its own padding — animate height alone and the answer
    // collapses to a 19px ledge instead of to nothing.
    const shut = h => ({ height: h, paddingBottom: '0px', opacity: 0 });
    const open = h => ({ height: h, paddingBottom: getComputedStyle(body).paddingBottom, opacity: 1 });

    on(summary, 'click', e => {
      e.preventDefault();
      if (playing) playing.cancel();
      body.style.overflow = 'hidden';

      if (d.open) {
        const from = open(body.getBoundingClientRect().height + 'px');
        playing = body.animate([from, shut('0px')], EASE);
        playing.onfinish = () => { d.open = false; body.style.overflow = ''; playing = null; };
      } else {
        d.open = true;
        playing = body.animate([shut('0px'), open(body.scrollHeight + 'px')], EASE);
        playing.onfinish = () => { body.style.overflow = ''; playing = null; };
      }
    });
  });

  /* ─────────────────  9. THE PAGE KEEPS TIME WITH THE DEMO  ─────────────────
     demo.js emits `lrc:line` every time the teleprompter advances, and the
     menu-bar meter borrows that beat so the two halves of the hero read as one
     song rather than two widgets.

     The brand mark used to pulse on this event too. It doesn't any more: the
     logo is the one element on the page that is always in view, so a twitch
     every ~2.6s was motion the reader could never look away from. The meter is
     inside the demo, which is the part that's supposed to be performing. */

  const eq = document.getElementById('eq');

  on(document, 'lrc:line', () => {
    if (eq) {
      eq.classList.remove('hit');
      void eq.offsetWidth;              // restart the animation, not resume it
      eq.classList.add('hit');
      setTimeout(() => eq.classList.remove('hit'), 300);
    }
  });
})();
