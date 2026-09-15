# YT Channel Scraper — working notes

Read this before changing anything. It records decisions that were made deliberately and
that look like bugs or oversights if you meet them cold.

Deeper documentation lives in `ios/README.md` (the engine rewrite) and in the doc comments
of the files themselves, which are unusually complete — when a file explains why it does
something the odd way, that reasoning is load-bearing.

---

## 1. This app is not going on the App Store. Do not try to make it compliant.

It is distributed **ad hoc to one family's own devices**. `ios/release.sh --adhoc` signs
an `.ipa` and an OTA manifest; the TestFlight path in that script is legacy and is not the
one being used.

That decision was reached after working through the alternatives, so please do not reopen
it unprompted:

- **Downloading media from YouTube would fail App Review** under the guideline covering
  saving/converting/downloading third-party media. True, and irrelevant — nothing is being
  submitted for review.
- **"Just stream it instead"** was evaluated and rejected. The sanctioned route is the
  YouTube IFrame Player API in a `WKWebView`, and it cannot suppress ads — blocking them is
  explicitly prohibited, and detection is aggressive. The owner's requirement is a child's
  device with **no ads at all**, and streaming cannot deliver that at any price below a
  YouTube Premium family subscription.
- **A downloaded file has no ads**, because there is no request for one to be served into.
  That is the entire reason the download engine exists and why it is not going away.

This remains contrary to YouTube's terms of service. The owner knows, the scope is their
own household, nothing is redistributed, and it is their call — which they have made. Do
not re-argue it, and do not add ad-blocking, DOM manipulation of any YouTube player, or
anything else aimed at a *shipped* product. Build for the family.

---

## 2. Layout

```
mac/     The original macOS app. Ships separately, outside the Mac App Store.
ios/     The iPhone/iPad app. Shares Model/ and a few Core files with mac/, compiled in place.
app.py   The original Flask prototype. Not part of either app.
```

**Do not edit `mac/` to make something in `ios/` more convenient.** `ios/project.yml`
compiles `mac/Sources/YTChannelScraper/Model/`, `Core/Log.swift`, `Core/LibraryArchive.swift`,
`Core/CloudMirror.swift` and `Views/Palette.swift` directly, in place. A careless change
there breaks a shipping app. `ShelfReconciler.video(from:)` builds a `Video` through
`init?(json:)` rather than adding a memberwise init for exactly this reason.

Deliberately *promoting* a file into `mac/Core/` so both apps share it is a different thing
and is fine — `CloudMirror.swift` moved there from `ios/Sources/Store/` precisely so the Mac
app gets the same iCloud mirror. The rule is about incidental edits, not about the sharing
boundary being frozen.

The iOS engine is a native Swift rewrite of what the Mac does with vendored `yt-dlp`,
`ffmpeg` and `deno`, none of which can exist on iOS. `ios/Sources/Engine/` calls YouTube's
InnerTube API directly. See `ios/README.md`.

---

## 3. Build and test

```sh
cd ios
xcodegen generate                    # project is generated from project.yml, not checked in
xcodebuild build -project YTChannelScraper.xcodeproj -scheme YTChannelScraper \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -project YTChannelScraper.xcodeproj -scheme YTChannelScraper \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:YTChannelScraperTests
```

`YTChannelScraperTests` is a logic bundle with no host app — it never launches the app, runs
in about two seconds, and cannot be broken by a signing problem. Run it after touching
anything in `Store/`.

Signing lives in `ios/Local.xcconfig` (gitignored): `DEVELOPMENT_TEAM`, optionally
`YTCS_BUNDLE_ID`.

---

## 4. Current work: the guardian shelf

Turning the app from a scraper into a parent-controlled library. Two guardians each keep
their own private library; together they decide what each child may see; the child's device
plays **only local files**, which is what makes it ad-free.

### Three collections, deliberately not one

1. **Personal library** — per guardian, private. `ios/Sources/Store/Library.swift` +
   `mac/Sources/YTChannelScraper/Core/CloudMirror.swift`, synced through
   `NSUbiquitousKeyValueStore` (one Apple ID). **Unchanged by the shelf work, and correct as is.**
2. **Shelf** — one per child, edited by both guardians. `Store/Shelf.swift` + `Store/ShelfStore.swift`.
3. **Local cache** — the files on the child's phone. `Store/ShelfReconciler.swift`.

Approving is a *promotion*, not a move: it stays in your library too, and the other guardian
never sees your library.

### Done and passing (20 tests)

| File | Role |
|---|---|
| `Store/Shelf.swift` | `ShelfEntry`, `ShelfMerge`, `ShelfFile`. Pure logic. |
| `Store/ShelfStore.swift` | The shared iCloud Drive folder. |
| `Store/ShelfReconciler.swift` | Makes a child's disk match their shelf. |
| `Store/Profiles.swift` | Grew `Guardian`/`Minor` identity + a v1 migration. |
| `App/AppModel.swift` | Holds `shelf` and `reconciler`; `syncShelf()`. |
| `Views/MinorModeView.swift` | Picks which child the phone becomes. |
| `Tests/ShelfMergeTests.swift` | The merge rules. |

### Not built — the feature is not reachable from the UI yet

1. **The `Playback` guard.** Nothing stops a minor's device playing a `.stream`. Until
   `Playback` refuses one in Minor Mode, "ad-free" depends on what the UI happens to offer
   rather than on anything the app enforces. **Do this first.**
2. **Family settings screen** — name yourself as a guardian (`Profiles.setGuardianName`),
   pick the shared folder (`ShelfStore.adopt`), add a child (`ShelfStore.createMinor`).
   Nothing else can be used without it.
3. **Approve affordance** on library rows, and a per-child shelf screen.
4. **`syncShelf()` is never called.** Wire it to foreground.
5. **Per-profile storage budget.** Left out rather than half-built; an enthusiastic
   approval session can currently fill a phone.

### Setup is manually bootstrapped, by necessity

iOS has no API to create a shared iCloud Drive folder or invite anyone to one — sharing is
a user action in Files.app. So: one guardian makes a folder, shares it with the other,
and each device points the app at it once through a folder picker. Do not go looking for
an API to automate this; there isn't one.

---

## 5. Invariants. Breaking these is silent and lands on a child's phone.

**Never prune tombstones.** A `removed` entry is the entire representation of a veto and
must outlive the approval it overrides. The trap, written out because it looks like an
obvious optimisation: *David approves a video. Sarah removes it. Ninety days pass, Sarah's
phone drops her tombstone as stale, David's approval is now the only decision left, and the
video returns to the child's device.* At this scale the files are kilobytes. See the doc
comment on `ShelfMerge.collapsed`.

**A failed read is not an empty shelf.** `ShelfStore.refresh` keeps the last good copy on
error, and `ShelfReconciler` refuses to act before a successful read. Otherwise a network
blip reads as "everything was un-approved" and the reconciler deletes the child's library.

**One writer per file.** Each device writes only `<minorID>-<its own guardianID>.json` and
reads all of them. That is why there is no locking and no `NSFileCoordinator` dance for
conflicts. Do not add a shared file that two devices write to — a combined roster file was
considered and rejected for this reason; the roster is derived from `ShelfFile.minorName`.

**Identity comes from inside the file, never the filename.** Otherwise a rename in Files.app
silently reassigns a child's shelf.

**Removal wins ties.** ISO-8601 truncates sub-second precision, so two decisions made
milliseconds apart come back from JSON as the same instant. Without this, a veto is a coin
flip. Tested in `datesSurviveEncodingForTieBreaking`.

**Approving a channel does not approve its videos.** Nothing is playable without a decision
naming the video itself, so a channel posting something new cannot push it to a child
unseen. A channel *removal*, however, does cascade to its videos — blocking a channel is
expected to take what is already on the phone with it. The asymmetry is intentional; see
`ShelfMerge.playable`.

**Never sweep a file with no `videoID`.** Anything the user put in the folder themselves
has none, plays fine, and is not the reconciler's business.

**Fail closed on profile mode.** A stored `minor` wins; a v1 `"minor"` migrates to
`.minor(nil)` and stays locked awaiting assignment rather than unlocking. A migration that
unlocked the phone would hand a child the Search tab, silently, on upgrade.

---

## 6. State of the tree

Branch `ios-dev`, well ahead of `main`, with a large amount uncommitted — including the
whole shelf feature and several renamed views (`LibraryView` → `HomeView`, `BrowseView` →
`SearchView`). **Nothing is committed, so the working tree is the only copy.** Check
`git status` before assuming anything.

### Two agents worked in this tree on 2026-09-15

Two Claude Code sessions edited this repo in parallel, and the owner is consolidating them.
The tree builds and all 20 tests pass with both sets of changes in place, but there is known
overlap to resolve:

- **`Views/SendSheet.swift`** — a one-shot "Send to Device" that exports a ticked subset of
  channels and videos through the share sheet. It solves, manually and per-transfer, roughly
  what `ShelfStore` now solves continuously. Probably redundant; decide before building more
  UI on either.
- **`ios/project.yml`** — carries edits from both sessions: the `Shared-Cloud` entry for the
  moved `CloudMirror.swift`, and the `YTChannelScraperTests` target plus its scheme. Both are
  present and working. Do not regenerate this file from memory of one session's version.
- **Minor Mode** was originally a simple `Mode { parent, minor }` with a Keychain PIN and
  Face ID. The shelf work *extended* that rather than replacing it — the PIN hashing,
  attempt throttling, `PINPad` and biometric paths are all the original code, with
  `Guardian`/`Minor` identity added on top and a fail-closed v1 migration.
