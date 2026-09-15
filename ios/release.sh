#!/usr/bin/env bash
# Cut a build and put it where testers can get at it.
#
#   ./release.sh                 archive, export, upload to TestFlight internal testing
#   ./release.sh --adhoc         archive and export a signed .ipa + an OTA manifest
#   ./release.sh --check         say whether this machine could do either, and stop
#   ./release.sh --schedule      run it on the 1st of every month, unattended
#   ./release.sh --unschedule    stop doing that
#
# Why this exists at all: a TestFlight build stops working 90 days after it is uploaded,
# so somebody has to archive and upload again before then — forever, for as long as
# anyone is using the app. A chore with no end date should not be six manual steps in an
# Organizer window, because the one time it gets forgotten every tester's app dies at
# once, with no warning and nothing they can do about it.
#
# Monthly rather than every-90-days on purpose. Each upload resets the clock, so running
# three times more often than strictly needed means two missed runs — a closed laptop, a
# machine away for repair — still leave the window open.
set -euo pipefail
cd "$(dirname "$0")"

SCHEME=YTChannelScraper
PROJECT=YTChannelScraper.xcodeproj
BUNDLE_DEFAULT=com.d4vid4nderson.ytchannelscraper
LABEL=com.d4vid4nderson.ytchannelscraper.release
LOG="$HOME/Library/Logs/ytcs-release.log"

MODE=testflight
ACTION=release
for arg in "$@"; do
  case "$arg" in
    --adhoc)      MODE=adhoc ;;
    --check)      ACTION=check ;;
    --schedule)   ACTION=schedule ;;
    --unschedule) ACTION=unschedule ;;
    -h|--help)    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg  (try --help)" >&2; exit 2 ;;
  esac
done

say() { printf '==> %s\n' "$*"; }
die() { printf 'release.sh: %s\n' "$*" >&2; exit 1; }

# --- what the machine needs before any of this can work -------------------------------

# The team id lives in Local.xcconfig, which is gitignored, so it is read from there
# rather than written down a second time here.
team_id() {
  [ -f Local.xcconfig ] || return 1
  sed -n 's|^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*||p' Local.xcconfig \
    | sed 's|//.*||' | tr -d '[:space:]' | head -1
}

bundle_id() {
  local override=""
  [ -f Local.xcconfig ] && override=$(sed -n 's|^[[:space:]]*YTCS_BUNDLE_ID[[:space:]]*=[[:space:]]*||p' \
    Local.xcconfig | sed 's|//.*||' | tr -d '[:space:]' | head -1)
  printf '%s' "${override:-$BUNDLE_DEFAULT}"
}

# The App Store Connect API key is the whole reason this can run with nobody at the
# keyboard: it authenticates the upload *and* lets xcodebuild create and renew
# provisioning profiles on its own, which is otherwise a dialog in Xcode.
#
#   App Store Connect -> Users and Access -> Integrations -> App Store Connect API
#   -> generate a key with the App Manager role, download the .p8 once, keep it.
#
# Local.release.env is gitignored and holds nothing but the two ids and the path.
load_key() {
  [ -f Local.release.env ] && . ./Local.release.env
  ASC_KEY_ID="${ASC_KEY_ID:-}"
  ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
  ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
  # ~ is not expanded inside a quoted value in the env file.
  ASC_KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
}

# True when there is a usable API key. Run by hand, the key is optional — xcodebuild
# falls back to the Apple ID signed into Xcode, which is enough for a one-off upload.
# Run by launchd at three in the morning it is not optional: that session prompts, and
# eventually expires, and nobody is there to notice either.
have_key() {
  load_key
  [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ] && [ -f "$ASC_KEY_PATH" ]
}

check() {
  local ok=1 unattended="${1:-}"
  for tool in xcodebuild xcodegen; do
    command -v "$tool" >/dev/null || { echo "  missing: $tool"; ok=; }
  done
  [ -n "$(team_id || true)" ] || { echo "  missing: DEVELOPMENT_TEAM in ios/Local.xcconfig"; ok=; }
  if [ -n "$unattended" ] && ! have_key; then
    echo "  missing: an App Store Connect API key — see Local.release.env.example"
    echo "           (needed only to run unattended; by hand, Xcode's own account does)"
    ok=
  fi
  [ -n "$ok" ]
}

# --- what testers are told ------------------------------------------------------------

# Notes ride along inside the archive: Xcode looks for TestFlight/WhatToTest.<locale>.txt
# when it assembles the upload, so the build arrives in App Store Connect with its notes
# already filled in and there is nothing to paste into a web form afterwards.
#
# WhatToTest.txt wins whenever somebody has edited it since the last upload — a person
# saying what this build is for beats any generated list. Left untouched, the commit
# subjects since the last release stand in, and a monthly keep-alive build with no commits
# behind it says so plainly rather than repeating stale notes at testers.
NOTES_FILE=WhatToTest.txt
MARKER=.last-release        # gitignored: epoch and commit of the last successful upload

notes() {
  local since_epoch="" since_sha="" text=""
  if [ -f "$MARKER" ]; then
    since_epoch=$(sed -n '1p' "$MARKER")
    since_sha=$(sed -n '2p' "$MARKER")
  fi

  if [ -f "$NOTES_FILE" ] \
     && { [ -z "$since_epoch" ] || [ "$(stat -f %m "$NOTES_FILE")" -gt "$since_epoch" ]; }; then
    text=$(cat "$NOTES_FILE")
  elif [ -n "$since_sha" ] && git rev-parse --verify --quiet "$since_sha^{commit}" >/dev/null 2>&1; then
    text=$(git log --format='- %s' "$since_sha..HEAD")
  fi

  if [ -z "$text" ]; then
    text="Nothing new to test. This build exists so the last one does not expire —
install it and carry on."
  fi
  # App Store Connect caps the field at 4000 characters.
  printf '%s\n' "$text" | cut -c1-4000 | head -c 4000
}

# --- the scheduling half --------------------------------------------------------------

schedule() {
  check unattended || die "not scheduling a job that cannot run yet — fix the above first"
  local plist="$HOME/Library/LaunchAgents/$LABEL.plist"
  mkdir -p "$HOME/Library/LaunchAgents" "$(dirname "$LOG")"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PWD/release.sh</string>
  </array>
  <!-- The 1st of the month, early. A calendar job missed because the Mac was asleep or
       off runs at the next wake rather than being skipped. -->
  <key>StartCalendarInterval</key>
  <dict>
    <key>Day</key><integer>1</integer>
    <key>Hour</key><integer>3</integer>
    <key>Minute</key><integer>15</integer>
  </dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$plist"
  say "scheduled: 1st of every month, 03:15 — log at $LOG"
  say "run it now without waiting:  launchctl kickstart -p gui/$UID/$LABEL"
}

unschedule() {
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
  say "unscheduled"
}

# --- the build half -------------------------------------------------------------------

release() {
  check || die "cannot build yet — see above"
  load_key

  local team build_dir archive export_dir options
  team=$(team_id)
  build_dir=build
  archive="$build_dir/$SCHEME.xcarchive"
  export_dir="$build_dir/export"
  options="$build_dir/ExportOptions.plist"

  # Epoch seconds: always larger than last time, which is the only thing App Store
  # Connect cares about — it refuses a build number it has already seen, and that is the
  # step a human forgets. Overridable for a one-off.
  local number="${YTCS_BUILD_NUMBER:-$(date +%s)}"

  say "$(date '+%Y-%m-%d %H:%M') — build $number, $MODE"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"

  # macOS still ships bash 3.2, where expanding an empty array under `set -u` is an
  # error rather than nothing — hence the ${a[@]+...} guard at each use below.
  local auth=()
  if have_key; then
    auth=(-authenticationKeyPath "$ASC_KEY_PATH"
          -authenticationKeyID "$ASC_KEY_ID"
          -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  elif [ "$MODE" = testflight ]; then
    say "no API key — using the Apple ID signed into Xcode (fine by hand, not unattended)"
  fi

  say "generating the project"
  xcodegen generate >/dev/null

  say "archiving"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" \
    CURRENT_PROJECT_VERSION="$number" \
    -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} archive >"$build_dir/archive.log" 2>&1 \
    || { tail -40 "$build_dir/archive.log"; die "archive failed (full log: ios/$build_dir/archive.log)"; }

  if [ "$MODE" = testflight ]; then
    mkdir -p "$archive/TestFlight"
    notes > "$archive/TestFlight/WhatToTest.en-US.txt"
    say "notes: $(head -1 "$archive/TestFlight/WhatToTest.en-US.txt")"

    # `destination: upload` makes the export step do the upload as well, so there is no
    # second tool and no Transporter window. `manageAppVersionAndBuildNumber: false`
    # stops Xcode quietly rewriting the number chosen above.
    cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$team</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
    say "uploading to TestFlight"
    xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
      -exportPath "$export_dir" -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} \
      >"$build_dir/export.log" 2>&1 \
      || { tail -40 "$build_dir/export.log"; die "upload failed (full log: ios/$build_dir/export.log)"; }

    # Only now, so a failed upload does not make the next run think its notes are stale.
    printf '%s\n%s\n' "$(date +%s)" "$(git rev-parse HEAD)" > "$MARKER"

    say "uploaded build $number — internal testers get it once processing finishes"
    say "nothing to review: internal testing has no Beta App Review"
  else
    # release-testing is Xcode 15.3+'s name for what everyone still calls ad hoc: signed
    # for the devices in the profile, installable off a web server, never seen by Apple.
    cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>release-testing</string>
  <key>teamID</key><string>$team</string>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
PLIST
    say "exporting a signed .ipa"
    xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
      -exportPath "$export_dir" -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} \
      >"$build_dir/export.log" 2>&1 \
      || { tail -40 "$build_dir/export.log"; die "export failed (full log: ios/$build_dir/export.log)"; }

    # iOS will not install a bare .ipa handed to it in Files. It installs one an
    # itms-services link points at, through a manifest that names where the .ipa is —
    # which is why this is written out beside it. Both have to be served over HTTPS with
    # a certificate the phone trusts.
    local base="${YTCS_MANIFEST_BASE_URL:-https://example.com/ytcs}"
    cat > "$export_dir/manifest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>$base/$SCHEME.ipa</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>$(bundle_id)</string>
        <key>bundle-version</key><string>$number</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>YT Channel Scraper</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST
    say "exported to ios/$export_dir"
    [ -n "${YTCS_MANIFEST_BASE_URL:-}" ] \
      || say "manifest points at $base — set YTCS_MANIFEST_BASE_URL to where you will host it"
    say "install link:  itms-services://?action=download-manifest&url=$base/manifest.plist"
  fi
}

case "$ACTION" in
  check)      check && { have_key && say "ready to release ($MODE), key and all" \
                                  || say "ready to release ($MODE) by hand; add a key to schedule it"; } \
                    || die "not ready" ;;
  schedule)   schedule ;;
  unschedule) unschedule ;;
  release)    release ;;
esac
