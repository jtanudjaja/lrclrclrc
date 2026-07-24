# site/

The marketing page for lrclrclrc. Plain static files — no build step, no
dependencies, no external requests (fonts are the system stack, the icon PNGs
are extracted from `bundling/icon.icns`).

```
index.html    the page
styles.css    all styling
demo.js       the hero's teleprompter animation
robots.txt    crawl policy (open) + sitemap pointer
sitemap.xml   one URL, because there's one page
assets/       app icon at 180 / 512 / 1024px, plus og.png (the share card)
```

Three alternate design directions were tried and dropped — an `.lrc`-file
layout, album liner notes, and a poster-scale karaoke treatment. This one won
for saying plainly what the app does before it tries to be interesting. Worth
remembering if a redesign ever comes up: that's the bar.

## The share card

`assets/og.png` is what Slack, iMessage, Discord, X, and LinkedIn render when
someone posts the link. It's generated, not hand-drawn:

```bash
swift scripts/make-og-image.swift site/assets/og.png
```

The generator reads `--bg`, `--ink`, `--brand` and friends straight out of
`styles.css`, so the card can't drift out of the page's palette. It fails rather
than guessing if a token it wants has been renamed. The wording, though, is
hardcoded in the script — the card repeats the hero's copy, and a page that says
one thing while every link preview says another is the failure mode to watch
for. Change the headline here, change it there.

### It also regenerates itself

`.github/workflows/og-image.yml` runs the command above on `macos-latest` and
commits the result if it differs. It fires on pushes to `main` that touch
`scripts/make-og-image.swift` or `styles.css` — the two inputs the render
actually reads — and on demand from **Actions → OG image → Run workflow**. Every
run uploads the card as an artifact, so a manual run is also how you preview a
change without committing anything.

`index.html` is deliberately *not* a trigger. The copy is baked into the
generator, so editing the page's headline produces a byte-identical card; the
job would run for nothing and the stale wording would survive anyway.

Two things about that workflow are worth knowing before editing it:

- **It verifies before it commits.** A headless runner that can't reach a
  drawing context returns a valid blank rectangle rather than an error, so the
  job checks the dimensions and rejects anything under 50 KB — an all-black
  1200×630 PNG compresses to a couple of KB.
- **It dispatches the Pages deploy by hand.** Commits pushed with
  `GITHUB_TOKEN` don't trigger other workflows (GitHub's loop guard), so a
  regenerated card would sit on `main` and never ship. The last step calls
  `gh workflow run pages.yml` to close that gap.

It's macOS-only — AppKit — so it can't join the ubuntu jobs in `pages.yml`.

Two constraints are load-bearing, and both are easy to undo by accident:

- **The `og:image` and `twitter:image` URLs must be absolute.** Crawlers fetch
  this markup out of context and won't resolve a relative path; a relative one
  doesn't error, it just quietly drops the image and ships a bare text card.
- **The card is 1200×630.** `twitter:card` is `summary_large_image`, which
  expects roughly that ratio. Pointing it back at a square icon gets the icon
  centre-cropped into a letterboxed strip.

The mock overlay on the card is abstract bars, not lettering — same rule as the
hero animation below. No real lyrics anywhere on this page.

## Search

Nobody searches for "lrclrclrc". They search for *lyrics on a Mac*, so the
`<title>` and `<meta name="description">` lead with what the app is rather than
what it's called, and both name Apple Music and Spotify. Keep them inside the
lengths where search results stop truncating:

| | budget | now |
|---|---|---|
| `<title>` | ~65 characters | 65 |
| `<meta name="description">` | ~160 characters | 157 |

Those budgets are really pixel widths, so they're approximate — but a title that
gets cut mid-word looks broken in the one place a stranger first sees the
project.

`canonical` and `og:url` both point at `https://jtanudjaja.github.io/lrclrclrc/`
with the trailing slash. **If a custom domain ever gets attached, they have to
move with it** — a canonical aimed at the old host tells search engines the new
one is a duplicate and hands all of it to a URL nobody links to any more.

### Structured data

The `application/ld+json` block in `<head>` describes the app (`SoftwareApplication`)
and repeats the FAQ (`FAQPage`). Two rules:

- **Only restate what's visible on the page.** That's Google's policy, and it's
  also the thing that keeps this honest. There's deliberately no
  `aggregateRating`, no `downloadUrl` and no version number — the app is
  unsigned with nothing to download, and structured data is exactly where a
  convenient exaggeration would go unread.
- **The FAQ block and the `<details>` list have to say the same thing.** Edit
  one, edit the other. Mismatched markup is worse than none.

### robots.txt and the sitemap

Both exist and both are, for now, mostly decorative: crawlers read `robots.txt`
only from the *origin root*, and on a project Pages site this one is served at
`/lrclrclrc/robots.txt`, which nothing fetches. It's committed so the day this
moves to a custom domain it's already right. Until then, the sitemap has to be
submitted by hand in Google Search Console.

Bump `<lastmod>` in `sitemap.xml` when the page copy meaningfully changes — not
on every deploy, which trains crawlers to ignore it.

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

The workflow's `check` job catches the failures that deploy cleanly and break
quietly. It walks every `.html` under `site/` and fails if:

- a local `href`/`src` points at a file that isn't there — a mistyped
  stylesheet path otherwise serves an unstyled page;
- an absolute URL pointing back at this site (`og:image`, the JSON-LD) points at
  a file that isn't there — these have to be absolute, which puts them out of
  reach of the check above, so a renamed asset breaks share cards with no
  symptom on the page;
- the JSON-LD doesn't parse — one stray comma voids the whole block and nothing
  visible changes;
- `canonical`, `og:image` or the description has gone missing, or `robots.txt` /
  `sitemap.xml` has.

## Keeping it honest

The page deliberately does **not** offer a download. The app is unsigned, so a
downloaded build gets quarantined and blocked. Every CTA reads **Install** and
points at the three-line Terminal recipe — framed as installing, not building,
because "build" reads as a project and "install" reads as a Tuesday. If a
signed, notarized release ever exists, that's the moment to add a download
button, and not before.

Every capability claimed on the page is checked against the source, not against
this repo's README. If you change the menu (`AppDelegate.setupStatusItem`), the
Preferences layout, or the timing offset steps, update the matching copy:

- the menu mock in the **One menu** section
- the feature grid
- the FAQ

## The demo lyrics

The hero animation shows a fictional track with lines written for this page.
No real lyrics are reproduced — keep it that way.
