#!/usr/bin/env bash
# Build "YT Channel Scraper.app" and wrap it in a DMG.
#
#   ./build-app.sh          full build
#   ./build-app.sh --app    stop after the .app, skip the DMG
#
# Everything it downloads is cached in vendor/, so a rebuild is offline and quick.
set -euo pipefail
cd "$(dirname "$0")"

APP="YT Channel Scraper"
FFMPEG_RELEASE=b6.1.1   # eugeneware/ffmpeg-static — fully static, includes libmp3lame
ARCH=$(uname -m)
case "$ARCH" in
  arm64)  FF_ARCH=darwin-arm64 ;;
  x86_64) FF_ARCH=darwin-x64 ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

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

# --- yt-dlp ---------------------------------------------------------------------------
# Frozen in from the venv. Build against the current release so a fresh bundle does not
# start life needing the in-app update.
step "Updating yt-dlp"
rm -rf vendor/lib   # left behind by earlier builds that shipped it unpacked
.venv/bin/pip install -q --upgrade yt-dlp
YTDLP=$(.venv/bin/python -c "from yt_dlp.version import __version__ as v; print(v)")
echo "  yt-dlp $YTDLP"

# --- icon -----------------------------------------------------------------------------
step "Building the icon"
if [ -f "YT_download@300x.png" ]; then
  rm -rf icon.iconset && mkdir -p icon.iconset
  for s in 16 32 64 128 256 512; do
    sips -z $s $s "YT_download@300x.png" --out "icon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "YT_download@300x.png" \
      --out "icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns icon.iconset -o icon.icns
  rm -rf icon.iconset
  echo "  icon.icns written"
else
  echo "  no source PNG — building without a custom icon"
  : > icon.icns
fi

# --- freeze ---------------------------------------------------------------------------
step "Running PyInstaller"
rm -rf build "dist/$APP.app" "dist/$APP"
.venv/bin/pyinstaller --noconfirm --clean "$APP.spec"

# PyInstaller does not preserve the exec bit on data files; app.py re-chmods at runtime,
# but setting it here means the very first launch does not have to.
chmod +x "dist/$APP.app/Contents/Resources/vendor/ffmpeg" \
         "dist/$APP.app/Contents/Resources/vendor/ffprobe" 2>/dev/null || true

# An unsigned bundle trips Gatekeeper on launch. An ad-hoc signature is enough for a
# locally built app used locally; distributing it to other Macs needs a real Developer ID
# and notarisation, or the recipient has to right-click -> Open the first time.
step "Ad-hoc signing"
codesign --force --deep --sign - "dist/$APP.app"
codesign --verify --deep "dist/$APP.app" && echo "  signature verifies"

if [ "${1:-}" = "--app" ]; then
  step "Done — dist/$APP.app"
  exit 0
fi

# --- dmg ------------------------------------------------------------------------------
step "Building the DMG"
rm -rf dist/dmg "dist/$APP.dmg" && mkdir -p dist/dmg
cp -R "dist/$APP.app" dist/dmg/
ln -s /Applications "dist/dmg/Applications"
hdiutil create -volname "$APP" -srcfolder dist/dmg -ov -format UDZO -quiet "dist/$APP.dmg"
rm -rf dist/dmg

step "Done"
echo "  dist/$APP.app   $(du -sh "dist/$APP.app" | cut -f1)"
echo "  dist/$APP.dmg   $(du -sh "dist/$APP.dmg" | cut -f1)"
echo "  bundled yt-dlp $YTDLP"
