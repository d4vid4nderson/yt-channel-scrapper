import SwiftUI

/// A panel's handle, carried on the panel's inner edge and sticking out into the page:
/// Saved on the left, Family on the right, Downloads along the bottom.
///
/// These used to be buttons in the window's toolbar, and later moved into the header row
/// once a channel was open — so they were in a different place depending on where you
/// were. A handle on the edge is where the panel itself is and never moves between views.
///
/// It is drawn as part of the panel, not as a button beside it: the panel's own surface
/// and hairline, flush against its edge, square where it joins and rounded only where it
/// sticks out — so with the panel open it reads as the panel's tab, and with it closed as
/// the panel's edge peeking out of the window. It sits one point over the seam to cover
/// the panel's hairline there, which is what makes the two one outline. It lives inside
/// the panel's slot (`drawerSlot(open:side:tab:)`), so the two move as one.
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

    /// How far a tab sticks out from its panel, and how long it is along the edge. Close to
    /// square on purpose: a tall sliver read as a scrollbar rather than as a handle.
    static let depth: CGFloat = 26
    static let length: CGFloat = 32

    var body: some View {
        let shape = TabShape(edge: edge, closed: true)
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
                .foregroundStyle(isOpen ? Palette.accent : Palette.ink(hovering ? 0.95 : 0.65))
                .frame(width: size.width, height: size.height)
                .background { Palette.sheetSurface.clipShape(shape) }
                .overlay {
                    TabShape(edge: edge, closed: false)
                        .stroke(Palette.ink(hovering ? 0.32 : 0.2), lineWidth: 1)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help("\(isOpen ? "Close" : "Open") \(title)  (\(shortcut))")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .onHover { hovering = $0 }
        .pointingHand()
        .offset(seam)
    }

    private var size: CGSize {
        edge == .bottom ? CGSize(width: Self.length, height: Self.depth)
                        : CGSize(width: Self.depth, height: Self.length)
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

/// A tab's outline: square on the side that joins the panel, the theme's corner on the
/// two that stick out. `closed: false` leaves the joining side undrawn, for the hairline,
/// so the tab and the panel share one outline instead of a line between them.
///
/// Drawn once in a frame where the tab sticks out along +u from a base at u = 0, and
/// mapped onto whichever edge it is on — which is how three edges get one shape.
private struct TabShape: Shape {
    let edge: EdgeTab.Edge
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        let (depth, length) = edge == .bottom ? (rect.height, rect.width) : (rect.width, rect.height)
        func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            switch edge {
            case .leading:  CGPoint(x: rect.minX + u, y: rect.minY + v)
            case .trailing: CGPoint(x: rect.maxX - u, y: rect.minY + v)
            case .bottom:   CGPoint(x: rect.minX + v, y: rect.maxY - u)
            }
        }

        var p = Path()
        p.move(to: at(0, 0))
        switch Theme.active.corners {
        case .rounded(let scale):
            let r = min(8 * scale, depth, length / 2)
            p.addArc(tangent1End: at(depth, 0), tangent2End: at(depth, length), radius: r)
            p.addArc(tangent1End: at(depth, length), tangent2End: at(0, length), radius: r)
        case .chamfered(let scale):
            let c = min(6 * scale, depth / 2, length / 2)
            p.addLine(to: at(depth - c, 0))
            p.addLine(to: at(depth, c))
            p.addLine(to: at(depth, length - c))
            p.addLine(to: at(depth - c, length))
        case .square:
            p.addLine(to: at(depth, 0))
            p.addLine(to: at(depth, length))
        }
        p.addLine(to: at(0, length))
        if closed { p.closeSubpath() }
        return p
    }
}
