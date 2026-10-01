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
/// the panel's hairline there, which is what makes the two one outline. The chevron points
/// the way a click will move the panel.
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

    var body: some View {
        let shape = TabShape(edge: edge, closed: true)
        Button(action: toggle) {
            stack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .overlay(alignment: .topTrailing) {
                        if busy {
                            Circle()
                                .fill(Palette.accent)
                                .frame(width: 5, height: 5)
                                .offset(x: 3, y: -2)
                        }
                    }
                Image(systemName: chevron)
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
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
        edge == .bottom ? CGSize(width: 56, height: 20) : CGSize(width: 20, height: 56)
    }

    /// Over the panel's hairline by its own width.
    private var seam: CGSize {
        switch edge {
        case .leading:  CGSize(width: -1, height: 0)
        case .trailing: CGSize(width: 1, height: 0)
        case .bottom:   CGSize(width: 0, height: 1)
        }
    }

    /// Which way the panel will move: out from its edge when closed, back into it when open.
    private var chevron: String {
        switch (edge, isOpen) {
        case (.leading, false), (.trailing, true): "chevron.right"
        case (.leading, true), (.trailing, false): "chevron.left"
        case (.bottom, false): "chevron.up"
        case (.bottom, true):  "chevron.down"
        }
    }

    @ViewBuilder
    private func stack(@ViewBuilder _ content: () -> some View) -> some View {
        if edge == .bottom {
            HStack(spacing: 5, content: content)
        } else {
            VStack(spacing: 4, content: content)
        }
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
