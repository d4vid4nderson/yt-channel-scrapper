import SwiftUI

/// A panel's handle, carried on the panel's inner edge and sticking out into the page:
/// Saved on the left, Family on the right, Downloads along the bottom.
///
/// These used to be buttons in the window's toolbar, and later moved into the header row
/// once a channel was open — so they were in a different place depending on where you
/// were. A handle on the edge is where the panel itself is and never moves between views.
///
/// It is drawn as part of the panel, not as a button beside it. Its base flares into the
/// panel's edge through two concave fillets, the way a folder's tab grows out of the
/// folder, so the eye follows one continuous outline from the panel's hairline round the
/// tab and back — there is no point at which the tab could be read as a separate object
/// laid on top. The surface is the panel's flat plate rather than its lit `sheetSurface`:
/// that wash is sized to whatever it fills, and squeezed into a tab it tinted the handle a
/// muddy red that matched nothing. It sits one point over the seam to cover the panel's
/// hairline there, which is what makes the two one outline, and it lives inside the panel's
/// slot (`drawerSlot(open:side:tab:)`), so the two move as one.
struct EdgeTab: View {
    enum Edge { case leading, trailing, bottom }

    let edge: Edge
    let icon: String
    /// For the tooltip and VoiceOver; the tab itself is the icon alone.
    let title: String
    let shortcut: String
    var busy = false
    let isOpen: Bool
    let toggle: () -> Void

    @State private var hovering = false

    /// How far a tab sticks out from its panel, and how long its face is along the edge.
    /// A little longer than deep, so it reads as a tab and not as a square button; nowhere
    /// near the old tall sliver, which read as a scrollbar.
    static let depth: CGFloat = 24
    static let length: CGFloat = 36
    /// The concave sweep at each end of the base, along the edge. Part of the tab's frame,
    /// so the frame is this much longer at each end than the face.
    nonisolated static let flare: CGFloat = 7

    var body: some View {
        let fill = TabShape(edge: edge, closed: true)
        Button(action: toggle) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .overlay(alignment: .topTrailing) {
                    if busy {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 5, height: 5)
                            .offset(x: 3, y: -2)
                    }
                }
                .foregroundStyle(isOpen ? Palette.accent : Palette.ink(hovering ? 0.95 : 0.6))
                // Nudged off the base toward the face, so the glyph sits in the middle of
                // what sticks out rather than of the whole frame.
                .offset(nudge)
                .frame(width: size.width, height: size.height)
                .background {
                    ZStack {
                        Palette.surface
                        Palette.ink(hovering ? 0.06 : 0.025)
                    }
                    .clipShape(fill)
                }
                .overlay {
                    TabShape(edge: edge, closed: false)
                        .stroke(Palette.ink(hovering ? 0.3 : 0.2), lineWidth: 1)
                }
                .contentShape(fill)
        }
        .buttonStyle(.plain)
        .help("\(isOpen ? "Close" : "Open") \(title)  (\(shortcut))")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHand()
        .offset(seam)
    }

    private var size: CGSize {
        let along = Self.length + Self.flare * 2
        return edge == .bottom ? CGSize(width: along, height: Self.depth)
                               : CGSize(width: Self.depth, height: along)
    }

    private var nudge: CGSize {
        switch edge {
        case .leading:  CGSize(width: 1, height: 0)
        case .trailing: CGSize(width: -1, height: 0)
        case .bottom:   CGSize(width: 0, height: -1)
        }
    }

    /// Over the panel's hairline by its own width.
    private var seam: CGSize {
        switch edge {
        case .leading:  CGSize(width: -1, height: 0)
        case .trailing: CGSize(width: 1, height: 0)
        case .bottom:   CGSize(width: 0, height: 1)
        }
    }
}

extension View {
    /// `drawerSlot`, with the panel's tab inside the same sliding frame.
    ///
    /// The tab was once an overlay on the slot, and the two animated as separate layers:
    /// the tab got to where it was going and the panel caught up. Here the tab is laid out
    /// beside the panel in one row that the slot reveals, so they are one view and cannot
    /// part. The slot is the tab's depth wider than the panel and gives that depth back to
    /// the page with a negative padding, so the page's width is what it always was.
    func drawerSlot(open: Bool, side: DrawerSide,
                    @ViewBuilder tab: () -> some View) -> some View {
        let depth = EdgeTab.depth
        return HStack(spacing: 0) {
            if side == .trailing { tab().frame(width: depth) }
            frame(width: Layout.drawerWidth)
            if side == .leading { tab().frame(width: depth) }
        }
        .frame(width: (open ? Layout.drawerWidth : 0) + depth, alignment: side.innerEdge)
        .clipped()
        .padding(side == .leading ? .trailing : .leading, -depth)
    }

    /// The same for the Downloads panel, rising from the bottom with its tab on top.
    func bottomDrawerSlot(open: Bool, @ViewBuilder tab: () -> some View) -> some View {
        let depth = EdgeTab.depth
        return VStack(spacing: 0) {
            tab().frame(height: depth)
            frame(height: Layout.downloadsHeight)
        }
        .frame(height: (open ? Layout.downloadsHeight : 0) + depth, alignment: .top)
        .clipped()
        .padding(.top, -depth)
    }
}

/// A tab's outline: a face standing off the base on two sides, the theme's corner where
/// it turns, and a concave fillet where each side meets the base, sweeping out along the
/// panel's edge. `closed: false` leaves the base undrawn, for the hairline, so the tab and
/// the panel share one outline instead of a line between them.
///
/// Drawn once in a frame where the tab sticks out along +u from a base at u = 0, and
/// mapped onto whichever edge it is on — which is how three edges get one shape. A
/// chamfering theme cuts both the corners and the fillets on the diagonal; a square one
/// has neither, and its tab is a plain block.
private struct TabShape: Shape {
    let edge: EdgeTab.Edge
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        let (depth, along) = edge == .bottom ? (rect.height, rect.width) : (rect.width, rect.height)
        func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            switch edge {
            case .leading:  CGPoint(x: rect.minX + u, y: rect.minY + v)
            case .trailing: CGPoint(x: rect.maxX - u, y: rect.minY + v)
            case .bottom:   CGPoint(x: rect.minX + v, y: rect.maxY - u)
            }
        }

        let f = min(EdgeTab.flare, along / 4, depth / 2)
        let a = f, b = along - f     // where the face's two sides stand
        var p = Path()
        switch Theme.active.corners {
        case .rounded(let scale):
            let r = min(8 * scale, depth - f, (b - a) / 2)
            p.move(to: at(0, 0))
            p.addArc(tangent1End: at(0, a), tangent2End: at(f, a), radius: f)
            p.addArc(tangent1End: at(depth, a), tangent2End: at(depth, b), radius: r)
            p.addArc(tangent1End: at(depth, b), tangent2End: at(f, b), radius: r)
            p.addArc(tangent1End: at(0, b), tangent2End: at(0, along), radius: f)
            p.addLine(to: at(0, along))
        case .chamfered(let scale):
            let c = min(6 * scale, depth / 2, (b - a) / 2)
            p.move(to: at(0, 0))
            p.addLine(to: at(f, a))
            p.addLine(to: at(depth - c, a))
            p.addLine(to: at(depth, a + c))
            p.addLine(to: at(depth, b - c))
            p.addLine(to: at(depth - c, b))
            p.addLine(to: at(f, b))
            p.addLine(to: at(0, along))
        case .square:
            p.move(to: at(0, a))
            p.addLine(to: at(depth, a))
            p.addLine(to: at(depth, b))
            p.addLine(to: at(0, b))
        }
        if closed { p.closeSubpath() }
        return p
    }
}
