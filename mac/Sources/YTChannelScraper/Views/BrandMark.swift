import SwiftUI

/// The badge with a ringed download arrow — the same mark the web app used.
///
/// Solid red in Classic. The other themes draw it as an outline in their brand colour,
/// with the theme's edge round it: squared off and filled, as Nostromo's corners make it,
/// it was a slab — the heaviest thing on a screen otherwise made of hairlines and thin
/// lettering. Kept rather than dropped because it is also the home button, and the thing
/// the hero hands over to the compact header.
struct BrandMark: View {
    var width: CGFloat = 44

    private var height: CGFloat { width * 124 / 176 }
    private var solid: Bool { Theme.active.id == .classic }

    var body: some View {
        let corner = width * 0.17
        let plate = ThemedRect(cornerRadius: corner, style: .continuous)
        let theme = Theme.active
        let ink = solid ? Palette.onFill : theme.markOnHighlight ? theme.litTint : Palette.brand
        ZStack {
            if solid {
                plate.fill(Palette.brand)
            } else if theme.markOnHighlight {
                plate.fill(theme.markFill ?? theme.glowDeep)
                plate.strokeBorder(theme.litTint, lineWidth: max(1, width * 0.024))
            } else {
                plate.fill(Palette.brand.opacity(0.08))
                plate.strokeBorder(Palette.brand, lineWidth: max(1, width * 0.024))
            }
            ZStack {
                Circle()
                    .strokeBorder(ink, lineWidth: width * 0.034)
                    .frame(width: width * 0.36, height: width * 0.36)
                DownArrow()
                    .stroke(ink, style: StrokeStyle(lineWidth: width * 0.034,
                                                    lineCap: .round, lineJoin: .round))
                    .frame(width: width * 0.16, height: width * 0.20)
            }
        }
        .frame(width: width, height: height)
        .themeEdge(radius: corner, lit: !solid)
        .accessibilityHidden(true)
    }

    private struct DownArrow: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let midX = rect.midX
            let stemTop = rect.minY
            let stemBottom = rect.maxY * 0.72
            path.move(to: CGPoint(x: midX, y: stemTop))
            path.addLine(to: CGPoint(x: midX, y: stemBottom))
            path.move(to: CGPoint(x: midX - rect.width * 0.42, y: stemBottom - rect.width * 0.42))
            path.addLine(to: CGPoint(x: midX, y: stemBottom))
            path.addLine(to: CGPoint(x: midX + rect.width * 0.42, y: stemBottom - rect.width * 0.42))
            path.move(to: CGPoint(x: midX - rect.width * 0.55, y: rect.maxY))
            path.addLine(to: CGPoint(x: midX + rect.width * 0.55, y: rect.maxY))
            return path
        }
    }
}
