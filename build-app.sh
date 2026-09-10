#!/usr/bin/env bash
# Build "YT Channel Scraper.app" and wrap it in a DMG.
#
#   ./build-app.sh                full build
#   ./build-app.sh --app          stop after the .app, skip the DMG
#   ./build-app.sh --keep-build   leave build/ in place for debugging
#
# Everything it downloads is cached in vendor/, so a rebuild is offline and quick.
set -euo pipefail
cd "$(dirname "$0")"

APP_ONLY=
KEEP_BUILD=
for arg in "$@"; do
  case "$arg" in
    --app)        APP_ONLY=1 ;;
    --keep-build) KEEP_BUILD=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

APP="YT Channel Scraper"
FFMPEG_RELEASE=b6.1.1   # eugeneware/ffmpeg-static — fully static, includes libmp3lame
ARCH=$(uname -m)
case "$ARCH" in
  arm64)  FF_ARCH=darwin-arm64; DENO_ARCH=aarch64-apple-darwin ;;
  x86_64) FF_ARCH=darwin-x64;   DENO_ARCH=x86_64-apple-darwin ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# PyInstaller's scratch dir holds a "$APP.pkg" — its own intermediate archive format,
# not a macOS installer. Double-clicking it hands it to Installer.app, which fails with
# "pagecontroller error -1". Clearing build/ on success keeps that trap out of the tree.
clean_build() {
  if [ -n "$KEEP_BUILD" ]; then
    echo "  keeping build/ (--keep-build)"
  else
    rm -rf build
    echo "  cleared build/ (PyInstaller scratch; --keep-build to retain)"
  fi
}

# --- toolchain -----------------------------------------------------------------------
step "Checking the build venv"
if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q --upgrade pip
fi
.venv/bin/pip install -q -r requirements.txt
.venv/bin/pip install -q --upgrade pyinstaller

# --- ffmpeg ---------------------------------------------------------------------------
# Homebrew's ffmpeg links ~18 Homebrew dylibs, so copying that binary would produce a
# bundle that only runs on a Mac that already has Homebrew's ffmpeg installed.
step "Staging static ffmpeg ($FF_ARCH)"
mkdir -p vendor
BASE="https://github.com/eugeneware/ffmpeg-static/releases/download/$FFMPEG_RELEASE"
for bin in ffmpeg ffprobe; do
  if [ ! -x "vendor/$bin" ]; then
    echo "  downloading $bin"
    curl -fsSL -o "vendor/$bin" "$BASE/$bin-$FF_ARCH"
    chmod +x "vendor/$bin"
  else
    echo "  vendor/$bin already staged"
  fi
done
# curl-downloaded files carry no quarantine flag, but a browser-downloaded one would.
xattr -dr com.apple.quarantine vendor/ffmpeg vendor/ffprobe 2>/dev/null || true
vendor/ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libmp3lame \
  || { echo "vendor/ffmpeg cannot encode mp3 — audio-only downloads would fail" >&2; exit 1; }

# --- deno -----------------------------------------------------------------------------
# YouTube gates every format above 360p behind a JavaScript "n challenge". yt-dlp solves
# it by shelling out to a JS runtime, which it finds by bare name on PATH — and an app
# launched from Finder inherits a PATH with no Homebrew in it. So the runtime ships in
# vendor/ alongside ffmpeg and app.py prepends that directory at boot.
step "Staging deno ($DENO_ARCH)"
if [ ! -x vendor/deno ]; then
  echo "  downloading deno"
  curl -fsSL -o vendor/deno.zip \
    "https://github.com/denoland/deno/releases/latest/download/deno-$DENO_ARCH.zip"
  ditto -x -k vendor/deno.zip vendor/
  rm -f vendor/deno.zip
  chmod +x vendor/deno
else
  echo "  vendor/deno already staged"
fi
xattr -dr com.apple.quarantine vendor/deno 2>/dev/null || true
# An ad-hoc signature keeps Gatekeeper from killing the helper when the app shells out to
# it; the outer --deep signing pass does not reach a plain data file.
codesign --force --sign - vendor/deno >/dev/null 2>&1 || true
vendor/deno --version >/dev/null 2>&1 \
  || { echo "vendor/deno will not run — downloads above 360p would fail" >&2; exit 1; }
echo "  $(vendor/deno --version | head -1)"

# --- yt-dlp ---------------------------------------------------------------------------
# Frozen in from the venv. Build against the current release so a fresh bundle does not
# start life needing the in-app update.
step "Updating yt-dlp"
rm -rf vendor/lib   # left behind by earlier builds that shipped it unpacked
.venv/bin/pip install -q --upgrade yt-dlp
YTDLP=$(.venv/bin/python -c "from yt_dlp.version import __version__ as v; print(v)")
echo "  yt-dlp $YTDLP"

# --- icon -----------------------------------------------------------------------------
# icon.svg is the master: a square 1024 canvas holding the same mark as docs/logo.svg.
# The old source was a 3879x2673 landscape PNG squashed to square by `sips -z`, which
# produced a distorted red blob with no arrow — and it was gitignored, so the icon could
# not be rebuilt from a clean checkout. QuickLook honours the SVG's filters, so the glow
# is baked in by the rasteriser rather than hand-painted.
step "Building the icon"
if [ -f icon.svg ]; then
  rm -rf icon.iconset build/iconsrc && mkdir -p icon.iconset build/iconsrc
  qlmanage -t -s 1024 -o build/iconsrc icon.svg >/dev/null 2>&1
  MASTER="build/iconsrc/icon.svg.png"
  [ -f "$MASTER" ] || { echo "qlmanage could not rasterise icon.svg" >&2; exit 1; }
  # The master is square, so -z (which does not preserve aspect) is safe here.
  for s in 16 32 64 128 256 512; do
    sips -z $s $s "$MASTER" --out "icon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$MASTER" \
      --out "icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns icon.iconset -o icon.icns
  rm -rf icon.iconset
  echo "  icon.icns written from icon.svg"
else
  echo "  no icon.svg — building without a custom icon"
  : > icon.icns
fi

# --- freeze ---------------------------------------------------------------------------
step "Running PyInstaller"
rm -rf build "dist/$APP.app" "dist/$APP"
.venv/bin/pyinstaller --noconfirm --clean "$APP.spec"

# PyInstaller does not preserve the exec bit on data files; app.py re-chmods at runtime,
# but setting it here means the very first launch does not have to.
chmod +x "dist/$APP.app/Contents/Resources/vendor/ffmpeg" \
         "dist/$APP.app/Contents/Resources/vendor/ffprobe" \
         "dist/$APP.app/Contents/Resources/vendor/deno" 2>/dev/null || true

# An unsigned bundle trips Gatekeeper on launch. An ad-hoc signature is enough for a
# locally built app used locally; distributing it to other Macs needs a real Developer ID
# and notarisation, or the recipient has to right-click -> Open the first time.
step "Ad-hoc signing"
codesign --force --deep --sign - "dist/$APP.app"
codesign --verify --deep "dist/$APP.app" && echo "  signature verifies"

if [ -n "$APP_ONLY" ]; then
  step "Done — dist/$APP.app"
  clean_build
  exit 0
fi

# --- dmg ------------------------------------------------------------------------------
# A plain `hdiutil create` leaves the generic white disk-image icon on both the volume and
# the .dmg file. Matching the app icon takes two separate pieces of Finder plumbing:
#   volume    — .VolumeIcon.icns at the volume root + the custom-icon bit on the root
#   .dmg file — the icns copied into the file's resource fork + the custom-icon bit
# Neither can be set on a compressed image, so the image is built read-write, dressed
# while mounted, then converted to UDZO.
step "Building the DMG"
rm -rf dist/dmg "dist/$APP.dmg" "dist/$APP.rw.dmg" && mkdir -p dist/dmg
cp -R "dist/$APP.app" dist/dmg/
ln -s /Applications "dist/dmg/Applications"
cp icon.icns "dist/dmg/.VolumeIcon.icns"
hdiutil create -volname "$APP" -srcfolder dist/dmg -ov -format UDRW -quiet "dist/$APP.rw.dmg"
rm -rf dist/dmg

step "Applying the icon to the DMG"
MNT=$(mktemp -d /tmp/ytcs-dmg.XXXXXX)
hdiutil attach "dist/$APP.rw.dmg" -mountpoint "$MNT" -nobrowse -quiet
SetFile -a C "$MNT"                       # tells Finder to use .VolumeIcon.icns
hdiutil detach "$MNT" -quiet
rmdir "$MNT" 2>/dev/null || true
hdiutil convert "dist/$APP.rw.dmg" -format UDZO -o "dist/$APP.dmg" -quiet
rm -f "dist/$APP.rw.dmg"

# The .dmg file's own Finder icon lives in its resource fork, not in the image contents.
RSRC=$(mktemp -d /tmp/ytcs-rsrc.XXXXXX)
cp icon.icns "$RSRC/icon.icns"
sips -i "$RSRC/icon.icns" >/dev/null            # give the icns an icon resource...
DeRez -only icns "$RSRC/icon.icns" > "$RSRC/icon.rsrc"   # ...so it can be extracted...
Rez -append "$RSRC/icon.rsrc" -o "dist/$APP.dmg"         # ...and appended to the dmg
SetFile -a C "dist/$APP.dmg"
rm -rf "$RSRC"
echo "  volume and .dmg file both carry the app icon"

step "Done"
clean_build
echo "  dist/$APP.app   $(du -sh "dist/$APP.app" | cut -f1)"
echo "  dist/$APP.dmg   $(du -sh "dist/$APP.dmg" | cut -f1)"
echo "  bundled yt-dlp $YTDLP"
