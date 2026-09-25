import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The web app's tokens, kept in one place so the native app reads as the same product.
/// Colour comes from the active `Theme`; see `Views/Theme.swift`.
enum Layout {
    /// The header band, shared by the search header and the downloads panel so the
    /// dark strip lines up across the window.
    static let headerHeight: CGFloat = 64

    /// The header row sits below the strip the traffic lights float in, so it needs no
    /// horizontal reserve for them — just the page's own gutter, which lines the home
    /// button up with the Select all chip underneath it.
    static let gutter: CGFloat = 16

    /// What a favourites panel takes from the page. Wide enough for a two-line video
    /// title beside its thumbnail, narrow enough that the list it is standing next to is
    /// still a list you can read.
    static let drawerWidth: CGFloat = 290

    /// The downloads panel is a handful of rows and a footer, not a page of its own.
    static let downloadsHeight: CGFloat = 300

    /// One easing for all three panels, so opening any of them is recognisably the same
    /// gesture.
    static let drawerEase = Animation.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.32)
}

enum Palette {

    // MARK: - Light and dark

    /// One colour that knows both appearances.
    ///
    /// Classic's tokens are built through here (see `Theme.classic`), so "what does this
    /// look like in light mode" is answered once per token and never at a call site.
    /// Resolved by the system at draw time, which is also what makes the app follow the
    /// Mac live when you flip the setting rather than needing a relaunch. The other
    /// themes each fix one appearance and need none of this.
    ///
    /// Two implementations because this file is compiled into the iPhone app as well —
    /// see `ios/project.yml`.
    static func dynamic(dark: Color, light: Color) -> Color {
        #if canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
        #else
        Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }

    static func adaptive(_ dark: Color, _ light: Color) -> Color { dynamic(dark: dark, light: light) }

    /// Built tokens, kept rather than rebuilt.
    ///
    /// A `Color` made fresh inside a view body is a new value every time as far as
    /// SwiftUI's diffing is concerned, so a view that draws one would never compare
    /// equal to itself and would redraw on every pass. There are a few dozen of these
    /// in the whole app, per theme — the key carries the theme for that reason.
    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var made: [String: Color] = [:]

        func colour(_ key: String, _ build: () -> Color) -> Color {
            let key = "\(Theme.active.id.rawValue).\(key)"
            lock.lock()
            defer { lock.unlock() }
            if let hit = made[key] { return hit }
            let colour = build()
            made[key] = colour
            return colour
        }
    }

    private static var theme: Theme { Theme.active }

    // MARK: - Ink

    /// Content on a surface, at `weight` of full strength.
    ///
    /// In the dark that is the theme's ink — white in Classic; in the light it is
    /// near-black, or Middle-earth's sepia — but not at the same weight, which is the
    /// part worth writing down. Dark on light bites harder than light on dark at the
    /// same opacity, so the top of the range comes down a little and the bottom comes
    /// up: a hairline at 0.09 white would all but vanish at 0.09 black, and text at full
    /// white would be a harsher black than anything else on the screen. One curve,
    /// `0.92 · w^0.85`, holds the whole ramp — from body text down through captions to
    /// hairlines and resting fills — in the same relationship to its background in both
    /// modes.
    static func ink(_ weight: Double) -> Color {
        cache.colour("ink\(weight)") {
            let t = theme
            let lightWeight = 0.92 * pow(weight, 0.85)
            switch t.appearance {
            case .adaptive:
                return dynamic(dark: .white.opacity(weight), light: .black.opacity(lightWeight))
            case .dark:
                return t.ink.opacity(weight)
            case .light:
                return t.ink.opacity(lightWeight)
            }
        }
    }

    /// The highlight where light falls on a surface.
    ///
    /// White in the dark. On a light surface there is nothing brighter to go to, so it
    /// becomes the faintest shade instead — the same modelling of a surface, lit from
    /// the other side.
    static func sheen(_ weight: Double) -> Color {
        cache.colour("sheen\(weight)") {
            let t = theme
            switch t.appearance {
            case .adaptive:
                return dynamic(dark: .white.opacity(weight), light: .black.opacity(weight * 0.55))
            case .dark:
                return t.ink.opacity(weight)
            case .light:
                return t.ink.opacity(weight * 0.55)
            }
        }
    }

    // MARK: - Brand

    /// The theme's accent: Classic's `--accent #ff0000`.
    static var accent: Color { theme.accent }

    /// The theme's second colour, where it has one.
    static var accent2: Color { theme.accent2 }

    /// The brand badge's fill.
    static var brand: Color { theme.brand }

    /// The page under everything.
    static var ground: Color { theme.ground }

    /// A panel or a row standing on the ground.
    static var surface: Color { theme.surface }

    /// A row or card on the phone's ground.
    static var card: Color { theme.card }

    /// The light this app pools into a corner, at `weight` of full strength: the hot
    /// core of it.
    static func glow(_ weight: Double) -> Color {
        cache.colour("glow\(weight)") { theme.glow.opacity(weight) }
    }

    /// The deeper falloff behind `glow`.
    static func glowDeep(_ weight: Double) -> Color {
        cache.colour("glowDeep\(weight)") { theme.glowDeep.opacity(weight) }
    }

    /// The accent with the lamp turned up, for a control under the pointer.
    static var accentHot: Color { theme.accentHot }

    /// The outline around a picked row.
    static func pickedEdge(hot: Bool) -> Color {
        hot ? theme.pickedEdgeHot : theme.pickedEdge
    }

    /// The search pill, and the text typed into it.
    static var field: Color { theme.field }
    static var fieldInk: Color { theme.fieldInk }
    static var fieldRaised: Color { theme.fieldRaised }

    /// Content on top of something filled: the accent, a coloured avatar, a scrim
    /// laid over artwork.
    ///
    /// A named token rather than a bare `.white` so it cannot be mistaken for one again.
    /// White in Classic in both appearances — what is underneath these does not change
    /// with the appearance, so neither does what sits on them. A theme with a very
    /// bright accent darkens it.
    static var onFill: Color { theme.onFill }

    /// Something finished, something wrong.
    static var good: Color { theme.good }
    static var warn: Color { theme.warn }

    /// Where a picked row's gradient goes as it crosses to the light.
    private static var pickedMid: Color { theme.pickedMid }
    private static var pickedFar: Color { theme.pickedFar }

    /// The drawer's surface: near-black with red light pooling in from the bottom-right
    /// and a faint sheen top-left, same as the hero and picked rows.
    static var sheetSurface: some View {
        ZStack {
            surface
            RadialGradient(
                stops: [
                    .init(color: glow(0.34), location: 0),
                    .init(color: glowDeep(0.12), location: 0.45),
                    .init(color: .clear, location: 0.76),
                ],
                center: UnitPoint(x: 1.04, y: 1.06),
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                stops: [
                    .init(color: sheen(0.06), location: 0),
                    .init(color: .clear, location: 0.62),
                ],
                center: UnitPoint(x: -0.08, y: -0.14),
                startRadius: 0,
                endRadius: 420
            )
        }
    }

    /// A kept row. The bookmark on the trailing edge is treated as the light source —
    /// the same red the rest of the app pools in from a corner, here leaking from the one
    /// element that makes this row different from its neighbours.
    ///
    /// Deliberately weaker than `pickedSurface`: a row can be kept *and* ticked, and when
    /// it is, the ticked state has to win. Keeping is a property of the video; ticking is
    /// something about to happen to it.
    ///
    /// Mac-only, and the one thing in this otherwise platform-clean file that is: the
    /// plate underneath is `.controlBackgroundColor`, which is AppKit's. The phone
    /// compiles this file in place and draws its own saved rows in `Views/Style.swift`,
    /// so the conditional costs iOS nothing and leaves the Mac's appearance untouched.
    #if os(macOS)
    /// A row's plate. AppKit's control background in Classic, which is what it always
    /// was; a theme's own surface otherwise, since AppKit's grey belongs to neither.
    static var rowPlate: Color {
        Theme.active.id == .classic ? Color(nsColor: .controlBackgroundColor) : surface
    }

    /// Behind the results lists: AppKit's under-page grey in Classic, the theme's ground
    /// and a faint trace of its scenery otherwise.
    @ViewBuilder
    static var page: some View {
        if Theme.active.id == .classic {
            Color(nsColor: .underPageBackgroundColor)
        } else {
            ZStack {
                ground
                ThemeBackdrop(strength: 0.45)
            }
        }
    }

    static func savedSurface(height: CGFloat) -> some View {
        ZStack {
            rowPlate
            RadialGradient(
                stops: [
                    .init(color: glow(0.22), location: 0),
                    .init(color: glowDeep(0.08), location: 0.42),
                    .init(color: .clear, location: 0.8),
                ],
                center: UnitPoint(x: 1.0, y: 0.5),
                startRadius: 0,
                endRadius: max(height * 2.4, 170)
            )
        }
    }
    #endif

    /// A row inside one of the favourites drawers. The same red light the hero throws
    /// from its bottom-right corner, turned right down — so the panel reads as part of
    /// the app rather than a list dropped onto it. At rest it is only a lift in the
    /// surface; the light arrives on hover.
    static func tileSurface(active: Bool) -> some View {
        ZStack {
            ink(active ? 0.075 : 0.04)
            if active {
                RadialGradient(
                    stops: [
                        .init(color: glow(0.30), location: 0),
                        .init(color: glowDeep(0.10), location: 0.48),
                        .init(color: .clear, location: 0.78),
                    ],
                    center: UnitPoint(x: 1.02, y: 1.18),
                    startRadius: 0,
                    endRadius: 168
                )
            }
        }
    }

    /// A picked row goes dark with red light pooling in from the bottom-right, echoing
    /// the hero, rather than just gaining a coloured outline.
    static func pickedSurface(height: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: surface, location: 0),
                    .init(color: pickedMid, location: 0.55),
                    .init(color: pickedFar, location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                stops: [
                    .init(color: glow(0.42), location: 0),
                    .init(color: glowDeep(0.16), location: 0.45),
                    .init(color: .clear, location: 0.72),
                ],
                center: UnitPoint(x: 1, y: 1.25),
                startRadius: 0,
                endRadius: max(height * 1.9, 120)
            )
            RadialGradient(
                stops: [
                    .init(color: sheen(0.07), location: 0),
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
                       : AnyShapeStyle(Palette.ink(0.06)),
                in: ThemedCapsule()
            )
    }
}

extension View {
    func chip(active: Bool = false) -> some View { modifier(ChipBackground(active: active)) }
}
