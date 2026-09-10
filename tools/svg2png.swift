import AppKit

// svg2png <in.svg> <out.png> <size>
//
// Rasterises an SVG at a given size, preserving transparency.
//
// `qlmanage -t` was used for this and cannot be: QuickLook thumbnails are composited
// onto an opaque white background, so everything the SVG leaves transparent — the canvas
// around the icon's squircle — came out as opaque white and showed in the Dock as a
// white square framing the icon. NSImage renders the SVG through CoreSVG and keeps the
// alpha channel intact.
let args = CommandLine.arguments
guard args.count == 4, let side = Int(args[3]) else {
    FileHandle.standardError.write("usage: svg2png <in.svg> <out.png> <size>\n".data(using: .utf8)!)
    exit(2)
}
guard let source = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("svg2png: could not load \(args[1])\n".data(using: .utf8)!)
    exit(1)
}
source.size = NSSize(width: side, height: side)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
// Nothing is filled first, so anything the SVG does not paint stays transparent.
source.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: args[2]))
} catch {
    FileHandle.standardError.write("svg2png: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
