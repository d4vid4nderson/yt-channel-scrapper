#!/usr/bin/env bash
# Assemble the native Swift app into dist-mac/YT Channel Scraper.app.
#
# There is no Xcode project: the sources build with SwiftPM and the bundle is put
# together here, because what makes this an app rather than a binary is mostly the
# three vendored executables in Resources plus an Info.plist.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="YT Channel Scraper"
BUNDLE_ID="com.moregroup.ytchannelscraper"
VERSION="2.0.0"
OUT="dist-mac"
APP="$OUT/$APP_NAME.app"

VENDORED=(yt-dlp_macos ffmpeg ffprobe deno)
for bin in "${VENDORED[@]}"; do
  if [ ! -f "vendor/$bin" ]; then
    echo "missing vendor/$bin — see README" >&2
    exit 1
  fi
done

echo "==> building (release)"
( cd mac && swift build -c release )
BINARY="mac/.build/release/YTChannelScraper"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/vendor"

cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

for bin in "${VENDORED[@]}"; do
  cp "vendor/$bin" "$APP/Contents/Resources/vendor/$bin"
  chmod +x "$APP/Contents/Resources/vendor/$bin"
done

# --- icon ---
# icon-dark.svg and icon-light.svg are the masters, rasterised by tools/svg2png.swift.
#
# Not qlmanage: QuickLook flattens thumbnails onto opaque white, so the transparent
# canvas around the icon's squircle became a white square and framed the icon in the
# Dock. Each iconset size is rendered from the SVG directly rather than downscaled from
# one master, so the small sizes stay crisp.
#
# The .icns can only hold one appearance — macOS resolves appearance-aware icons from an
# Icon Composer .icon document, and that has no build-time CLI (ictool only exports
# images). So the dark artwork is the static icon and both renders ship as PNGs for the
# app to swap between at runtime; see AppDelegate.applyIcon.
echo "==> rasterising icons"
mkdir -p build
SVG2PNG="build/svg2png"
if swiftc -O -o "$SVG2PNG" tools/svg2png.swift 2>/dev/null; then
  rm -rf build/icon.iconset && mkdir -p build/icon.iconset
  for s in 16 32 64 128 256 512; do
    "$SVG2PNG" icon-dark.svg "build/icon.iconset/icon_${s}x${s}.png" $s
    "$SVG2PNG" icon-dark.svg "build/icon.iconset/icon_${s}x${s}@2x.png" $((s * 2))
  done
  iconutil -c icns build/icon.iconset -o icon.icns
  "$SVG2PNG" icon-dark.svg "$APP/Contents/Resources/AppIconDark.png" 1024
  "$SVG2PNG" icon-light.svg "$APP/Contents/Resources/AppIconLight.png" 1024
  rm -rf build/icon.iconset
  echo "    icon.icns + both appearance PNGs written (with alpha)"
else
  echo "    could not build tools/svg2png.swift — keeping the existing icon.icns" >&2
fi

cp icon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local use only.</string>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# Ad-hoc signing, inner binaries first — an unsigned nested executable invalidates the
# outer signature, and macOS refuses to launch a bundle whose signature does not match.
echo "==> signing (ad-hoc)"
for bin in "${VENDORED[@]}"; do
  codesign --force --sign - --timestamp=none "$APP/Contents/Resources/vendor/$bin" 2>/dev/null
done
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

SIZE=$(du -sh "$APP" | cut -f1)
echo "==> done: $APP ($SIZE)"
