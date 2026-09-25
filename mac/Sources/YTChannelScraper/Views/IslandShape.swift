import SwiftUI

/// The island's outline: a straight side against the screen, softly rounded corners on
/// the three sides that are not, and — where the body meets that straight side — a
/// *concave* flare rather than a corner.
///
/// The flare is the whole point. A convex corner there ends the shape, and the island
/// reads as a rectangle parked next to the screen edge. A concave one hands the outline
/// off to the bezel instead, so the island reads as something peeking out from behind
/// the screen — the same trick a speech bubble's tail plays, and what the Dynamic
/// Island does against the real notch.
///
/// Drawn once for a left-docked island and then transformed onto whichever edge it is
/// actually on. Four hand-written paths would be four chances to get one of them subtly
/// wrong, and only one of the four is ever on screen to notice it.
struct IslandShape: Shape {
    var edge: IslandPlacement.Edge
    /// The far corners, away from the screen.
    var radius: CGFloat
    /// How far the body stands off the ends of the straight side before flaring back
    /// into it.
    var flare: CGFloat

    /// So the corners ease between the collapsed and expanded sizes with everything
    /// else rather than snapping at the start of the animation.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, flare) }
        set {
            radius = newValue.first
            flare = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Along the edge it is docked to, and out from it.
        let along = edge.isHorizontal ? rect.width : rect.height
        let depth = edge.isHorizontal ? rect.height : rect.width
        guard along > 0, depth > 0 else { return Path() }

        let body = leftDocked(depth: depth, along: along)
        // `CGAffineTransform` maps (x, y) to (a·x + c·y + tx, b·x + d·y + ty). The two
        // upright cases are the identity; the horizontal ones transpose, which swaps
        // the two axes and lays the same shape along the top or the bottom.
        let placed: Path = switch edge {
        case .left:   body
        case .right:  body.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: depth, ty: 0))
        case .top:    body.applying(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0))
        case .bottom: body.applying(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: depth))
        }
        return placed.offsetBy(dx: rect.minX, dy: rect.minY)
    }

    /// The canonical shape: docked on the left, `depth` out to the right, `along` tall.
    private func leftDocked(depth: CGFloat, along: CGFloat) -> Path {
        let r = max(0, min(radius, depth, along / 2))
        // Never more flare than there is body to flare out of.
        let f = max(0, min(flare, depth - r, (along - 2 * r) / 2))
        // The magic constant for a circular quarter-arc as a cubic. Arcs by angle would
        // do as well, but `Path` measures them in a flipped space and the sign of
        // `clockwise` is a coin toss to read; control points are unambiguous.
        let k: CGFloat = 0.552_284_749_830_793_6

        var path = Path()
        // The straight side runs the full length, against the screen. Everything else
        // is held off the ends of it by the flare.
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(
            to: CGPoint(x: f, y: f),
            control1: CGPoint(x: 0, y: k * f),
            control2: CGPoint(x: f - k * f, y: f)
        )
        path.addLine(to: CGPoint(x: depth - r, y: f))
        path.addCurve(
            to: CGPoint(x: depth, y: f + r),
            control1: CGPoint(x: depth - r + k * r, y: f),
            control2: CGPoint(x: depth, y: f + r - k * r)
        )
        path.addLine(to: CGPoint(x: depth, y: along - f - r))
        path.addCurve(
            to: CGPoint(x: depth - r, y: along - f),
            control1: CGPoint(x: depth, y: along - f - r + k * r),
            control2: CGPoint(x: depth - r + k * r, y: along - f)
        )
        path.addLine(to: CGPoint(x: f, y: along - f))
        path.addCurve(
            to: CGPoint(x: 0, y: along),
            control1: CGPoint(x: f - k * f, y: along - f),
            control2: CGPoint(x: 0, y: along - k * f)
        )
        path.closeSubpath()
        return path
    }
}
