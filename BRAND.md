# Brand

The single source of truth for what this app is called, what it claims, and how
it sounds. Copy lives in a dozen places — the page, the share card, this repo's
README, the first-run wizard, the menu — and the failure mode is all of them
saying *almost* the same thing. Change wording here first, then walk the
[surface map](#surface-map).

---

## The name

**lrclrclrc.** Lowercase, one word, nine letters, no spaces.

`.lrc` is the file format that pairs a lyric line with the moment it's sung —
it's what LRCLIB returns and what `LRCParser.swift` reads. The name is that
extension three times, once for each job the app does:

| | |
|---|---|
| **lrc** | know what's playing |
| **lrc** | find the words |
| **lrc** | put them on screen |

Three is the spine of the whole identity, and it wasn't imposed — it was already
there in the source before anything was written about it:

- **three bars in the icon**, the middle one lit — the product in one mark
- **three moving parts** in the architecture (`MusicWatcher`, `LyricsService`,
  `OverlayPanel`)
- **three lines** to install
- **three places** to show lyrics — Overlay, Menu Bar, Hidden

Reach for the three when a section needs a shape. Don't force it where there
isn't one.

### How you say it

You don't. It's a thing you type, not a thing you say — which is the honest
answer and a better one than a phonetic spelling nobody would use. If someone
genuinely needs to read it aloud: *"L-R-C, three times."*

Never write it as **LRCLRCLRC**, **LrcLrcLrc**, **Lrclrclrc**, or **lrc³**. It
stays lowercase even at the start of a sentence — so rewrite the sentence rather
than capitalizing it. The one exception is the macOS menu item macOS builds for
us (**Quit lrclrclrc**), which is already correct.

---

## Who it's for

One person. Every line on every surface is written to them, and when two
phrasings compete, the tiebreaker is which one they'd recognize.

**They're working, with music on.** At their Mac — code, email, a spreadsheet.
Not a performer, not a passive listener. Someone who sings along.

**A song they love comes on.** They know the chorus cold. Verse two is a mumble,
a hum, a guess. The song ends having been background instead of an event.

**The words are locked in the Music app.** Getting them means leaving what
they're doing — so they don't, and the moment passes.

That last sentence is the entire product thesis, and it's why the copy is shaped
the way it is. **This person does not have a window-layering problem.** They
have a *the song ended and I mumbled through it* problem. Sell the second thing.
Everything about floating, panels, Spaces and z-order is the answer to a
question they never asked — true, necessary, and belonging further down the page.

## What we say

Four fixed pieces. Everything else is written fresh; these four are copied.

### Tagline

> **Never miss the lyrics.**

One tagline. It goes on the hero, the share card, and the README, and it doesn't
get paraphrased into "never miss a word", "never miss a line", or "always know
the lyrics". Those are four brands, not one.

It replaced *"Lyrics that float over everything"*, and the reason is worth
keeping: the old line described the window, this one describes what keeps
happening to you. It also contains the word **lyrics**, which the old one did
not — on a link preview in a thread, that single noun is the difference between
a stranger knowing what this is and not.

One risk to hold in mind if it's ever revisited: *never miss a ___* is a worn
construction, and on a music product it sits a syllable away from *never miss a
beat*. It earns its place by being specific about the loss, so don't loosen it
into something vaguer.

### Descriptor — the "what is it" sentence

**This is where mechanism lives, and that's not a contradiction of rule 1.** The
tagline poses the problem; the descriptor sitting directly beneath it answers
"…okay, how?" for the reader who's now interested enough to ask. Floating,
panels, syncing and Spaces all belong here. They just don't belong first.

Three lengths, picked by the space available, never re-improvised. **The noun is
"menu-bar app"** — one noun, all three tiers. *Overlay* and *card* describe the
thing on screen, never the product itself.

- **Short** (≤ 60 chars) — *A menu-bar lyrics app for Apple Music and Spotify.*
  For the places that give you one line and no layout control: the GitHub repo's
  **About** field, a directory entry, a social bio. It carries no tagline,
  because in those slots the reader hasn't opted in to anything yet and needs
  the category before the pitch.
- **Standard** — *A macOS menu-bar app that shows time-synced lyrics for Apple
  Music and Spotify in a translucent card that floats above your other windows.*
- **Long** — the hero lede: *lrclrclrc watches whatever Apple Music or Spotify
  is playing, pulls time-synced lyrics, and highlights each line in a
  translucent card that stays above your other apps — across Spaces and
  full-screen windows.*

### The noun is absolute. The shape is not.

These are two different rules and they used to be muddled together as one
"exemption", which is how *overlay* survived on four tags for as long as it did.
Kept apart, neither one leaks:

**Vocabulary — no exceptions, anywhere.** The product is a **menu-bar app**. Not
an overlay, not a widget, not a tool. This holds on every surface including the
ones written for machines and strangers: `<title>`, `og:`, `twitter:`, JSON-LD,
the repo's About field. If a new surface appears, it uses this noun. There is no
slot where a second noun is allowed, because every such slot is how the first
inconsistency got in.

The one thing this rule does *not* cover is prose about the **category** —
"a lyrics overlay is really three separate jobs" is a claim about that class of
software, not a name for this one, and it stays. The test isn't grammatical,
it's about meaning: **substitute "lrclrclrc" and see whether the sentence still
says the same thing.** If it now makes a narrower claim than it did, the phrase
was describing the category and it's fine. If it says the same thing, the phrase
was naming the product, and it's the wrong noun.

**Shape — varies by who's reading.** Whether a surface opens with the *tagline*
or with the *category* depends entirely on whether the reader has opted in yet:

| | Opens with | Because |
|---|---|---|
| hero, share-card art, README | the **tagline** | they chose to be here; lead with the problem |
| `<title>`, `og:`/`twitter:` titles, repo About | the **category** | a search result or a link preview in someone else's thread — they haven't opted in, and have about a second to learn what this is |

That's why the page `<title>` leads with *what the app is* rather than "Never
miss the lyrics" — nobody searches for "lrclrclrc", they search for lyrics on a
Mac. See [`site/README.md`](site/README.md#search). Same for the preview titles:
the card art is already carrying the tagline in 70pt type right beside them, so
the words underneath do the other job.

Category-shaped is not licence to invent a third descriptor. Those surfaces use
the descriptor tiers above, verbatim.

### The trio

> **macOS · menu bar · free and open source**

The eyebrow above the hero and the footer line on the share card. Middot with
spaces, no serial anything, no fourth item. "MIT" belongs in the footer and the
README badge, where a licence is actually actionable — not in the trio, where it
reads as jargon to the person deciding whether to bother.

### The sign-off

> **Never miss another chorus.**

The closing line. Deliberately the same construction as the tagline, so the page
is bookended: it opens on the plain, category-naming version of the problem and
closes on the specific, slightly wistful one. *Lyrics* is what you'd type into a
search box; *another chorus* is what you actually lost.

Once per surface, at the end. It is not a second tagline, and the echo only
works because there are exactly two of them — a third "never miss…" anywhere on
the page turns a device into a tic.

*(It replaced "Put the words back on screen", which is still a good line and
still in the git history if the bookend ever reads as repetition rather than
composition.)*

---

## How it sounds

Four rules, in priority order. When two collide, the lower number wins.

**1. Name the problem, not the mechanism.** This is the one that decides
headlines. Every early draft of the tagline described the software — *floats*,
*overlay*, *stays above*, *time-synced* — and every one of them was answering a
question nobody asked. **The reader doesn't have a window-layering problem. They
have a "the song ended and I mumbled through it" problem.** Write the second
thing. The mechanism has a home directly underneath, in the lede, where someone
who's already interested will read it.

A quick test for any headline: cross out every word that describes the software.
If what's left is nothing, start again.

**2. Say the thing, then be interesting.** Three alternate designs for the page
were built and dropped — an `.lrc`-file layout, album liner notes, a poster-scale
karaoke treatment — and the plain one won for naming what the app does before it
tried to be clever. That's the bar for copy too. A heading that's a pun the
reader has to decode is a heading that failed.

**3. Name the trade-off before someone else does.** There's no download, sync
quality varies by song, and it's a personal project with no support promised.
All three are on the page, in the reader's words, above the fold of the FAQ. An
objection you raise yourself reads as confidence; the same objection found in a
comment thread reads as a cover-up.

**4. Small words, real numbers.** ±0.25 s. 1 Hz, extrapolated to ~10 fps. Three
lines. About a minute. macOS 13 Ventura or later. Numbers are the texture here —
they're what make "it's fast" unnecessary to write.

### Never

No **seamless**, **beautiful**, **magical**, **effortless**, **powerful**,
**blazing**, **just works**, **game-changing**. No exclamation marks. No "we" —
there is no we, and the first person singular only shows up in the licence. No
feature described in the future tense as though it exists.

---

## Vocabulary

Same thing, same word, every time. Half the drift on a page like this is
synonym drift.

| Use | Not |
|---|---|
| the overlay, the card | the widget, the HUD, the popup, the window |
| the menu bar, the ♫ | the tray, the systray, the status bar |
| time-synced lyrics | synced-up, live, real-time, synchronised lyrics |
| menu-bar app *(adj)* · the menu bar *(noun)* | menubar |
| Apple Music | iTunes, the Music app *(except where macOS names it)* |
| Spotify — the desktop app | the Spotify client |
| Install | Download, Get, Build, Grab |
| free and open source | freeware, FOSS, 100% free, gratis |
| macOS 13 Ventura or later | macOS 13+, Ventura+, 13.0+ *(shields.io badges are exempt — the label is width-bound)* |
| Spaces, full-screen apps | desktops, virtual desktops |
| LRCLIB | lrclib, LRCLib *(the URL is lowercase; the name isn't)* |
| US spelling — color, capitalize | colour, capitalise |

**Don't uppercase a wordmark.** `text-transform: uppercase` turns *macOS* into
*MACOS*, and the lowercase m is the entire point of it. The hero eyebrow is set
in sentence case with tracking for exactly this reason. Chips that mirror
something the app itself uppercases — the overlay's source chip — are the one
place it's allowed, because there the page is quoting the product.

Menu items, preference labels and keyboard shortcuts are quoted **exactly** as
they appear in the app, in bold: **Show Lyrics In**, **Find Lyrics…** (⌘L),
**Click-Through (ignore mouse)**. If the menu changes, the copy is wrong until
it's changed too.

---

## How it looks

Defined once in [`site/styles.css`](site/styles.css) and read from there by the
share-card generator, so there is exactly one copy of every hex.

| Token | | Role |
|---|---|---|
| `--bg` | `#08090c` | Page. Dark by commitment — the product is a translucent card over dark desktops, and the page is the same material. |
| `--ink` | `#eef1f7` | Body text |
| `--ink-dim` | `#a2abbd` | Ledes, secondary |
| `--ink-faint` | `#6b7488` | Fine print |
| `--brand-deep` | `#1c2133` | Icon gradient, dark stop |
| `--brand` | `#3370d1` | Icon gradient, light stop · focus · CTA |
| `--brand-lit` | `#7fb2f5` | Links, the lit line, the second half of the headline |

**Never hard-code a hex.** `scripts/make-og-image.swift` parses these tokens out
of the stylesheet and `fatalError`s if one is renamed, which is deliberate — a
share card that silently renders in last season's blue is worse than one that
doesn't render.

**Type** is the system stack (`-apple-system`, SF Pro), never a webfont. No
network requests leave the page, which matches an app that talks to exactly one
server.

**The mark** is a squircle tile (22.37% corner radius) with a −55° gradient and
three bars — 50%, 100%, 35% opacity, middle one lit. It is generated by
`scripts/make-icon.swift`, not drawn by hand. Don't crop it, don't put it on a
light background, don't set the wordmark in anything but the system sans at
semibold with `-0.6` kerning.

**Motion** always degrades to static. Every animation is gated behind
`prefers-reduced-motion` on the page and macOS's reduce-motion setting in the
app. This is a brand property, not just an accessibility box: the product's
entire pitch is that it sits on screen for hours without demanding anything.

---

## Two things we don't do

**No lyrics anywhere in this repo.** Not on the page, not on the share card, not
in an issue, not in a screenshot. The hero demo is a fictional song written for
it; the card's overlay mock is abstract bars, not lettering. The app fetches
lyrics at runtime and stores none of them, and the marketing has to be able to
say that without an asterisk.

**No download button until there's something safe to download.** The app is
unsigned, so a downloaded build gets quarantined and blocked. Every CTA reads
**Install** and points at the three-line Terminal recipe — *installing*, not
*building*, because "build" reads as a project and "install" reads as a Tuesday.
The day a signed, notarized release exists is the day that changes, and not
before.

---

## Surface map

Every place the four fixed pieces appear. Change one, change the row.

| Surface | Carries |
|---|---|
| [`site/index.html`](site/index.html) — hero | trio · tagline · long descriptor |
| [`site/index.html`](site/index.html) — `og:`/`twitter:` tags | category-shaped descriptor · settled noun |
| [`site/index.html`](site/index.html) — JSON-LD | the FAQ, verbatim — it must match the `<details>` list word for word |
| [`site/index.html`](site/index.html) — closer | sign-off |
| [`scripts/make-og-image.swift`](scripts/make-og-image.swift) | tagline · standard descriptor · trio |
| [`README.md`](README.md) | tagline · standard descriptor |
| `Sources/lrclrclrc/OnboardingView.swift` | outcome-first welcome · the tagline's echo on the final step |
| `Sources/lrclrclrc/AppDelegate.swift` | menu item names — the vocabulary's source of truth |
| **GitHub repo → About** | short descriptor · homepage URL · topics |

The repo's **About** field is the one surface here that isn't a file, so nothing
in a diff will ever remind you it exists — and for a project installed by
`git clone`, it's the first thing most people read. It sat empty for the whole
life of the project. Set it with `gh`, not the web UI, so the wording is
reviewable:

```bash
gh repo edit \
  --description "A menu-bar lyrics app for Apple Music and Spotify." \
  --homepage "https://jtanudjaja.github.io/lrclrclrc/"
```

The share card is the one that goes stale silently: its wording is compiled into
the generator, so editing the page's headline leaves every link preview quoting
the old one. `.github/workflows/og-image.yml` re-renders the card on any push to
`main` that touches the generator or the stylesheet — but it can't know the
*page* changed. That check is human.
