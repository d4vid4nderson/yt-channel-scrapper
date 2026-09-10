import SwiftUI

/// The web app's tokens, kept in one place so the native app reads as the same product.
enum Layout {
    /// The header band, shared by the search header and the downloads panel so the
    /// dark strip lines up across the window.
    static let headerHeight: CGFloat = 64

    /// The header row sits below the strip the traffic lights float in, so it needs no
    /// horizontal reserve for them — just the page's own gutter, which lines the home
    /// button up with the Select all chip underneath it.
    static let gutter: CGFloat = 16
}

enum Palette {
    static let accent = Color(red: 1, green: 0, blue: 0)          // --accent #ff0000
    static let ground = Color(red: 0.059, green: 0.059, blue: 0.059)  // #0f0f0f

    /// The drawer's surface: near-black with red light pooling in from the bottom-right
    /// and a faint sheen top-left, same as the hero and picked rows.
    static var sheetSurface: some View {
        ZStack {
            Color(red: 0.071, green: 0.071, blue: 0.071)     // #121212
            RadialGradient(
                stops: [
                    .init(color: Color(red: 1, green: 0.18, blue: 0.24).opacity(0.34), location: 0),
                    .init(color: Color(red: 0.75, green: 0.08, blue: 0.14).opacity(0.12), location: 0.45),
                    .init(color: .clear, location: 0.76),
                ],
                center: UnitPoint(x: 1.04, y: 1.06),
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                stops: [
                    .init(color: .white.opacity(0.06), location: 0),
                    .init(color: .clear, location: 0.62),
                ],
                center: UnitPoint(x: -0.08, y: -0.14),
                startRadius: 0,
                endRadius: 420
            )
        }
    }

    /// A picked row goes dark with red light pooling in from the bottom-right, echoing
    /// the hero, rather than just gaining a coloured outline.
    static func pickedSurface(height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.071, green: 0.071, blue: 0.071), location: 0),
                    .init(color: Color(red: 0.098, green: 0.067, blue: 0.075), location: 0.55),
                    .init(color: Color(red: 0.169, green: 0.071, blue: 0.094), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                stops: [
                    .init(color: Color(red: 1, green: 0.18, blue: 0.24).opacity(0.42), location: 0),
                    .init(color: Color(red: 0.75, green: 0.08, blue: 0.14).opacity(0.16), location: 0.45),
                    .init(color: .clear, location: 0.72),
                ],
                center: UnitPoint(x: 1, y: 1.25),
                startRadius: 0,
                endRadius: max(height * 1.9, 120)
            )
            RadialGradient(
                stops: [
                    .init(color: .white.opacity(0.07), location: 0),
                    .init(color: .clear, location: 0.6),
                ],
                center: UnitPoint(x: 0, y: -0.3),
                startRadius: 0,
                endRadius: max(height * 1.5, 100)
            )
        }
    }
}

/// The web app's pill-shaped `.chip`.
struct ChipBackground: ViewModifier {
    var active = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                active ? AnyShapeStyle(Palette.accent.opacity(0.14))
                       : AnyShapeStyle(Color.primary.opacity(0.06)),
                in: Capsule()
            )
    }
}

extension View {
    func chip(active: Bool = false) -> some View { modifier(ChipBackground(active: active)) }
}
