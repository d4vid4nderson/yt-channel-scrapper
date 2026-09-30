#!/usr/bin/env bash
# Rasterise Support/icon-ios.svg into the asset catalog, and each theme's icon from
# ../icons/themes (see tools/theme-icons.py) into its own alternate icon set. The
# generated PNGs are committed, so this only needs re-running when the artwork changes.
#
# Deliberately does not require Homebrew: the fallback renders the SVG through CoreSVG,
# which every Mac already has. App Store Connect rejects an icon with an alpha channel,
# so the PNG is flattened onto opaque black on the way out either way.
set -euo pipefail
cd "$(dirname "$0")"

render() {
SRC="$1"
OUT="$2"
if command -v rsvg-convert >/dev/null 2>&1; then
  echo "==> rasterising with rsvg-convert"
  rsvg-convert -w 1024 -h 1024 -b '#090909' "$SRC" -o "$OUT"
else
  echo "==> rasterising with CoreSVG (no Homebrew needed)"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/render.swift" <<'SWIFT'
import AppKit

// NSImage reads an SVG through CoreSVG: no WebKit, no window, no run loop. This replaced
// a WKWebView snapshot, which needed all three and crashes outright inside
// -takeSnapshotWithConfiguration: on macOS 26. tools/svg2png.swift has rendered the Mac
// icon this way all along, so both icons now come off the same path.
//
// CoreSVG does not implement <feMerge>, so the glow filter is dropped and the mark comes
// out flat. Install librsvg (brew install librsvg) for a faithful render - the branch
// above prefers rsvg-convert whenever it is present.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])

guard let image = NSImage(contentsOf: source) else {
    FileHandle.standardError.write("could not load \(source.path)\n".data(using: .utf8)!)
    exit(1)
}
image.size = NSSize(width: 1024, height: 1024)

// noneSkipLast, not a 24-bit RGB rep: App Store Connect rejects an icon with an alpha
// channel, but CoreGraphics has no packed 24-bit format and traps if asked for one
// (samplesPerPixel: 3, hasAlpha: false). This is 32-bit with the alpha ignored, which
// encodes to a PNG carrying no alpha channel.
guard let context = CGContext(
    data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(1) }

context.setFillColor(red: 0.035, green: 0.035, blue: 0.035, alpha: 1)
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
NSGraphicsContext.restoreGraphicsState()

guard let cgImage = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
else { exit(1) }
try png.write(to: destination)
SWIFT
  swift "$TMP/render.swift" "$PWD/$SRC" "$PWD/$OUT"
fi

python3 - "$OUT" <<'PY'
import struct, sys
path = sys.argv[1]
with open(path, 'rb') as f:
    head = f.read(33)
assert head[:8] == b'\x89PNG\r\n\x1a\n', "not a PNG"
width, height, depth, colour = struct.unpack('>IIBB', head[16:26])
assert (width, height) == (1024, 1024), f"expected 1024x1024, got {width}x{height}"
# Colour types 4 and 6 carry alpha, which App Store Connect rejects for an app icon.
assert colour in (0, 2, 3), f"icon has an alpha channel (colour type {colour})"
print(f"==> {path}: {width}x{height}, no alpha — good")
PY
}

render Support/icon-ios.svg Support/Assets.xcassets/AppIcon.appiconset/icon-1024.png

# One alternate icon set per theme, named AppIcon-<theme id> — the name
# `ThemeChrome.applyIcon` asks UIKit for, and the list in project.yml.
for SVG in ../icons/themes/*-ios.svg; do
  THEME="$(basename "$SVG" -ios.svg)"
  SET="Support/Assets.xcassets/AppIcon-$THEME.appiconset"
  mkdir -p "$SET"
  cat > "$SET/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  render "$SVG" "$SET/icon-1024.png"
done

# Small copies of every icon as plain image sets, for the theme picker the Home Screen
# quick action opens. An app icon set cannot be loaded as an image, so the picker needs
# its own. 180px is a 60pt tile at 3x.
for SET in Support/Assets.xcassets/AppIcon*.appiconset; do
  NAME="$(basename "$SET" .appiconset)"
  THEME="${NAME#AppIcon-}"
  [ "$THEME" = "AppIcon" ] && THEME="classic"
  OUT="Support/Assets.xcassets/ThemeIcon-$THEME.imageset"
  mkdir -p "$OUT"
  sips -Z 180 "$SET/icon-1024.png" --out "$OUT/icon.png" >/dev/null
  cat > "$OUT/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "icon.png", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
done
echo "==> theme picker icons written"
