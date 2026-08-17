<div align="center">

<img src="docs/logo.svg" alt="YT Channel Scraper" width="104">

# YT Channel Scraper

**Browse any YouTube channel's back catalogue in one list, tick the videos you want, and download them in a batch.**

A small local web app — Flask + [yt-dlp](https://github.com/yt-dlp/yt-dlp) — that runs on your own machine.
No account, no API key, no cloud.

<img src="docs/01-landing.jpg" alt="Landing page" width="820">

</div>

---

## Why

`yt-dlp` is excellent, but grabbing *a few specific videos* from a channel means either downloading
everything or copying URLs one at a time. This puts the channel in front of you as a browsable list —
thumbnails, durations, view counts — so you can pick.

## What you get

| | |
|---|---|
| **Whole channel, one list** | Videos, Shorts, Live streams or Music, with thumbnails, durations and view counts |
| **Results while you wait** | Videos stream into the page as they're found, not after the whole channel is walked |
| **Paged** | 25 at a time, so the first page lands in seconds even on a 5,000-video channel |
| **Batch download** | Tick as many as you like; 3 download at a time with live per-video progress |
| **Quality choice** | Best available, 1080p, 720p, 480p, or audio-only as 192 kbps mp3 |
| **Resilient** | Automatically retries YouTube's intermittent `403`s, which are common and usually transient |

<img src="docs/02-results.jpg" alt="Scraped channel with videos selected" width="900">

## Install

Needs **Python 3.9+** and **ffmpeg** (to merge video + audio and to make mp3s):

```bash
brew install ffmpeg          # macOS — or apt install ffmpeg, etc.

git clone https://github.com/d4vid4nderson/yt-channel-scrapper.git
cd yt-channel-scrapper
./run.sh
```

`run.sh` creates a virtualenv and installs Flask + yt-dlp on first run, then starts the app at
**http://127.0.0.1:5005**.

## Use it

1. Paste a channel URL — `https://www.youtube.com/@channelname`, a bare `@handle`, or a playlist URL.
2. Pick the type: **Videos**, **Shorts**, **Live** or **Music**.
3. **Scrape.** Results stream in; **Load 25 more** pulls the next page.
4. Tick what you want (filter by title, or **Select all**), choose a quality, **Download selected**.
5. Progress appears in the Downloads panel. Finished files land in `downloads/`, named
   `Title [videoid].mp4`, and each row's progress ring turns into a save button.

<img src="docs/03-downloads.jpg" alt="Downloads modal" width="820">

<img src="docs/04-tabs.jpg" alt="Channel type dropdown" width="820">

## How it works

- **Scraping** uses yt-dlp flat extraction with `process=False`, so the entry list stays a lazy
  generator and videos can be pushed to the page as pages load (~30 per 0.6s) rather than after the
  entire channel has been walked.
- **Pagination** pauses the worker every 25 videos *while holding its place in that generator*, so
  **Load more** continues where it stopped instead of re-walking the channel.
- **Music** tries `/releases` (artist channels) and falls back to `/playlists`. Both list albums
  rather than videos, so those entries get expanded one level to reach the actual tracks.
- **Progress** is combined across streams. A merged download is two passes — video, then audio —
  each reporting 0–100% of its own file, which would fill the bar twice. Each job probes once to
  read `requested_formats`, then reports bytes against the combined total, so it fills once.
- **Retries**: every job re-extracts and retries up to 3 times with a backoff.
- **Downloads panel** shows as a centred modal over the results list, and as a bottom
  drawer on the landing page where there's no list behind it to sit over.

Quality presets are yt-dlp format strings in `FORMATS` (`app.py`) if you want to change them.

## Notes and limits

- **Local only.** It binds to `127.0.0.1` and has no authentication — don't expose it to a network.
- Job state is in memory: restarting the server clears the download list. The files stay.
- If a file of the same name already exists in `downloads/`, yt-dlp skips it and the row completes
  instantly. Delete it first to re-fetch at a different quality.
- Age-restricted and members-only videos will fail on their row. The usual fix is passing browser
  cookies — add `"cookiesfrombrowser": ("chrome",)` to the `opts` dict in `_worker`.
- Only download content you have the rights to. Respect YouTube's Terms of Service and copyright.

## Layout

```
app.py                 Flask app: scrape/pagination endpoints, download queue, worker threads
templates/index.html   Whole front end — markup, CSS and JS in one file, no build step
run.sh                 Creates the venv on first run, then starts the app
downloads/             Where finished files land (gitignored)
```

## Built with

[Flask](https://flask.palletsprojects.com/) · [yt-dlp](https://github.com/yt-dlp/yt-dlp) ·
[ffmpeg](https://ffmpeg.org/) · vanilla JS and CSS, no framework
