import SwiftUI

/// The starburst that bloomed out of the bottom-right corner of the web app's landing
/// page: four blurred discs of different sizes, all centred on the corner itself, screen
/// -blended over near-black so the overlaps brighten rather than muddy.
///
/// Sizes are kept as fractions of the window width, the way the original used `vw`, so
/// the bloom keeps its proportions as the window is resized.
///
/// Light mode is the same bloom inverted at the blend, not recoloured at the stops.
/// Screen over near-black brightens where the discs overlap, which is what makes it
/// read as light; screen over white has nowhere to go and flattens to paper. Multiply
/// is the same operation from the other end — pale discs deepening where they overlap
/// — so the corner still gathers, and the overlaps still say there are four of them.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var drift = false

    private struct Disc {
        let scale: CGFloat          // fraction of window width
        let stops: [Gradient.Stop]
        let period: Double
        let grow: CGFloat
        let shift: CGSize
    }

    /// Pale enough that multiplying them onto white is a wash rather than a stain.
    /// The order and the geometry are the dark set's — only the stops differ.
    private static let lightDiscs: [Disc] = [
        Disc(scale: 0.52,
             stops: [
                .init(color: Color(red: 1.00, green: 0.71, blue: 0.72), location: 0),
                .init(color: Color(red: 1.00, green: 0.80, blue: 0.78).opacity(0.6), location: 0.38),
                .init(color: .clear, location: 0.68),
             ],
             period: 13, grow: 1.12, shift: .zero),
        Disc(scale: 0.70,
             stops: [
                .init(color: Color(red: 1.00, green: 0.82, blue: 0.73).opacity(0.75), location: 0),
                .init(color: Color(red: 1.00, green: 0.78, blue: 0.77).opacity(0.35), location: 0.42),
                .init(color: .clear, location: 0.70),
             ],
             period: 19, grow: 1.16, shift: CGSize(width: -0.06, height: -0.04)),
        Disc(scale: 0.96,
             stops: [
                .init(color: Color(red: 0.97, green: 0.79, blue: 0.80).opacity(0.7), location: 0),
                .init(color: Color(red: 0.96, green: 0.86, blue: 0.87).opacity(0.3), location: 0.45),
                .init(color: .clear, location: 0.72),
             ],
             period: 27, grow: 1.08, shift: CGSize(width: 0.03, height: 0.02)),
        Disc(scale: 0.34,
             stops: [
                .init(color: Color(red: 1.00, green: 0.89, blue: 0.82).opacity(0.55), location: 0),
                .init(color: Color(red: 1.00, green: 0.83, blue: 0.79).opacity(0.25), location: 0.50),
                .init(color: .clear, location: 0.74),
             ],
             period: 17, grow: 1.20, shift: CGSize(width: -0.02, height: -0.03)),
    ]

    private static let discs: [Disc] = [
        Disc(scale: 0.52,
             stops: [
                .init(color: Color(red: 1.00, green: 0.14, blue: 0.20), location: 0),
                .init(color: Color(red: 0.80, green: 0.07, blue: 0.13).opacity(0.6), location: 0.38),
                .init(color: .clear, location: 0.68),
             ],
             period: 13, grow: 1.12, shift: .zero),
        Disc(scale: 0.70,
             stops: [
                .init(color: Color(red: 1.00, green: 0.43, blue: 0.27).opacity(0.75), location: 0),
                .init(color: Color(red: 0.88, green: 0.14, blue: 0.18).opacity(0.35), location: 0.42),
                .init(color: .clear, location: 0.70),
             ],
             period: 19, grow: 1.16, shift: CGSize(width: -0.06, height: -0.04)),
        Disc(scale: 0.96,
             stops: [
                .init(color: Color(red: 0.75, green: 0.06, blue: 0.12).opacity(0.7), location: 0),
                .init(color: Color(red: 0.43, green: 0.04, blue: 0.08).opacity(0.3), location: 0.45),
                .init(color: .clear, location: 0.72),
             ],
             period: 27, grow: 1.08, shift: CGSize(width: 0.03, height: 0.02)),
        Disc(scale: 0.34,
             stops: [
                .init(color: Color(red: 1.00, green: 0.59, blue: 0.43).opacity(0.55), location: 0),
                .init(color: Color(red: 1.00, green: 0.24, blue: 0.20).opacity(0.25), location: 0.50),
                .init(color: .clear, location: 0.74),
             ],
             period: 17, grow: 1.20, shift: CGSize(width: -0.02, height: -0.03)),
    ]

    /// Classic's geometry, in a theme's colours. The strengths are the dark set's; a light
    /// theme multiplies them in, so its colours are already pale.
    private static func discs(for theme: Theme) -> [Disc] {
        let c = theme.aurora
        func stops(_ core: Color, _ a: Double, _ b: Double) -> [Gradient.Stop] {
            [.init(color: core.opacity(a), location: 0),
             .init(color: core.opacity(b), location: 0.40),
             .init(color: .clear, location: 0.70)]
        }
        return [
            Disc(scale: 0.52, stops: stops(c[0], 1, 0.6), period: 13, grow: 1.12, shift: .zero),
            Disc(scale: 0.70, stops: stops(c[1], 0.75, 0.35), period: 19, grow: 1.16,
                 shift: CGSize(width: -0.06, height: -0.04)),
            Disc(scale: 0.96, stops: stops(c[2], 0.7, 0.3), period: 27, grow: 1.08,
                 shift: CGSize(width: 0.03, height: 0.02)),
            Disc(scale: 0.34, stops: stops(c[3], 0.55, 0.25), period: 17, grow: 1.20,
                 shift: CGSize(width: -0.02, height: -0.03)),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let dark = scheme == .dark
            let theme = Theme.active
            let discs = theme.aurora.isEmpty
                ? (dark ? Self.discs : Self.lightDiscs)
                : Self.discs(for: theme)
            ZStack {
                Palette.ground
                ForEach(Array(discs.enumerated()), id: \.offset) { _, disc in
                    let diameter = side * disc.scale
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(stops: disc.stops),
                                center: .center,
                                startRadius: 0,
                                endRadius: diameter / 2
                            )
                        )
                        .frame(width: diameter, height: diameter)
                        // Centred on the corner, so only the upper-left quadrant shows.
                        .position(x: geo.size.width, y: geo.size.height)
                        .scaleEffect(drift ? disc.grow : 1, anchor: .bottomTrailing)
                        .offset(
                            x: drift ? side * disc.shift.width : 0,
                            y: drift ? geo.size.height * disc.shift.height : 0
                        )
                        .blendMode(dark ? .screen : .multiply)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: disc.period).repeatForever(autoreverses: true),
                            value: drift
                        )
                }
            }
            .compositingGroup()     // keep .screen blending inside this stack
            .blur(radius: 48)
            .clipped()
            // The theme's own scenery — rain, dunes, a grid — sharp, over the bloom.
            .overlay { ThemeBackdrop() }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { drift = true }
    }
}
