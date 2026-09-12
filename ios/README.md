# YT Channel Scraper for iOS

The Mac app, rebuilt for iPhone and iPad.

Not a port in the usual sense. The Mac app's entire working core is four vendored
binaries driven through `Process` — `yt-dlp` for extraction, `ffmpeg` and `ffprobe` for
muxing, `deno` for YouTube's JavaScript challenge. None of that can exist on iOS:
`Process` is not in the SDK, and the sandbox refuses to exec anything the app did not
ship signed. So the UI moved and **the engine was rewritten**, natively, in Swift.

| The Mac does this | iOS does this instead |
|---|---|
| `yt-dlp --flat-playlist --dump-json` | `Sources/Engine/` — YouTube's InnerTube API, called directly |
| `yt-dlp -f …` to pick and fetch streams | `StreamResolver` + `Transfer` (background `URLSession`) |
| vendored `ffmpeg` to mux | `Muxer` — `AVMutableComposition` + passthrough export |
| vendored `ffmpeg` + lame for mp3 | `Muxer.extractAudio` — passthrough to **m4a**, no re-encode |
| vendored `deno` for the JS challenge | `JSChallenge` — JavaScriptCore (see *Known limits*) |
| `~/Downloads/YT Channel Scraper` | `Documents/`, visible in the Files app |
| Three side drawers, ⌘1/⌘2/⌘3 | Three tabs |

Nothing under `mac/` is modified. The iOS target compiles the Mac package's `Model/`,
`Core/Log.swift`, `Core/LibraryArchive.swift` and `Views/Palette.swift` **in place** —
they carry no AppKit — and everything iOS needs on top of them is an extension. A
mistake here cannot break the shipping Mac app. A `.ytcslibrary` exported on one opens
on the other.

---

## Build it

You need a Mac with Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The project is generated from `project.yml` rather than
checked in, because the iOS target deliberately compiles files that live in `mac/` and
expressing that as one line of YAML is far less fragile than the file-reference soup
Xcode would write for it.

```sh
cd ios
cp Local.xcconfig.example Local.xcconfig   # then put your team id in it
./make-icon.sh                             # rasterises the 1024 app icon, once
xcodegen generate
open YTChannelScraper.xcodeproj
```

`Local.xcconfig` is gitignored so the repo does not carry a team id around. Find yours
at developer.apple.com → Membership. If `com.moregroup.ytchannelscraper` is taken on
your account, change `PRODUCT_BUNDLE_IDENTIFIER` in the same file.

`make-icon.sh` needs no Homebrew — it falls back to rendering the SVG in a `WKWebView`,
which every Mac has. It flattens the result onto opaque black, because App Store Connect
rejects an app icon with an alpha channel.

## Get it onto a phone

**Just your own devices** — no App Store Connect, no review, nothing to wait for. Plug
the phone in, pick it as the run destination, press ⌘R. With a paid developer account
the build stays valid for a year; with a free Apple ID, seven days, then re-run.

**TestFlight, internal** — up to 100 testers, but every one of them has to be a user on
your App Store Connect team. No Beta App Review: the build only has to pass automated
validation.

1. App Store Connect → Apps → **+** → New App. Pick the bundle id, give it a name and
   an SKU.
2. Xcode → any iOS device as destination → Product → **Archive**.
3. In the Organizer: **Distribute App** → **TestFlight & App Store** → Upload.
4. Wait for processing (a few minutes), then App Store Connect → TestFlight → Internal
   Testing → add your testers.

Bump `CFBundleVersion` in `project.yml` for every upload; App Store Connect rejects a
build number it has seen before.

**External TestFlight or the App Store — don't plan on it.** External testing requires
Beta App Review, and an app that downloads YouTube videos is among the most reliably
rejected categories there is: App Review Guideline 5.2.3, plus YouTube's own terms.
Internal TestFlight and direct install are the realistic distribution routes, which is
what this app is set up for.

---

## Known limits

These are real, measured, and deliberately written down rather than discovered later.

### The player endpoint is behind a bot wall

Listing a channel and searching for one work, and are verified against live YouTube —
run `Tools/check-renderers.py`. **Resolving a video's streams is the part that may not.**

Measured 2026-09-11 from a datacenter address: every client in `InnerTube.playerLadder`
came back `LOGIN_REQUIRED` / "Sign in to confirm you're not a bot" with zero formats,
while `browse` and `search` answered normally from the same address in the same minute.

YouTube treats residential and cellular addresses — which is what a phone is — far more
leniently than server ranges, so this is expected to behave differently on a real
device. But it is unverified, and it is the first thing to test once the app is on a
phone: **open any video and try to play it.** If it fails, `Failure.refused` carries
YouTube's own wording into the UI, so the reason will be on screen.

If the wall follows you onto the device, what YouTube is asking for is a signed-in
session or a PO token. This app has neither, and adding them is a substantial piece of
work rather than a setting.

### The JavaScript solver does not currently fire

`JSChallenge` stands in for the Mac's bundled Deno, and against the live player
(`8c3fda2d`, 2.96 MB) it finds nothing. That player hoists its string constants into
four tables and indexes them with values computed at run time — `H5[A^4028]` — so the
operation names the patterns match on are no longer inside the functions that use them.
There is no `a=a.split("")`, no `enhanced_except`, no `fromCharCode(110)` anywhere in it.

This is survivable rather than fatal: the web client is **last** in the ladder and the
three ahead of it hand over plain URLs. The cost is the videos only the web client would
have served. The code is kept because failing costs nothing, and because
`Tools/check-patterns.py` says in a few seconds whether it has started working again.

Getting it working would mean *interpreting* the JavaScript rather than pattern matching
it, which is how yt-dlp gets through — see `yt_dlp/extractor/youtube/_video.py`.

### 1080p is the ceiling

`AVAssetExportSession` passthrough will not write VP9, AV1 or Opus into an MP4, and
there is no ffmpeg here to re-containerise them. So `StreamResolver` only ever selects
H.264 video and AAC audio (`Stream.isMuxable`), and YouTube caps H.264 at 1080p.
`Quality.best` therefore cannot mean 4K the way it does on the Mac. Choosing otherwise
would mean failing at the very end of a long download rather than at the start.

### Downloads do not survive the app being killed

`Transfer` uses a background `URLSession`, so a download keeps going while the app is
suspended or the user is in another app. If the app is force-quit or the system reclaims
it under memory pressure, in-flight jobs are lost and have to be started again.

---

## When it breaks

It will. This talks to a private API that changes without notice. Two tools tell you
*what* broke before you start reading code, and both run on any machine with Python —
no Xcode, no device.

```sh
Tools/check-renderers.py     # is the listing half still correct?
Tools/check-patterns.py      # does the JS solver still find its functions?
```

`check-renderers.py` makes the same calls the app makes and checks the same fields:
channel resolution, the four tabs, paging, search, avatars, subscriber counts. If it
passes and the app still shows an empty list, the bug is in the Swift, not in YouTube.

`check-patterns.py` reads the regexes **out of `Sources/Engine/Patterns.swift`** rather
than restating them, so it cannot drift from what the app does.

Three things have already moved once and will move again:

- **Channel tabs use `lockupViewModel`**, not `videoRenderer`. Shorts use
  `shortsLockupViewModel` and carry no duration at all.
- **On a channel search result, `subscriberCountText` holds the handle** and
  `videoCountText` holds the subscriber count. Reading them by name loses both.
- **A tab response carries six continuation tokens** — one grid, three filter chips, two
  comment sections. Swift cannot pick "the first in document order", because
  `JSONSerialization` is unordered, so `Renderers.continuation(in:)` identifies the
  grid's token structurally. Getting this wrong pages sideways into another shelf,
  intermittently.

The client version strings in `InnerTube.Client` rot faster than anything else. When
extraction fails everywhere at once, check them against yt-dlp's `INNERTUBE_CLIENTS` in
`yt_dlp/extractor/youtube/_base.py`, which is kept current by people watching this full
time.

Runtime logs:

```sh
log stream --predicate 'subsystem == "com.moregroup.ytchannelscraper"'
```

`engine` covers extraction and says which client answered; `transfer` covers downloads
and muxing; `preview` covers playback.
