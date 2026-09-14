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
nothing in them reaches for AppKit on this platform, the one exception being
`Palette.savedSurface`, which is `#if os(macOS)` because its plate is an AppKit system
colour and only the Mac's rows use it — and everything iOS needs on top of them is an
extension. A
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
at developer.apple.com → Membership. If `com.d4vid4nderson.ytchannelscraper` is taken on
your account, set `YTCS_BUNDLE_ID` in the same file.

Both knobs really are knobs. `project.yml` spells the bundle id as
`$(YTCS_BUNDLE_ID:default=…)` rather than as a plain value, because a target-level build
setting outranks an xcconfig — written plainly, the id here would have silently ignored
whatever `Local.xcconfig` said.

`make-icon.sh` needs no Homebrew — it falls back to rendering the SVG in a `WKWebView`,
which every Mac has. It flattens the result onto opaque black, because App Store Connect
rejects an app icon with an alpha channel.

## Get it onto a phone

**TestFlight, internal testing. That is the plan, and the only plan.** This app is never
going to the App Store, so nothing here is built to survive App Review and no decision in
it should be made in the hope of passing one.

That is not pessimism, it is the premise: an app that downloads YouTube videos is among
the most reliably rejected categories there is — App Review Guideline 5.2.3, plus
YouTube's own terms — so a plan that ends in the App Store is a plan that ends in a
rejection. Internal TestFlight sidesteps the whole question, because **internal testing
has no Beta App Review at all.** A build only has to pass automated validation.

What it costs: a paid Apple Developer Program membership, and every tester has to be a
user on your App Store Connect team (up to 100 of them).

### If signing fails

Two failures look alike from the command line and have nothing to do with each other.

```
No profiles for 'com.d4vid4nderson.ytchannelscraper' were found … Automatic signing is
disabled and unable to generate a profile.
```

Not an error, just `xcodebuild` refusing to talk to Apple unless asked. Add
`-allowProvisioningUpdates` and it creates the App ID and the profile itself. Xcode.app
does this silently, which is why the same project builds there and not here.

```
Your development team has reached the maximum number of registered iPhone devices.
```

That one is an account limit, not a project problem, and no build flag gets past it. A
paid membership registers **100 devices per device type per membership year**, and the
trap is that *disabling* a device does not give the slot back — it only drops it out of
newly generated profiles. The count that matters is every device ever registered this
year, so a team can be at its cap with three devices actually in use.

Slots come back **once per membership year**, in the window Apple opens at renewal:
developer.apple.com → Certificates, Identifiers & Profiles → Devices, where the option
to remove devices appears for that period and nowhere else. Your renewal date is on the
Membership details page. Outside that window the honest options are a different team or
a different phone.

To check which devices a profile actually covers, rather than guessing:

```sh
security cms -D -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<uuid>.mobileprovision \
  | plutil -p - | grep -A20 ProvisionedDevices
xcrun devicectl list devices                       # the phone's UDID is in here
```

Once a slot is free, this puts the app on a connected phone without opening Xcode:

```sh
xcodebuild -project YTChannelScraper.xcodeproj -scheme YTChannelScraper \
  -destination 'id=<device-id>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <device-id> \
  ~/Library/Developer/Xcode/DerivedData/YTChannelScraper-*/Build/Products/Debug-iphoneos/YTChannelScraper.app
```

### The one thing to plan around

**A TestFlight build stops working 90 days after you upload it.** Not the app, not the
account — that specific build. Every 90 days you archive and upload again, and testers
update from the TestFlight app.

Worth knowing: for **your own** phone, plugging in and pressing ⌘R lasts a *year* on a
paid account, which is four times longer than TestFlight. TestFlight earns its keep when
you want installs without a cable, or on devices that are not in front of you — not when
you want the longest-lived install.

### Each release

1. **Once, at the start:** App Store Connect → Apps → **+** → New App. Pick the bundle
   id, give it a name and an SKU. Do not submit it for review, then or ever — the record
   sits in "Prepare for Submission" indefinitely and that is fine.
2. Bump `CFBundleVersion` in `project.yml`. App Store Connect rejects a build number it
   has seen before, and this is the step everyone forgets.
3. `xcodegen generate` if you changed `project.yml`.
4. Xcode → any iOS device as the destination → Product → **Archive**.
5. Organizer → **Distribute App** → **TestFlight & App Store** → Upload. The wording
   mentions the App Store; uploading is not submitting, and nothing is sent for review.
6. Wait a few minutes for processing, then App Store Connect → TestFlight → **Internal
   Testing** → add testers.

Export compliance is answered in advance: `ITSAppUsesNonExemptEncryption` is set to
`false` in the Info.plist because the app uses nothing but HTTPS. Without it App Store
Connect asks the same encryption question on every single upload and holds the build
until you answer.

---

## Known limits

These are real, measured, and deliberately written down rather than discovered later.

### The player endpoint needs a visitor id — it is not a bot wall

This section used to say the opposite, and the correction is worth keeping rather than
quietly deleting, because the wrong version was believed for two days and sent someone
looking at IP reputation and PO tokens.

The symptom: every client in `InnerTube.playerLadder` comes back `LOGIN_REQUIRED` with
the reason "Sign in to confirm you're not a bot" and zero formats, while `browse` and
`search` answer normally from the same address in the same minute. That was measured on
2026-09-11 from a datacenter and read as an IP-reputation block, with the expectation
that a phone on cellular would behave differently.

It does not. The same failure reproduces from a phone, and the same fix works from a
datacenter, because the variable was never the address. The `player` endpoint wants
`visitorData` — YouTube's anonymous session id, carried in `ytcfg` on any page — and
refuses without it. Replaying one request twice on 2026-09-13, seconds apart from the
same machine:

    no visitorData  ->  LOGIN_REQUIRED, 0 formats
    visitorData     ->  OK, 23 adaptive formats, HLS offered

`VisitorID` fetches one per launch and `InnerTube.post` attaches it to every call, as
both `context.client.visitorData` and the `X-Goog-Visitor-Id` header. Either alone is
sufficient; sending both is what YouTube's own clients do.

The lesson worth carrying: `browse` working while `player` refuses is not evidence about
where the request came from. The listing endpoints are simply laxer about the same
missing field.

### Clients rot, and the ladder now reflects that

The version strings in `InnerTube.Client` were all from March 2025 and by late 2026 two
of the four rungs had gone bad in different ways. What the ladder looks like now, and
why:

- **`visionos`** leads. No proof-of-origin requirement, no JavaScript player, and it is
  served the full H.264 ladder to 1080p with AAC beside it — the pair `Muxer` writes
  through untouched.
- **`android_vr`** is second. Also outside the PO-token requirement, but usually offers
  only the muxed 360p rung, so it is a floor rather than a choice.
- **`tv`** third.
- **`ios`** demoted from first to fourth. yt-dlp marks its media URLs
  `GvsPoTokenPolicy(required: true)` as of 2026.08.19: it resolves, promises an HLS
  master, and then answers the fetch with 403. It is kept only in case that lifts.
- **`web`** last, as before, because it needs `JSChallenge`.

A 403 arrives *after* `resolve` has returned, so `StreamResolver` cannot see it. Both
callers feed the refused client back in through `resolve(videoID:for:refused:)`, which
is what lets the ladder keep walking instead of picking the same dead rung forever.

When extraction breaks again, `vendor/yt-dlp_macos` is the fastest oracle available —
it is maintained by people watching this full time:

```sh
./vendor/yt-dlp_macos --simulate -v "https://www.youtube.com/watch?v=<id>"
./vendor/yt-dlp_macos -F --extractor-args "youtube:player_client=android_vr" "<url>"
```

The first line names the client it chose; the second says what a given client is being
offered. Current definitions live in `yt_dlp/extractor/youtube/_base.py` under
`INNERTUBE_CLIENTS`.

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
log stream --predicate 'subsystem == "com.d4vid4nderson.ytchannelscraper"'
```

`engine` covers extraction and says which client answered; `transfer` covers downloads
and muxing; `preview` covers playback.
