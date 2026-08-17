# YT Channel Scraper

Paste a YouTube channel URL, get a list of its videos, tick the ones you want, download them.

## Run

```bash
./run.sh
```

Then open http://127.0.0.1:5005

First run creates a `.venv` and installs Flask + yt-dlp. `ffmpeg` must be on your PATH
(`brew install ffmpeg`) — it's needed to merge video+audio and to make mp3s.

## How it works

- **Landing → app** — the page opens as a full-screen dark hero with the logo and search
  bar centred; hitting Scrape collapses the hero into the top bar and drops the results in.
  It's one CSS class swap (`body.landing` → `body.app`); everything that moves is a
  transform, so it animates as one motion instead of re-laying out.
- **Scrape** — `yt-dlp` flat extraction on the chosen channel tab, run in a background
  thread with `process=False` so the entry list stays a lazy generator. Videos stream into
  the page as pages load (~30 per 0.6s) instead of the UI blocking until the whole channel
  is walked — TED's ~5,000 videos would otherwise sit on "Scraping…" for minutes.
  An indeterminate bar under the search field runs while it works (the channel's total
  isn't known until the end, so a percentage would be fiction). The close button in the
  header stops the scrape and resets to a blank landing page — queued downloads are left
  running on purpose.
- **Pagination** — the worker pauses every `PAGE_SIZE` (25) videos and parks on the
  generator, holding its position, until **Load more** asks for the next page. So the
  first page lands in seconds on any channel instead of grinding through thousands of
  entries. Resuming continues where it stopped rather than re-walking the channel.
- **Tabs** — Videos, Shorts and Live map to `/videos`, `/shorts` and `/streams`. Music
  tries `/releases` first (artist channels) and falls back to `/playlists`, since most
  channels have no releases tab at all. Either way those entries are *albums/playlists*
  rather than videos, so entries with `ie_key == "YoutubeTab"` get expanded one level to
  reach the actual tracks. A tab the channel doesn't have yields a plain-English message
  rather than yt-dlp's None.
- **Select** — filter by title, select-all applies to whatever the filter is showing.
- **Download** — 3 worker threads pull from a queue; progress appears in a modal, and the
  Downloads button in the top row keeps a live count while the modal is closed. Each row
  shows a progress ring (SVG `stroke-dashoffset`) that closes as the file arrives, then
  spins, fills, and becomes the save button — it's a real `<a download>` pointing at the
  finished file. Files land in `downloads/`, named `Title [videoid].mp4`.
- **Combined progress** — a merged download is two passes (video stream, then audio),
  each reporting 0-100% of its own file, which made the ring fill twice. Each job probes
  once with `download=False` to read `requested_formats`, then reports downloaded bytes
  against the combined expected size, so it fills exactly once.
- **Retries** — YouTube hands out intermittent `HTTP 403`s on media URLs. Each job
  re-extracts and retries up to 3 times with a backoff; the row shows "hit an error,
  retrying…" while that happens. Most 403s clear on the second attempt.

Quality options map to yt-dlp format strings (`app.py: FORMATS`). "Audio only" produces
192kbps mp3.

## Look

Light theme on white, using YouTube's palette (`#ff0000` red, `#0f0f0f` text, `#606060`
secondary, `#e3e3e3` lines) and Roboto throughout — the same font youtube.com uses for its
interface. The badge is inline SVG, also used as the favicon; swap the paths in
`templates/index.html` to change it. On load it plays the same beat as a finished
download — the ring fills in bursts like a real transfer, then the arrow springs in —
and clicking the badge replays it.

The landing layout centres by transform, which depends on text width, so a webfont
swapping in mid-paint would shift the whole page. First paint is held until
`document.fonts.ready` (with a 1.2s failsafe), and the page canvas is dark so a reload
doesn't flash white. Measured CLS on load: 0.

The Google Fonts `<link>` needs a network connection; offline it falls back to the system
sans and everything still works.

## Notes

- Runs on localhost only, no auth — it's a local tool, don't expose it to a network.
- If a file with the same name is already in `downloads/`, yt-dlp skips the download and
  the row completes instantly — delete the file first to re-fetch at a different quality.
- Job state lives in memory; restarting the server clears the download list (files stay).
- Age-restricted or members-only videos will fail with an error on their row. Passing
  cookies (`"cookiesfrombrowser": ("chrome",)` in the `opts` dict in `_worker`) is the
  usual fix.
- Only download content you have the rights to.
