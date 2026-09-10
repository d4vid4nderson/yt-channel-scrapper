import SwiftUI

/// The starburst that bloomed out of the bottom-right corner of the web app's landing
/// page: four blurred discs of different sizes, all centred on the corner itself, screen
/// -blended over near-black so the overlaps brighten rather than muddy.
///
/// Sizes are kept as fractions of the window width, the way the original used `vw`, so
/// the bloom keeps its proportions as the window is resized.
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private static let ground = Color(red: 0.059, green: 0.059, blue: 0.059)   // #0f0f0f

    private struct Disc {
        let scale: CGFloat          // fraction of window width
        let stops: [Gradient.Stop]
        let period: Double
        let grow: CGFloat
        let shift: CGSize
    }

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

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                Self.ground
                ForEach(Array(Self.discs.enumerated()), id: \.offset) { _, disc in
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
                        .blendMode(.screen)
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
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { drift = true }
    }
}
