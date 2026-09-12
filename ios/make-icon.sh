#!/usr/bin/env bash
# Rasterise Support/icon-ios.svg into the asset catalog. Run once after cloning; the
# generated PNG is committed, so this only needs re-running when the artwork changes.
#
# Deliberately does not require Homebrew: the fallback renders the SVG in a WKWebView,
# which every Mac already has. App Store Connect rejects an icon with an alpha channel,
# so the PNG is flattened onto opaque black on the way out either way.
set -euo pipefail
cd "$(dirname "$0")"

OUT="Support/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
SRC="Support/icon-ios.svg"

if command -v rsvg-convert >/dev/null 2>&1; then
  echo "==> rasterising with rsvg-convert"
  rsvg-convert -w 1024 -h 1024 -b '#090909' "$SRC" -o "$OUT"
else
  echo "==> rasterising with WKWebView (no Homebrew needed)"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/render.swift" <<'SWIFT'
import AppKit
import WebKit

// A snapshot needs a run loop and a real window to draw into, so this is an NSApplication
// rather than a plain script: an off-screen WKWebView never finishes its first paint.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])

final class Renderer: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                          styleMask: [.borderless], backing: .buffered, defer: false)

    func run() {
        web.navigationDelegate = self
        window.contentView = web
        window.orderBack(nil)
        // The SVG is wrapped so it fills the viewport exactly with no page margin —
        // otherwise the snapshot comes back 1024 wide with the art inset by 8px.
        let svg = (try? String(contentsOf: source, encoding: .utf8)) ?? ""
        web.loadHTMLString(
            "<html><body style=\"margin:0;background:#090909\">\(svg)</body></html>",
            baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // One runloop turn after didFinish: the filter and gradient are composited after
        // the navigation completes, and snapshotting immediately catches a flat plate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
            webView.takeSnapshot(with: config) { image, error in
                guard let image, error == nil else {
                    FileHandle.standardError.write(Data("snapshot failed: \(error?.localizedDescription ?? "?")\n".utf8))
                    exit(1)
                }
                // Redraw onto an opaque bitmap: WKWebView hands back a representation
                // with alpha, and App Store Connect refuses an icon that has one.
                let flat = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: flat)
                NSColor(red: 0.035, green: 0.035, blue: 0.035, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
                image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
                NSGraphicsContext.restoreGraphicsState()

                guard let png = flat.representation(using: .png, properties: [:]) else { exit(1) }
                try? png.write(to: destination)
                exit(0)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let renderer = Renderer()
renderer.run()
app.run()
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
