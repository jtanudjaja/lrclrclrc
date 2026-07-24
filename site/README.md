# site/

The marketing page for lrclrclrc. Plain static files — no build step, no
dependencies, no external requests (fonts are the system stack, the icon PNGs
are extracted from `bundling/icon.icns`).

```
index.html    the page
styles.css    all styling
demo.js       the hero's teleprompter animation
assets/       app icon at 180 / 512 / 1024px
```

Three alternate design directions were tried and dropped — an `.lrc`-file
layout, album liner notes, and a poster-scale karaoke treatment. This one won
for saying plainly what the app does before it tries to be interesting. Worth
remembering if a redesign ever comes up: that's the bar.

## Preview locally

```bash
python3 -m http.server 8000 --directory site
```

Then open <http://localhost:8000>. Opening `index.html` over `file://` works too,
but some browsers won't load the stylesheet that way.

## Publish on GitHub Pages

Deployment is automated by `.github/workflows/pages.yml`. **One-time setup:**
repo **Settings → Pages → Build and deployment → Source: GitHub Actions**. The
older *Deploy from a branch* option ignores the workflow, so it has to be
switched.

After that, any push to `main` that touches `site/**` builds and deploys, and
the site lands at `https://jtanudjaja.github.io/lrclrclrc/`. Pull requests run
the link check but don't deploy. You can also trigger a deploy by hand from the
**Actions** tab (*Deploy site → Run workflow*).

The workflow's `check` job walks every `.html` under `site/` and fails if any
local `href`/`src` points at a file that isn't there — a mistyped stylesheet
path would otherwise deploy cleanly and serve an unstyled page.

## Keeping it honest

The page deliberately does **not** offer a download. The app is unsigned, so a
downloaded build gets quarantined and blocked. Every CTA reads **Install** and
points at the three-line Terminal recipe — framed as installing, not building,
because "build" reads as a project and "install" reads as a Tuesday. If a
signed, notarized release ever exists, that's the moment to add a download
button, and not before.

Every capability claimed on the page is checked against the source, not against
this repo's README — the README has drifted (it still lists *Larger/Smaller*
menu items and a ⌘, that the status menu doesn't have). If you change the menu
(`AppDelegate.setupStatusItem`), the Preferences layout, or the timing offset
steps, update the matching copy:

- the menu mock in the **One menu** section
- the feature grid
- the FAQ

## The demo lyrics

The hero animation shows a fictional track with lines written for this page.
No real lyrics are reproduced — keep it that way.
