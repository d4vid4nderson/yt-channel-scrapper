#!/usr/bin/env bash
# Build an ad hoc release and put it on the family's install page, so a phone updates by
# opening https://<user>.github.io/ytplayer-install and tapping Install — no cable.
#
#   ./publish.sh               build, then publish
#   ./publish.sh --no-build    publish whatever ios/build/export already holds
#
# The page is a GitHub Pages repo, cloned beside this one (../../ytplayer-install). It is
# public: anyone with the URL can download the .ipa, but it installs only on the phones
# in the ad hoc profile, and a new phone still has to be registered first (see
# release.sh). The manifest must point at where it is served, so the base URL is fixed
# here and handed to release.sh.
set -euo pipefail
cd "$(dirname "$0")"

REPO="${YTCS_PAGES_REPO:-d4vid4nderson/ytplayer-install}"
BASE="https://${REPO%%/*}.github.io/${REPO#*/}"
CLONE="${YTCS_PAGES_CLONE:-../../ytplayer-install}"
EXPORT=build/export

say() { printf '==> %s\n' "$*"; }

if [ "${1:-}" != "--no-build" ]; then
  YTCS_IGNORE_KEY=1 YTCS_MANIFEST_BASE_URL="$BASE" ./release.sh --adhoc
fi

[ -f "$EXPORT/YTChannelScraper.ipa" ] || { echo "no .ipa in ios/$EXPORT" >&2; exit 1; }

if [ ! -d "$CLONE/.git" ]; then
  say "cloning $REPO"
  gh repo clone "$REPO" "$CLONE"
fi

say "copying the build"
cp "$EXPORT/YTChannelScraper.ipa" "$CLONE/YTChannelScraper.ipa"
# Point the manifest at the page, whatever base URL the build was made with.
sed -E "s#<string>https?://[^<]*/YTChannelScraper.ipa</string>#<string>$BASE/YTChannelScraper.ipa</string>#" \
  "$EXPORT/manifest.plist" > "$CLONE/manifest.plist"
touch "$CLONE/.nojekyll"

version=$(/usr/libexec/PlistBuddy -c "Print :items:0:metadata:bundle-version" "$CLONE/manifest.plist")
stamp=$(date '+%B %-d, %Y at %-I:%M %p')

cat > "$CLONE/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>YT Player</title>
<style>
  :root { --bg: #f5f5f7; --card: #fff; --ink: #1d1d1f; --muted: #6e6e73; --accent: #e5333c; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #000; --card: #1c1c1e; --ink: #f5f5f7; --muted: #98989d; }
  }
  body { margin: 0; background: var(--bg); color: var(--ink);
         font: 17px/1.45 -apple-system, BlinkMacSystemFont, system-ui, sans-serif; }
  main { max-width: 440px; margin: 0 auto; padding: 48px 16px; }
  .card { background: var(--card); border-radius: 20px; padding: 28px 24px; text-align: center; }
  h1 { margin: 0 0 4px; font-size: 28px; }
  p { margin: 0; color: var(--muted); }
  a.install { display: block; margin: 24px 0 8px; padding: 14px; border-radius: 14px;
              background: var(--accent); color: #fff; font-weight: 600; text-decoration: none; }
  ol { text-align: left; color: var(--muted); font-size: 15px; padding-left: 20px; margin: 24px 0 0; }
  li { margin-bottom: 6px; }
</style>
</head>
<body>
<main>
  <div class="card">
    <h1>YT Player</h1>
    <p>Build $version &middot; $stamp</p>
    <a class="install" href="itms-services://?action=download-manifest&amp;url=$BASE/manifest.plist">Install</a>
    <p>Open this page in Safari on the iPhone.</p>
    <ol>
      <li>Tap <b>Install</b>, then <b>Install</b> again when asked.</li>
      <li>Go to the Home Screen and wait for the icon to finish.</li>
      <li>If it says it cannot verify the app: Settings &rarr; General &rarr; VPN &amp; Device Management &rarr; the developer &rarr; Verify App.</li>
    </ol>
  </div>
</main>
</body>
</html>
HTML

say "publishing build $version"
git -C "$CLONE" add -A
git -C "$CLONE" commit -q -m "Build $version"
git -C "$CLONE" push -q -u origin HEAD
say "live shortly at $BASE"
