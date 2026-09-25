import AppKit
import Foundation

/// Which screen edge the island grows out of, and where along that edge it sits.
///
/// The island started life pinned to the notch, which is one place on one display and
/// needed no describing. Being able to put it anywhere means writing that place down,
/// and this is it.
///
/// Stored as a *fraction* of the edge rather than a point, so it keeps its place across
/// a resolution change — plugging into a projector should not leave it hanging off the
/// side of the screen.
struct IslandPlacement: Codable, Equatable {
    enum Edge: String, Codable, CaseIterable, Identifiable {
        case top, bottom, left, right

        var id: String { rawValue }

        /// Which way the island slides when you drag it along this edge. Also which way
        /// its flat side faces, and therefore which pair of corners stay square.
        var isHorizontal: Bool { self == .top || self == .bottom }

        var label: String {
            switch self {
            case .top: "Top edge"
            case .bottom: "Bottom edge"
            case .left: "Left edge"
            case .right: "Right edge"
            }
        }
    }

    var edge: Edge

    /// Where the island's middle sits along the edge, 0 to 1 from the screen's left or
    /// bottom.
    ///
    /// Deliberately the middle and not a corner: the island is two quite different
    /// widths depending on whether it is open, and a stored corner would make it appear
    /// to crawl sideways every time you hovered it.
    var along: CGFloat

    /// The display it was left on. Without this, an island parked on a second monitor
    /// comes back on the built-in one at launch, because a fraction on its own says
    /// nothing about which screen it is a fraction of.
    var displayID: CGDirectDisplayID?
}

/// A placement resolved against the displays that actually exist right now.
///
/// Everything that positions the panel goes through this, including the default: `nil`
/// placement resolves to `home()`, so there is one piece of geometry rather than a
/// notch case and an everything-else case drifting apart.
struct IslandDock {
    let screen: NSScreen
    let edge: IslandPlacement.Edge

    /// Where the island's middle sits along the edge, in screen coordinates.
    let centre: CGFloat

    /// The notch's own width, and non-nil only when the island is actually sitting in
    /// one. The collapsed pill has to be wider than the notch: sized narrower, it sits
    /// black-on-black *inside* it and is effectively invisible. Anywhere else there is
    /// nothing to clear and the pill takes its own minimum width.
    let notchWidth: CGFloat?

    /// How close to home a drop has to land before it is treated as going home rather
    /// than as a placement of its own. Generous, because the notch is the one target
    /// on the screen edge you cannot see the boundaries of.
    static let homeRadius: CGFloat = 70

    /// How much closer a different edge has to be before the island jumps to it.
    ///
    /// In a corner two edges are within a few points of each other, and without this
    /// the island flips between them on every pixel of mouse movement.
    static let edgeHysteresis: CGFloat = 48

    /// Home: the top edge of the notched display, centred on the notch itself — which
    /// is not always the screen's midpoint, they differ when displays are arranged
    /// off-centre. Machines with no notch get the screen's midpoint.
    static func home() -> IslandDock? {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let screen else { return nil }
        if let notch = notch(on: screen) {
            return IslandDock(screen: screen, edge: .top, centre: notch.centre, notchWidth: notch.width)
        }
        return IslandDock(screen: screen, edge: .top, centre: screen.frame.midX, notchWidth: nil)
    }

    /// Resolve a stored placement, falling back to home if the display it names has
    /// been unplugged since.
    static func resolve(_ placement: IslandPlacement?) -> IslandDock? {
        guard let placement else { return home() }
        guard let screen = screen(for: placement.displayID) else { return home() }
        let frame = screen.frame
        let span = placement.edge.isHorizontal ? frame.width : frame.height
        let origin = placement.edge.isHorizontal ? frame.minX : frame.minY
        return IslandDock(
            screen: screen,
            edge: placement.edge,
            centre: origin + placement.along * span,
            // A placement exists precisely because the island was moved off home, and
            // a drop that lands back near the notch is turned into `nil` rather than a
            // fraction that happens to sit there. So an explicit placement is never in
            // the notch, and has nothing to clear.
            notchWidth: nil
        )
    }

    /// Whether a placement is close enough to home to simply be home.
    static func isHome(_ placement: IslandPlacement?) -> Bool {
        guard placement != nil else { return true }
        guard let dock = resolve(placement), let home = home() else { return false }
        guard dock.edge == .top else { return false }
        // The same *display*, not merely the same fraction: the top middle of a second
        // monitor looks like home arithmetically and is nowhere near it.
        guard let here = dock.screen.displayID, here == home.screen.displayID else { return false }
        return abs(dock.centre - home.centre) <= homeRadius
    }

    /// The edge nearest a point, with a bias towards staying on the one already held.
    static func edge(
        nearest point: CGPoint,
        on screen: NSScreen,
        holding held: IslandPlacement.Edge
    ) -> IslandPlacement.Edge {
        let frame = screen.frame
        let gaps: [(IslandPlacement.Edge, CGFloat)] = [
            (.top, frame.maxY - point.y),
            (.bottom, point.y - frame.minY),
            (.left, point.x - frame.minX),
            (.right, frame.maxX - point.x),
        ]
        guard let nearest = gaps.min(by: { $0.1 < $1.1 }) else { return held }
        let heldGap = gaps.first { $0.0 == held }?.1 ?? .greatestFiniteMagnitude
        return nearest.1 + edgeHysteresis < heldGap ? nearest.0 : held
    }

    /// The rect a panel of this size occupies: flush to the edge, growing inward, and
    /// clamped so it cannot hang off the ends of the screen.
    ///
    /// Each size is clamped by its own length, so a shut island can be parked right
    /// into a corner. The open one is longer and clamps sooner, which means opening in
    /// a corner grows inward from it rather than recentring — the corner end of the
    /// two rects is the same end, because both are against it.
    func frame(for size: CGSize) -> NSRect {
        let bounds = screen.frame
        if edge.isHorizontal {
            let middle = clamp(centre, span: size.width, low: bounds.minX, high: bounds.maxX)
            let y = edge == .top ? bounds.maxY - size.height : bounds.minY
            return NSRect(x: middle - size.width / 2, y: y, width: size.width, height: size.height)
        }
        let middle = clamp(centre, span: size.height, low: bounds.minY, high: bounds.maxY)
        let x = edge == .left ? bounds.minX : bounds.maxX - size.width
        return NSRect(x: x, y: middle - size.height / 2, width: size.width, height: size.height)
    }

    /// The screen a point is on.
    ///
    /// Not simply `contains`: dragging *along* an edge puts the cursor exactly on the
    /// boundary, and a rect does not contain its own top or right side — which would
    /// leave the island homeless at the very position it is being asked about. So fall
    /// back to whichever screen the point is least far outside.
    static func screen(under point: CGPoint) -> NSScreen? {
        if let inside = NSScreen.screens.first(where: { $0.frame.contains(point) }) { return inside }
        return NSScreen.screens.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    private static func distance(from point: CGPoint, to frame: NSRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }

    /// The fraction this point corresponds to along one of a screen's edges.
    static func fraction(of value: CGFloat, along edge: IslandPlacement.Edge, on screen: NSScreen) -> CGFloat {
        let frame = screen.frame
        let span = edge.isHorizontal ? frame.width : frame.height
        guard span > 0 else { return 0.5 }
        return (value - (edge.isHorizontal ? frame.minX : frame.minY)) / span
    }

    /// Keep a middle far enough from both ends that something `span` long, centred on
    /// it, stays between them.
    private func clamp(_ centre: CGFloat, span: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        // Longer than the screen: no position fits, so sit in the middle and overhang
        // evenly rather than pin to one end.
        guard high - low >= span else { return (low + high) / 2 }
        return min(max(centre, low + span / 2), high - span / 2)
    }

    private static func notch(on screen: NSScreen) -> (centre: CGFloat, width: CGFloat)? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return nil
        }
        return ((left.maxX + right.minX) / 2, right.minX - left.maxX)
    }

    private static func screen(for id: CGDirectDisplayID?) -> NSScreen? {
        guard let id else { return nil }
        return NSScreen.screens.first { $0.displayID == id }
    }
}

extension NSScreen {
    /// The display this screen draws, for remembering which one something was left on.
    /// `NSScreen` objects themselves are rebuilt whenever the arrangement changes, so
    /// they cannot be held onto or compared across one.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
