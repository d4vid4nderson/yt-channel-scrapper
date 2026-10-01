import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A whole look: colours, the geometry of every container, the edge drawn around it, the
/// typeface, and what sits behind the page.
///
/// `Palette` is the only thing views ask for colour, and it answers from `Theme.active`,
/// so a theme reaches the few hundred call sites without any of them knowing themes
/// exist. Shapes do the same through `ThemedRect` and `ThemedCapsule`. What a call site
/// has to opt into is only the decoration that is more than a colour — `themeEdge`, and
/// `displayType` for the handful of headings that carry a theme's lettering.
///
/// Compiled into both apps, like `Palette.swift` — see `ios/project.yml`. The platform
/// halves are the chrome at the bottom: AppKit's appearance on the Mac, UIKit's bar
/// appearances on the phone.
///
/// Classic is today's app, token for token, and follows the system's light or dark. The
/// others each pick one appearance, because a neon city at noon is not a thing.
struct Theme: Identifiable, @unchecked Sendable {

    enum ID: String, CaseIterable, Identifiable, Sendable {
        case classic, bladeRunner, dune, middleEarth, prancingPony, synthwave, grid, nostromo, nostromoTeal
        var id: String { rawValue }
    }

    enum Appearance: Sendable { case adaptive, dark, light }

    /// How a container's corners are cut. The radius a call site asks for is scaled, so
    /// a 14pt card and a 7pt button keep their relationship in every theme.
    enum Corners: Sendable {
        case rounded(scale: CGFloat)
        case chamfered(scale: CGFloat)
        case square
    }

    /// What `themeEdge` draws around a container, on top of its own hairline.
    enum Edge: Sendable {
        case none
        /// A lit tube of `edgeTint`, with a little light spilling off it.
        case neon
        /// A gilt double rule with an interlaced knot in each corner — elven work.
        case knotwork
        /// A carved bevel, dark below and lit above, with a brass nail at each corner.
        case carved
        /// Only the corners, as a targeting reticle draws them.
        case brackets
        /// `accent` running into `accent2` along the edge, and glowing.
        case gradient
        /// A short bar of `edgeTint` on the leading end of the top edge — a glyph mark.
        case notch
        /// A raised panel, the way a Winamp skin built its chrome: lit along the top,
        /// shadowed along the bottom, a sheen across the upper half, and a hairline of
        /// `edgeTint` inside. Lit (hover, selection) brightens it rather than glowing.
        case bevel
    }

    /// What stands behind the page where it is not covered.
    enum Backdrop: Sendable { case aurora, haze, dunes, parchment, tavern, sunset, grid, scanlines }

    /// The display a skin reads its title and time from — Winamp's LCD. A dark well set
    /// into the panel, its own lettering colour, and a little of that colour's light.
    struct LCD: Sendable {
        let background: Color
        let ink: Color
        let glow: Color
    }

    struct Typeface: @unchecked Sendable {
        /// Applied to every system font in the app through the environment.
        var design: Font.Design = .default
        /// Also app-wide. Standard in every theme now: a condensed or expanded body face
        /// stretched every label and list in the app, which read as distorted rather than
        /// as a look. Character belongs in the headings.
        var width: Font.Width = .standard
        /// Headings: the first of these faces the device has, else the system at
        /// `displayWeight`. A list because the Mac ships faces the phone does not.
        var display: [String] = []
        var displayWeight: Font.Weight = .bold
        var displayWidth: Font.Width = .standard
        var displayCaps = false
        var displayTracking: CGFloat = 0

        /// The display face this device actually has, if any.
        var displayName: String? { display.first(where: Theme.hasFont) }
    }

    static func hasFont(_ name: String) -> Bool {
        #if canImport(AppKit)
        NSFont(name: name, size: 12) != nil
        #else
        UIFont(name: name, size: 12) != nil
        #endif
    }

    let id: ID
    let name: String
    let tagline: String
    let appearance: Appearance

    /// Text and every hairline, at whatever weight `Palette.ink` is asked for.
    let ink: Color
    let accent: Color
    let accentHot: Color
    /// The second colour a theme has, where it has one: Blade Runner's cyan against its
    /// magenta, the Fremen blue against the spice.
    let accent2: Color
    /// What `themeEdge` draws in.
    let edgeTint: Color
    /// The brand badge. Only Classic differs from `accent`: its badge is YouTube-pure red
    /// in both appearances, where its accent deepens in the light for contrast.
    let brand: Color
    let ground: Color
    let surface: Color
    /// A row or card on the phone's ground.
    let card: Color
    let field: Color
    let fieldInk: Color
    /// A control sitting inside the field — the Mac search's tab menu.
    let fieldRaised: Color
    /// Content on an accent fill. Not always white: Nostromo's phosphor green and the
    /// Grid's cyan are too bright to put white on.
    let onFill: Color
    let good: Color
    let warn: Color
    let glow: Color
    let glowDeep: Color
    let pickedMid: Color
    let pickedFar: Color
    let pickedEdge: Color
    let pickedEdgeHot: Color

    let corners: Corners
    let edge: Edge
    let type: Typeface
    let backdrop: Backdrop
    /// Four disc colours for the Mac's corner bloom, hottest first. Empty keeps Classic's
    /// own hand-tuned set.
    let aurora: [Color]
    /// Nil in Classic, which has no skin to set a display into.
    let lcd: LCD?

    var colorScheme: ColorScheme? {
        switch appearance {
        case .adaptive: nil
        case .dark: .dark
        case .light: .light
        }
    }

    var isLight: Bool { appearance == .light }
}

// MARK: - The themes

extension Theme {

    static let all: [Theme] = ID.allCases.map(named)

    static func named(_ id: ID) -> Theme {
        switch id {
        case .classic: classic
        case .bladeRunner: bladeRunner
        case .dune: dune
        case .middleEarth: middleEarth
        case .prancingPony: prancingPony
        case .synthwave: synthwave
        case .grid: grid
        case .nostromo: nostromo
        case .nostromoTeal: nostromoTeal
        }
    }

    /// The app as it has always been. Every value here is the one `Palette` held before
    /// themes existed, with the reasoning that picked it kept beside it.
    static let classic: Theme = {
        let d = Palette.adaptive
        let red = Color(red: 1, green: 0, blue: 0)
        return Theme(
            id: .classic,
            name: "Classic",
            tagline: "Red on near-black, the way it started",
            appearance: .adaptive,
            ink: .white,
            // `--accent #ff0000`, and a touch deeper in the light. Pure red on white is
            // about 4:1 against the background, which is under the bar for text and for
            // anything small enough to be a glyph. #d40000 clears it without reading as a
            // different red.
            accent: d(red, Color(red: 0.83, green: 0, blue: 0)),
            accentHot: d(Color(red: 1, green: 0.13, blue: 0.2),
                         Color(red: 0.92, green: 0.06, blue: 0.10)),
            accent2: d(red, Color(red: 0.83, green: 0, blue: 0)),
            edgeTint: d(red, Color(red: 0.83, green: 0, blue: 0)),
            brand: red,
            ground: d(Color(red: 0.059, green: 0.059, blue: 0.059),      // #0f0f0f
                      Color(red: 0.965, green: 0.965, blue: 0.970)),     // #f6f6f7
            surface: d(Color(red: 0.071, green: 0.071, blue: 0.071),     // #121212
                       Color(red: 1, green: 1, blue: 1)),
            card: d(Color(red: 0.094, green: 0.094, blue: 0.094), .white),
            // The search pill is a light element in both appearances. Inverting it would
            // be wrong — it is bright on purpose, the one thing on the hero you are meant
            // to type into. But bright against near-black carries its own edge and bright
            // against near-white does not, so the light one goes all the way to white and
            // takes a hairline instead.
            field: d(Color(white: 0.89), Color(white: 1)),
            fieldInk: .black,
            fieldRaised: .white,
            // What is underneath a fill does not change with the appearance — red stays
            // red, a thumbnail stays a photograph — so neither does what sits on it.
            onFill: .white,
            good: d(Color(red: 0.35, green: 0.82, blue: 0.45),
                    Color(red: 0.13, green: 0.55, blue: 0.25)),
            warn: d(Color(red: 1, green: 0.72, blue: 0.35),
                    Color(red: 0.72, green: 0.44, blue: 0.02)),
            // The red light this app pools into a corner. Light mode takes a little over
            // half: the same wash that reads as a glow against near-black reads as a stain
            // on white, and the point of it is the light, not the colour.
            glow: d(Color(red: 1, green: 0.18, blue: 0.24),
                    Color(red: 1, green: 0.34, blue: 0.30).opacity(0.58)),
            glowDeep: d(Color(red: 0.75, green: 0.08, blue: 0.14),
                        Color(red: 0.97, green: 0.52, blue: 0.44).opacity(0.58)),
            // Where a picked row's gradient goes as it crosses to the light: near-black
            // warming towards the red in the dark, white warming towards a blush in the
            // light.
            pickedMid: d(Color(red: 0.098, green: 0.067, blue: 0.075),
                         Color(red: 0.996, green: 0.965, blue: 0.965)),
            pickedFar: d(Color(red: 0.169, green: 0.071, blue: 0.094),
                         Color(red: 0.992, green: 0.925, blue: 0.925)),
            // The outline around a picked row: the warm near-black the row itself fades
            // to, a shade further on — and in the light, the blush, a shade deeper.
            pickedEdge: d(Color(red: 0.20, green: 0.10, blue: 0.11),
                          Color(red: 0.95, green: 0.81, blue: 0.81)),
            pickedEdgeHot: d(Color(red: 0.29, green: 0.13, blue: 0.15),
                             Color(red: 0.93, green: 0.72, blue: 0.72)),
            corners: .rounded(scale: 1),
            edge: .none,
            type: Typeface(),
            backdrop: .aurora,
            aurora: [],
            lcd: nil
        )
    }()

    /// Los Angeles and the dead Las Vegas, 2049. Not the first film's neon: smog lit
    /// amber from inside, concrete, cold teal in the shadows, and dust hanging in the air.
    /// Thin, light capitals; a bevelled panel rather than a glowing tube.
    static let bladeRunner = Theme(
        id: .bladeRunner,
        name: "Blade Runner 2049",
        tagline: "Amber haze over a dead city",
        appearance: .dark,
        ink: hex(0xE6DED2),
        accent: hex(0xD9792E),
        accentHot: hex(0xEC8E45),
        accent2: hex(0x7FA6A8),
        edgeTint: hex(0xB8692C),
        brand: hex(0xD9792E),
        ground: hex(0x0C0B0A),
        surface: hex(0x141210),
        card: hex(0x1A1714).opacity(0.92),
        field: hex(0x1C1916),
        fieldInk: hex(0xE6DED2),
        fieldRaised: hex(0x2A2520),
        onFill: hex(0x160C05),
        good: hex(0x9DB88A),
        warn: hex(0xE8A64A),
        glow: hex(0xC8692A),
        glowDeep: hex(0x4A2A16),
        pickedMid: hex(0x1A130E),
        pickedFar: hex(0x2A1A10),
        pickedEdge: hex(0x4A3020),
        pickedEdgeHot: hex(0x6A4228),
        corners: .rounded(scale: 0.3),
        edge: .bevel,
        type: Typeface(displayWeight: .light, displayCaps: true, displayTracking: 1.6),
        backdrop: .haze,
        aurora: [hex(0xD9792E), hex(0xA9542A), hex(0x4A2A16), hex(0x7FA6A8)],
        lcd: LCD(background: hex(0x0A0806), ink: hex(0xF0A05A), glow: hex(0xD9792E))
    )

    /// Arrakis at dusk. Umber and sand, spice orange for anything that matters, and the
    /// blue of Fremen eyes as the rare second colour. Thin, spaced capitals.
    static let dune = Theme(
        id: .dune,
        name: "Dune",
        tagline: "Sand, spice and a long horizon",
        appearance: .dark,
        ink: hex(0xF0DEC0),
        accent: hex(0xE0822F),
        accentHot: hex(0xF29A45),
        accent2: hex(0x6FB3E8),
        edgeTint: hex(0xE0822F),
        brand: hex(0xE0822F),
        ground: hex(0x130C06),
        surface: hex(0x1B120A),
        card: hex(0x22170E).opacity(0.9),
        field: hex(0x2A1C10),
        fieldInk: hex(0xF0DEC0),
        fieldRaised: hex(0x3A2816),
        onFill: hex(0x1B1007),
        good: hex(0xB7C46A),
        warn: hex(0xF4C55A),
        glow: hex(0xE0822F),
        glowDeep: hex(0x7A3A12),
        pickedMid: hex(0x1F140B),
        pickedFar: hex(0x2E1C0D),
        pickedEdge: hex(0x4A2E15),
        pickedEdgeHot: hex(0x6A3F1A),
        corners: .square,
        edge: .bevel,
        type: Typeface(displayWeight: .light, displayCaps: true, displayTracking: 2),
        backdrop: .dunes,
        aurora: [hex(0xE0822F), hex(0xF2B45A), hex(0x8A3C12), hex(0xF7D08A)],
        lcd: LCD(background: hex(0x0E0804), ink: hex(0xF2B45A), glow: hex(0xE0822F))
    )

    /// A page from the Red Book, bound in Rivendell. Sepia ink on parchment, gilt rules,
    /// oxblood for the things you press, and
    /// Luminari's uncial-flavoured capitals on the Mac — the phone has no such face and
    /// sets its headings in Baskerville.
    static let middleEarth = Theme(
        id: .middleEarth,
        name: "Middle-earth",
        tagline: "Sepia ink, parchment and gilt",
        appearance: .light,
        ink: hex(0x3A2814),
        accent: hex(0x8E2A1C),
        accentHot: hex(0xA8321F),
        accent2: hex(0xA9822F),
        edgeTint: hex(0xA9822F),
        brand: hex(0x8E2A1C),
        ground: hex(0xEADDBE),
        surface: hex(0xF4EAD2),
        card: hex(0xF4E9CE).opacity(0.92),
        field: hex(0xFBF4E2),
        fieldInk: hex(0x3A2814),
        fieldRaised: hex(0xEFE2C2),
        onFill: hex(0xFBF4E2),
        good: hex(0x4E6B2A),
        warn: hex(0xA0621A),
        glow: hex(0xC9A04A).opacity(0.7),
        glowDeep: hex(0x8E5A2A).opacity(0.6),
        pickedMid: hex(0xF0E2C0),
        pickedFar: hex(0xE7D2A4),
        pickedEdge: hex(0xD6BC86),
        pickedEdgeHot: hex(0xC4A260),
        corners: .rounded(scale: 0.4),
        // The skin's bevel with its gilt rule, not a knot in every corner: on every row,
        // card and button at once that was a page of swirls.
        edge: .bevel,
        type: Typeface(design: .serif, display: ["Luminari-Regular", "Baskerville-SemiBold"],
                       displayCaps: true, displayTracking: 0.8),
        backdrop: .parchment,
        aurora: [hex(0xD8B86A), hex(0xE2C98E), hex(0xC49A58), hex(0xEAD7A8)],
        // A page, so the display is a darker panel of the same paper with sepia on it
        // rather than a lit screen — there is nothing electric in Rivendell.
        lcd: LCD(background: hex(0xE2D1A8), ink: hex(0x3A2814), glow: .clear)
    )

    /// The Prancing Pony, Bree. Dark oak and firelight, brass on everything that is held,
    /// ale-red for what you press, and the inn sign's painted capitals.
    static let prancingPony = Theme(
        id: .prancingPony,
        name: "The Prancing Pony",
        tagline: "Oak beams, firelight and a pint in Bree",
        appearance: .dark,
        ink: hex(0xF3E3C3),
        accent: hex(0xD9A441),
        accentHot: hex(0xF0BE5A),
        accent2: hex(0x9A3A2C),
        edgeTint: hex(0xC8963A),
        brand: hex(0xD9A441),
        ground: hex(0x160D07),
        surface: hex(0x22150C),
        card: hex(0x2A1A0F).opacity(0.92),
        field: hex(0x2E1D11),
        fieldInk: hex(0xF3E3C3),
        fieldRaised: hex(0x3E2816),
        onFill: hex(0x1E1208),
        good: hex(0x9DB86A),
        warn: hex(0xE8A13A),
        glow: hex(0xFF8A2A),
        glowDeep: hex(0x7A2E12),
        pickedMid: hex(0x2A190D),
        pickedFar: hex(0x3A200F),
        pickedEdge: hex(0x5A3A18),
        pickedEdgeHot: hex(0x7A5020),
        corners: .rounded(scale: 0.25),
        edge: .carved,
        type: Typeface(design: .serif, display: ["Copperplate-Bold"],
                       displayCaps: true, displayTracking: 0.5),
        backdrop: .tavern,
        aurora: [hex(0xFF8A2A), hex(0xD9A441), hex(0x7A2E12), hex(0xFFC46B)],
        lcd: LCD(background: hex(0x0F0804), ink: hex(0xF0BE5A), glow: hex(0xD9A441))
    )

    /// 1986, on a VHS cover. A violet sky with stars over a magenta floor, chrome panels,
    /// and heavy italic capitals. No sun: it sat behind whatever was centred on the page.
    static let synthwave = Theme(
        id: .synthwave,
        name: "Synthwave",
        tagline: "Chrome sunsets and a magenta grid",
        appearance: .dark,
        ink: hex(0xFCE8FF),
        accent: hex(0xFF2A6D),
        accentHot: hex(0xFF5A8C),
        accent2: hex(0x05D9E8),
        edgeTint: hex(0xFF2A6D),
        brand: hex(0xFF2A6D),
        ground: hex(0x0D0221),
        surface: hex(0x140433),
        card: hex(0x1A083D).opacity(0.88),
        field: hex(0x1E0B45),
        fieldInk: hex(0xFCE8FF),
        fieldRaised: hex(0x2E1560),
        onFill: .white,
        good: hex(0x05FFA1),
        warn: hex(0xFFD319),
        glow: hex(0xFF2A6D),
        glowDeep: hex(0x7B2CBF),
        pickedMid: hex(0x1C0838),
        pickedFar: hex(0x2E0B45),
        pickedEdge: hex(0x4A1260),
        pickedEdgeHot: hex(0x6A1A80),
        corners: .rounded(scale: 0.6),
        edge: .bevel,
        type: Typeface(display: ["AvenirNext-HeavyItalic"],
                       displayCaps: true, displayTracking: 0.4),
        backdrop: .sunset,
        aurora: [hex(0xFF2A6D), hex(0xFF8C42), hex(0x7B2CBF), hex(0xFFD319)],
        lcd: LCD(background: hex(0x08011A), ink: hex(0x05D9E8), glow: hex(0x05D9E8))
    )

    /// Inside the machine, 1982. Black, light cycles drawing their trails low across it,
    /// and corners cut on the diagonal rather than rounded. No grid on the backdrop: it
    /// sat over everything as a mesh.
    static let grid = Theme(
        id: .grid,
        name: "The Grid",
        tagline: "Lines of light inside the machine",
        appearance: .dark,
        ink: hex(0xD6FBFF),
        accent: hex(0x18E4FF),
        accentHot: hex(0x7FF3FF),
        accent2: hex(0xFF9B26),
        edgeTint: hex(0x18E4FF),
        brand: hex(0x18E4FF),
        ground: hex(0x000407),
        surface: hex(0x02090E),
        card: hex(0x041017).opacity(0.9),
        field: hex(0x051620),
        fieldInk: hex(0xD6FBFF),
        fieldRaised: hex(0x0A2A3A),
        onFill: hex(0x00141A),
        good: hex(0x6CFFB0),
        warn: hex(0xFF9B26),
        glow: hex(0x18E4FF),
        glowDeep: hex(0x0A4A7A),
        pickedMid: hex(0x03141C),
        pickedFar: hex(0x062431),
        pickedEdge: hex(0x0E3F52),
        pickedEdgeHot: hex(0x146680),
        corners: .chamfered(scale: 0.9),
        edge: .bevel,
        type: Typeface(displayWeight: .semibold, displayCaps: true, displayTracking: 1.6),
        backdrop: .grid,
        aurora: [hex(0x18E4FF), hex(0x0A6FA8), hex(0x0B3D66), hex(0x7FF3FF)],
        lcd: LCD(background: hex(0x00070A), ink: hex(0x7FF3FF), glow: hex(0x18E4FF))
    )

    /// MU-TH-UR 6000, the ship's computer. Green phosphor on black glass, monospaced
    /// type, scanlines, and bracketed corners instead of boxes. Amber for warnings.
    static let nostromo = Theme(
        id: .nostromo,
        name: "Nostromo",
        tagline: "Green phosphor on the ship's terminal",
        appearance: .dark,
        ink: hex(0x9CFFB4),
        accent: hex(0x3DFF7A),
        accentHot: hex(0x8CFFAE),
        accent2: hex(0xFFB000),
        edgeTint: hex(0x3DFF7A),
        brand: hex(0x3DFF7A),
        ground: hex(0x010602),
        surface: hex(0x020E07),
        card: hex(0x03140A).opacity(0.9),
        field: hex(0x03180C),
        fieldInk: hex(0x9CFFB4),
        fieldRaised: hex(0x0A2E16),
        onFill: hex(0x011006),
        good: hex(0x3DFF7A),
        warn: hex(0xFFB000),
        glow: hex(0x3DFF7A),
        glowDeep: hex(0x0B5A26),
        pickedMid: hex(0x03170B),
        pickedFar: hex(0x062812),
        pickedEdge: hex(0x0E3F1C),
        pickedEdgeHot: hex(0x146A2E),
        corners: .square,
        edge: .brackets,
        type: Typeface(design: .monospaced, displayWeight: .bold,
                       displayCaps: true, displayTracking: 1.2),
        backdrop: .scanlines,
        aurora: [hex(0x3DFF7A), hex(0x1A8A3C), hex(0x0B5A26), hex(0x9CFFB4)],
        lcd: LCD(background: hex(0x000A03), ink: hex(0x3DFF7A), glow: hex(0x3DFF7A))
    )

    /// The same terminal, a different tube: teal and cyan phosphor, amber still for
    /// warnings.
    static let nostromoTeal = Theme(
        id: .nostromoTeal,
        name: "Nostromo Teal",
        tagline: "The ship's terminal, on a cyan tube",
        appearance: .dark,
        ink: hex(0x9CF6FF),
        accent: hex(0x2EE8E0),
        accentHot: hex(0x8AFFF8),
        accent2: hex(0xFFB000),
        edgeTint: hex(0x2EE8E0),
        brand: hex(0x2EE8E0),
        ground: hex(0x010607),
        surface: hex(0x021012),
        card: hex(0x031619).opacity(0.9),
        field: hex(0x03191C),
        fieldInk: hex(0x9CF6FF),
        fieldRaised: hex(0x0A2E33),
        onFill: hex(0x011214),
        good: hex(0x3DFFC8),
        warn: hex(0xFFB000),
        glow: hex(0x2EE8E0),
        glowDeep: hex(0x0B4F5A),
        pickedMid: hex(0x031A1C),
        pickedFar: hex(0x062A2E),
        pickedEdge: hex(0x0E3F44),
        pickedEdgeHot: hex(0x146A70),
        corners: .square,
        edge: .brackets,
        type: Typeface(design: .monospaced, displayWeight: .bold,
                       displayCaps: true, displayTracking: 1.2),
        backdrop: .scanlines,
        aurora: [hex(0x2EE8E0), hex(0x1A7F8A), hex(0x0B4F5A), hex(0x9CF6FF)],
        lcd: LCD(background: hex(0x00090A), ink: hex(0x2EE8E0), glow: hex(0x2EE8E0))
    )

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - Which one is on

extension Theme {

    /// The theme every token is read from. Behind a lock rather than on the main actor
    /// because `Palette` and the shapes are read from wherever SwiftUI draws.
    static var active: Theme { box.read() }

    static let defaultsKey = "appearance.theme.v1"

    fileprivate static func activate(_ id: ID) { box.write(named(id)) }

    private static let box = Box()

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var theme: Theme = {
            let saved = UserDefaults.standard.string(forKey: Theme.defaultsKey)
            return Theme.named(saved.flatMap(ID.init(rawValue:)) ?? .classic)
        }()

        func read() -> Theme {
            lock.lock()
            defer { lock.unlock() }
            return theme
        }

        func write(_ new: Theme) {
            lock.lock()
            theme = new
            lock.unlock()
        }
    }
}

/// The choice, for views to bind to. Per device: a child picking Synthwave for their own
/// phone should not repaint a parent's Mac.
@MainActor @Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var selection: Theme.ID {
        didSet {
            guard selection != oldValue else { return }
            Theme.activate(selection)
            UserDefaults.standard.set(selection.rawValue, forKey: Theme.defaultsKey)
            ThemeChrome.apply(theme)
            ThemeChrome.applyIcon(theme)
        }
    }

    var theme: Theme { Theme.named(selection) }

    private init() {
        selection = Theme.active.id
        ThemeChrome.apply(Theme.active)
    }
}

/// Puts a theme over a window's content.
///
/// The `.id` is what makes a switch take: tokens are read while a body is built, so
/// nothing that has already been built would notice a new theme otherwise. Rebuilding
/// the tree costs a flicker once, when you pick one, and nothing at any other time. Put
/// it *below* any `@State` that must survive — the phone's `AppModel` lives above it.
struct ThemedRoot<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let theme = ThemeStore.shared.theme
        content
            .fontDesign(theme.type.design)
            .fontWidth(theme.type.width)
            .foregroundStyle(theme.id == .classic
                             ? AnyShapeStyle(.primary) : AnyShapeStyle(Palette.ink(1)))
            .tint(Palette.accent)
            .preferredColorScheme(Self.scheme(theme))
            .modifier(ThemedButtons(on: theme.id != .classic))
            .id(theme.id)
    }
}

extension ThemedRoot {
    /// Classic follows the system on the Mac. The phone has always been dark in Classic,
    /// and a `nil` here would override the `.dark` its screens ask for.
    fileprivate static func scheme(_ theme: Theme) -> ColorScheme? {
        #if canImport(AppKit)
        theme.colorScheme
        #else
        theme.colorScheme ?? .dark
        #endif
    }
}

/// Every button left on the system's default style, in the theme's instead — Set up…,
/// Sync, Done. A button that asked for a style of its own (`.plain`, `.bordered`) keeps
/// it: those are the ones that already draw themselves in the palette.
///
/// Mac only. The phone's default buttons are text rows in forms and menus, which is
/// right for them in any theme.
struct ThemedButtons: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        #if canImport(AppKit)
        if on { content.buttonStyle(ThemedButtonStyle()) } else { content }
        #else
        content
        #endif
    }
}

struct ThemedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ThemedButtonBody(configuration: configuration)
    }

    struct ThemedButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            let theme = Theme.active
            let destructive = configuration.role == .destructive
            let tint = destructive ? theme.warn : theme.edgeTint
            let lit = hovering && enabled
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive ? AnyShapeStyle(theme.warn) : AnyShapeStyle(Palette.ink(0.92)))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(
                    configuration.isPressed ? tint.opacity(0.30)
                        : lit ? tint.opacity(0.18) : Palette.ink(0.07),
                    in: ThemedCapsule())
                .overlay(ThemedCapsule().strokeBorder(tint.opacity(lit ? 0.8 : 0.4), lineWidth: 1))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(ThemedCapsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

extension View {
    /// The theme's button style, for a sheet: a sheet is presented in a window of its
    /// own and does not inherit it from `themed()`.
    func themedButtons() -> some View {
        modifier(ThemedButtons(on: Theme.active.id != .classic))
    }

    func themed() -> some View { ThemedRoot { self } }
}

// MARK: - Shapes

/// `RoundedRectangle`, cut the way the theme cuts corners. Same initialiser, so a call
/// site changes by one word; Classic draws exactly the rectangle it replaced.
struct ThemedRect: InsettableShape {
    var cornerRadius: CGFloat
    var style: RoundedCornerStyle = .circular
    private var inset: CGFloat = 0

    init(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {
        self.cornerRadius = cornerRadius
        self.style = style
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        switch Theme.active.corners {
        case .rounded(let scale):
            return RoundedRectangle(cornerRadius: max(cornerRadius * scale - inset, 0),
                                    style: style).path(in: r)
        case .chamfered(let scale):
            return Chamfer(cut: max(cornerRadius * scale - inset * 0.4, 0)).path(in: r)
        case .square:
            return Rectangle().path(in: r)
        }
    }

    func inset(by amount: CGFloat) -> ThemedRect {
        var copy = self
        copy.inset += amount
        return copy
    }
}

/// `Capsule`, likewise. A pill only stays a pill in themes whose corners are fully round.
struct ThemedCapsule: InsettableShape {
    var style: RoundedCornerStyle = .circular
    private var inset: CGFloat = 0

    init(style: RoundedCornerStyle = .circular) { self.style = style }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let half = min(r.width, r.height) / 2
        switch Theme.active.corners {
        case .rounded(let scale) where scale >= 1:
            return Capsule(style: style).path(in: r)
        case .rounded(let scale):
            return RoundedRectangle(cornerRadius: half * scale, style: style).path(in: r)
        case .chamfered(let scale):
            return Chamfer(cut: half * 0.7 * scale).path(in: r)
        case .square:
            return Rectangle().path(in: r)
        }
    }

    func inset(by amount: CGFloat) -> ThemedCapsule {
        var copy = self
        copy.inset += amount
        return copy
    }
}

/// A rectangle with its top-leading and bottom-trailing corners cut off on the diagonal —
/// two, not four, which is what makes it read as machined rather than as an octagon.
struct Chamfer: Shape {
    var cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = min(cut, rect.width / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.closeSubpath()
        return p
    }
}

/// The four corners of a rectangle and nothing between them.
private struct Brackets: Shape {
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        let l = min(length, rect.width / 3, rect.height / 3)
        var p = Path()
        for (corner, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
            (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
            (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
        ] {
            p.move(to: CGPoint(x: corner.x, y: corner.y + dy * l))
            p.addLine(to: corner)
            p.addLine(to: CGPoint(x: corner.x + dx * l, y: corner.y))
        }
        return p
    }
}

// MARK: - Edges

extension View {
    /// The theme's border treatment round a container whose shape is
    /// `ThemedRect(cornerRadius: radius)`. `lit` is hover or selection: the edge brightens
    /// rather than the container changing shape. Nothing at all in Classic.
    func themeEdge(radius: CGFloat, lit: Bool = false) -> some View {
        themeEdge(ThemedRect(cornerRadius: radius, style: .continuous), lit: lit)
    }

    /// The same, round any themed shape — the search pill's `ThemedCapsule`.
    func themeEdge<S: InsettableShape>(_ shape: S, lit: Bool = false) -> some View {
        overlay { ThemeEdgeView(shape: shape, lit: lit).allowsHitTesting(false) }
    }
}

private struct ThemeEdgeView<S: InsettableShape>: View {
    let shape: S
    let lit: Bool

    var body: some View {
        let theme = Theme.active
        switch theme.edge {
        case .none:
            EmptyView()
        case .neon:
            shape
                .strokeBorder(theme.edgeTint.opacity(lit ? 0.95 : 0.55), lineWidth: 1)
                .shadow(color: theme.edgeTint.opacity(lit ? 0.8 : 0.45), radius: lit ? 7 : 4)
        case .gradient:
            shape
                .strokeBorder(
                    LinearGradient(colors: [theme.accent, theme.accent2],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(lit ? 1 : 0.7),
                    lineWidth: 1.2
                )
                .shadow(color: theme.accent.opacity(lit ? 0.7 : 0.4), radius: lit ? 8 : 5)
        case .knotwork:
            ZStack {
                shape.strokeBorder(theme.edgeTint.opacity(lit ? 0.9 : 0.65), lineWidth: 1)
                shape.inset(by: 3.5)
                    .stroke(theme.edgeTint.opacity(lit ? 0.55 : 0.35), lineWidth: 0.6)
                // A knot at each corner, sitting over the join of the two rules.
                Canvas { c, size in
                    let side = min(18, min(size.width, size.height) * 0.36)
                    guard side >= 10 else { return }
                    let o: CGFloat = 1
                    for (x, y) in [(o, o), (size.width - side - o, o),
                                   (o, size.height - side - o),
                                   (size.width - side - o, size.height - side - o)] {
                        Knot.trefoil.draw(in: &c, rect: CGRect(x: x, y: y, width: side, height: side),
                                          ink: .color(theme.edgeTint.opacity(lit ? 1 : 0.85)),
                                          gap: theme.surface, width: max(1, side * 0.09))
                    }
                }
            }
        case .carved:
            ZStack {
                // Light from above: the top edge catches it, the bottom falls into shadow.
                shape.strokeBorder(
                    LinearGradient(colors: [theme.ink.opacity(0.22), .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 2)
                shape.inset(by: 2)
                    .stroke(theme.edgeTint.opacity(lit ? 0.65 : 0.35), lineWidth: 0.8)
                Canvas { c, size in
                    guard min(size.width, size.height) >= 22 else { return }
                    let r: CGFloat = 2.4, o: CGFloat = 6
                    for (x, y) in [(o, o), (size.width - o, o), (o, size.height - o),
                                   (size.width - o, size.height - o)] {
                        let nail = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        c.fill(Path(ellipseIn: nail), with: .radialGradient(
                            Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.6), theme.edgeTint,
                                              Color(red: 0.25, green: 0.15, blue: 0.05)]),
                            center: CGPoint(x: x - r * 0.35, y: y - r * 0.35),
                            startRadius: 0, endRadius: r * 1.4))
                    }
                }
            }
        case .brackets:
            Brackets(length: 9)
                .stroke(theme.edgeTint.opacity(lit ? 1 : 0.7),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                .shadow(color: theme.edgeTint.opacity(0.5), radius: 3)
        case .notch:
            Rectangle()
                .fill(theme.edgeTint.opacity(lit ? 1 : 0.8))
                .frame(width: 22, height: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .bevel:
            Bevel(shape: shape, lit: lit)
        }
    }
}

// MARK: - Skin chrome

/// A raised panel, lit from above: the bevel every Winamp skin built its chrome from.
///
/// Three passes inside the shape. A rim that is light along the top and dark along the
/// bottom, which is all a bevel is; a sheen over the upper half, which is what makes it
/// read as moulded plastic or brushed metal rather than as a line drawing; and a hairline
/// of the theme's tint just inside, so each skin's panels carry its colour. `pressed`
/// turns the light round, as a button pushed into the panel would.
struct Bevel<S: InsettableShape>: View {
    let shape: S
    var lit = false
    var pressed = false

    var body: some View {
        let theme = Theme.active
        let light = theme.isLight ? Color.white.opacity(0.75) : theme.ink.opacity(lit ? 0.30 : 0.20)
        let dark = theme.isLight ? theme.ink.opacity(0.28) : Color.black.opacity(0.65)
        let (top, bottom) = pressed ? (dark, light) : (light, dark)
        ZStack {
            shape.inset(by: 1)
                .fill(LinearGradient(
                    stops: [.init(color: (theme.isLight ? Color.white : theme.ink)
                                    .opacity(pressed ? 0 : lit ? 0.09 : 0.055), location: 0),
                            .init(color: .clear, location: 0.5)],
                    startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(
                LinearGradient(stops: [.init(color: top, location: 0),
                                       .init(color: top.opacity(0.25), location: 0.45),
                                       .init(color: bottom.opacity(0.4), location: 0.6),
                                       .init(color: bottom, location: 1)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
            shape.inset(by: 1.5)
                .stroke(theme.edgeTint.opacity(lit ? 0.55 : 0.28), lineWidth: 0.6)
        }
    }
}

extension View {
    /// Set into the theme's LCD, the way a skin's player showed its title and time: a
    /// dark well sunk into the panel (lit along the bottom, shadowed along the top — the
    /// bevel turned inward), the display's own colour, and a trace of its light. Nothing
    /// in Classic.
    @ViewBuilder
    func lcdWell(padding: EdgeInsets = EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9),
                 radius: CGFloat = 6) -> some View {
        if let lcd = Theme.active.lcd {
            let shape = ThemedRect(cornerRadius: radius, style: .continuous)
            self
                .foregroundStyle(lcd.ink)
                .shadow(color: lcd.glow.opacity(0.45), radius: 2.5)
                .padding(padding)
                .background(lcd.background, in: shape)
                .overlay { Bevel(shape: shape, pressed: true).allowsHitTesting(false) }
                .environment(\.lcdInk, lcd.ink)
        } else {
            self
        }
    }
}

extension EnvironmentValues {
    /// The LCD's lettering colour, for anything inside a well that draws its own colours
    /// (the Now Playing waveform) rather than taking the foreground style.
    @Entry var lcdInk: Color? = nil
}

// MARK: - Knotwork

/// An interlaced knot: a closed curve drawn as a ribbon that passes alternately over and
/// under itself at every crossing, which is the whole of what makes a line read as
/// Celtic work rather than as a scribble.
///
/// The curves are (2, q) torus knots, whose plain projection is alternating: walk along
/// the curve and the crossings go over, under, over… So the crossings are found once,
/// numerically, and every second one along the curve gets its passage redrawn on top with
/// a gap either side — nothing needs to know which is which beyond that.
struct Knot: Sendable {
    /// In a unit square.
    let points: [CGPoint]
    /// Index ranges of `points` that pass over at a crossing.
    let overs: [ClosedRange<Int>]

    /// Three lobes: the trefoil, the triquetra's knotted cousin.
    static let trefoil = Knot(lobes: 3, samples: 240, depth: 0.55)

    init(lobes q: Int, samples n: Int, depth: CGFloat) {
        var raw: [CGPoint] = []
        for i in 0..<n {
            let phi = Double(i) / Double(n) * 2 * .pi
            let r = 1 + Double(depth) * cos(Double(q) * phi)
            raw.append(CGPoint(x: r * cos(2 * phi), y: r * sin(2 * phi)))
        }
        let extent = 1 + depth
        points = raw.map { CGPoint(x: ($0.x / extent + 1) / 2, y: ($0.y / extent + 1) / 2) }

        // Every crossing, as the two sample indices that meet there.
        var hits: [(Int, Int)] = []
        func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
            func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
                (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
            }
            return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0
        }
        // `i` stops two short of the end: `i + 2..<n` is an empty — or, past that, an
        // invalid — range, and adjacent segments always touch without crossing.
        for i in 0..<(n - 2) {
            for j in (i + 2)..<n where !(i == 0 && j == n - 1) {
                if cross(points[i], points[(i + 1) % n], points[j], points[(j + 1) % n]) {
                    hits.append((i, j))
                }
            }
        }
        // Along the curve, the passages alternate over and under.
        let passages = hits.flatMap { [$0.0, $0.1] }.sorted()
        let reach = max(3, n / (q * 14))
        overs = passages.enumerated().compactMap { k, index in
            k.isMultiple(of: 2) ? (index - reach)...(index + reach) : nil
        }
    }

    /// `gap` is unused now that gaps are cut rather than painted; kept so the call sites
    /// read as what they draw on.
    func draw(in c: inout GraphicsContext, rect: CGRect, ink: GraphicsContext.Shading,
              gap: Color, width: CGFloat) {
        let n = points.count
        func at(_ i: Int) -> CGPoint {
            let p = points[((i % n) + n) % n]
            return CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
        }
        var whole = Path()
        whole.move(to: at(0))
        for i in 1...n { whole.addLine(to: at(i)) }
        let passes: [Path] = overs.map { range in
            var pass = Path()
            pass.move(to: at(range.lowerBound))
            for i in range.dropFirst() { pass.addLine(to: at(i)) }
            return pass
        }
        // In a layer of its own, so the gaps are cut through to whatever is underneath
        // rather than painted in a colour that only nearly matches it: over parchment
        // or a card, a painted gap showed as a tick at each end.
        c.drawLayer { layer in
            layer.stroke(whole, with: ink, style: StrokeStyle(lineWidth: width, lineJoin: .round))
            layer.blendMode = .destinationOut
            for pass in passes {
                layer.stroke(pass, with: .color(.black),
                             style: StrokeStyle(lineWidth: width * 2.8, lineCap: .butt))
            }
            layer.blendMode = .normal
            for pass in passes {
                layer.stroke(pass, with: ink, style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }
}

// MARK: - Lettering

extension Font {
    /// A heading in the theme's lettering. Headings only: the named faces are chosen for
    /// character, not for reading a paragraph in. Classic keeps the system face at
    /// `classic`, the weight the heading had before themes.
    static func display(_ size: CGFloat, classic: Font.Weight = .bold) -> Font {
        let theme = Theme.active
        if theme.id == .classic { return .system(size: size, weight: classic) }
        if let name = theme.type.displayName { return .custom(name, size: size) }
        return .system(size: size, weight: theme.type.displayWeight).width(theme.type.displayWidth)
    }
}

extension View {
    /// `Font.display`, with the theme's capitals and spacing.
    func displayType(_ size: CGFloat, classic: Font.Weight = .bold) -> some View {
        let type = Theme.active.type
        return font(.display(size, classic: classic))
            .textCase(type.displayCaps ? .uppercase : nil)
            .tracking(type.displayTracking * min(size, 24) / 20)
    }
}

// MARK: - Backdrop

/// What a theme puts behind the page, and how it moves.
///
/// Every frame is drawn from a clock rather than animated state, so a scene is a pure
/// function of time: the rain is the same rain wherever you look away and back, and there
/// is nothing to get out of step. Capped at 30 frames a second — it sits under a phone's
/// lists all day, and nobody is watching the background closely enough to see 60.
///
/// Still, not moving, under Reduce Motion and in Low Power Mode. Nothing flashes or
/// flickers in any theme: this is on a child's screen.
///
/// Classic's is nothing — its aurora is the Mac's own `AuroraBackground`.
struct ThemeBackdrop: View {
    var strength: Double = 1
    /// Only the CRT's own lines and roll, lighter, for laying *over* content — see
    /// `CRTGlass`. Ignored by every scene but the scanlines.
    var glass = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = Theme.active
        Group {
            if reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
                || theme.backdrop == .aurora {
                scene(theme, at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    // Kept small, so a sine of it keeps its precision.
                    let t = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 3600)
                    scene(theme, at: t)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scene(_ theme: Theme, at t: Double) -> some View {
        let k = strength
        return Canvas { context, size in
            switch theme.backdrop {
            case .aurora: break
            case .haze: Self.haze(&context, size, theme, k, t)
            case .dunes: Self.dunes(&context, size, theme, k, t)
            case .parchment: Self.parchment(&context, size, theme, k, t)
            case .tavern: Self.tavern(&context, size, theme, k, t)
            case .sunset: Self.sunset(&context, size, theme, k, t)
            case .grid: Self.grid(&context, size, theme, k, t)
            case .scanlines where glass:
                Self.scanlines(&context, size, theme, k * 0.45, t, glow: false)
            case .scanlines: Self.scanlines(&context, size, theme, k, t)
            }
        }
    }

    /// The same scatter on every frame, so each drop, mote and wisp keeps its identity.
    private struct Seeded {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    private static func horizonGlow(_ c: inout GraphicsContext, _ s: CGSize,
                                    _ color: Color, _ k: Double, height: CGFloat = 0.55) {
        let rect = CGRect(x: 0, y: s.height * (1 - height), width: s.width, height: s.height * height)
        c.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [.clear, color.opacity(0.22 * k)]),
            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
    }

    private static let amber = Color(red: 1, green: 0.54, blue: 0.24)

    // MARK: Blade Runner 2049

    /// The dead city's air: an amber wash bleeding down from the top, two banks of haze
    /// drifting so slowly they read as still, and dust hanging in it. No rain, no neon —
    /// that was the first film.
    private static func haze(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                             _ k: Double, _ t: Double) {
        let all = Path(CGRect(origin: .zero, size: s))
        c.fill(all, with: .linearGradient(
            Gradient(stops: [.init(color: th.glow.opacity(0.20 * k), location: 0),
                             .init(color: th.glowDeep.opacity(0.10 * k), location: 0.45),
                             .init(color: .clear, location: 0.8)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
        for (i, (x, y, r, a)) in [(0.25, 0.30, 0.65, 0.16), (0.78, 0.55, 0.55, 0.12)].enumerated() {
            let drift = CGFloat(sin(t * 0.03 + Double(i) * 2.1)) * s.width * 0.06
            let center = CGPoint(x: s.width * x + drift, y: s.height * y)
            c.fill(all, with: .radialGradient(
                Gradient(colors: [th.glow.opacity(a * k), .clear]),
                center: center, startRadius: 0, endRadius: max(s.width, s.height) * r))
        }
        var rng = Seeded(state: 2049)
        for _ in 0..<Int(s.width * s.height / 5200) {
            let speed = 3 + rng.next() * 6
            let span = s.width + 20
            let x = (rng.next() * span + t * speed).truncatingRemainder(dividingBy: span) - 10
            let y = rng.next() * s.height + 6 * sin(t * (0.1 + rng.next() * 0.2) + rng.next() * 6)
            let r = 0.5 + rng.next() * 1.1
            c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                   with: .color(th.accentHot.opacity((0.05 + rng.next() * 0.10) * k)))
        }
    }

    // MARK: Dune

    /// Restraint: the warm light low on the horizon, and fine sand carried across it on
    /// the wind. Nothing drawn that says "desert" — the palette already does.
    private static func dunes(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                              _ k: Double, _ t: Double) {
        horizonGlow(&c, s, th.glow, k * 0.8, height: 0.6)
        var rng = Seeded(state: 10191)
        for _ in 0..<Int(s.width * s.height / 2200) {
            let speed = 6 + rng.next() * 16
            let span = s.width + 20
            let x = (rng.next() * span + t * speed).truncatingRemainder(dividingBy: span) - 10
            // Heavier near the ground, as blown sand is.
            let y = s.height * (1 - pow(rng.next(), 1.8) * 0.9)
                + 3 * sin(t * (0.3 + rng.next() * 0.4) + rng.next() * 6)
            let r = 0.5 + rng.next() * 0.9
            c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                   with: .color(th.ink.opacity((0.06 + rng.next() * 0.10) * k)))
        }
    }

    // MARK: Middle-earth

    /// Paper, its burnt edges, and dust turning slowly in lamplight. No knotwork, here
    /// or on the panels: it was one ornament too many wherever it went.
    private static func parchment(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                                  _ k: Double, _ t: Double) {
        var rng = Seeded(state: 1954)
        for _ in 0..<Int(s.width * s.height / 900) {
            let r = 0.4 + rng.next() * 1.1
            let dot = CGRect(x: rng.next() * s.width, y: rng.next() * s.height, width: r, height: r)
            c.fill(Path(ellipseIn: dot), with: .color(th.ink.opacity((0.04 + rng.next() * 0.05) * k)))
        }
        var motes = Seeded(state: 3019)
        for _ in 0..<36 {
            let span = s.height + 40
            let rise = 4 + motes.next() * 9
            let y = s.height + 20 - (motes.next() * span + t * rise).truncatingRemainder(dividingBy: span)
            let x = motes.next() * s.width + 18 * sin(t * (0.15 + motes.next() * 0.2) + motes.next() * 6)
            let r = 1.2 + motes.next() * 2.2
            let glint = 0.10 + 0.08 * sin(t * 0.5 + motes.next() * 6)
            c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                   with: .color(th.accent2.opacity(glint * k)))
        }
        let radius = max(s.width, s.height) * 0.75
        c.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0.55),
                .init(color: Color(red: 0.45, green: 0.30, blue: 0.12).opacity(0.28 * k), location: 1),
            ]),
            center: CGPoint(x: s.width / 2, y: s.height / 2), startRadius: 0, endRadius: radius))
    }

    // MARK: The Prancing Pony

    /// The hearth: a warm glow from low in one corner that breathes as a fire does, with
    /// embers drifting up out of it, and the room darkening away from it. The breathing is slow and never
    /// dips far — firelight, not flicker.
    private static func tavern(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                               _ k: Double, _ t: Double) {
        // The hearth.
        let fire = CGPoint(x: s.width * 0.12, y: s.height * 1.02)
        let breathe = 1 + 0.05 * sin(t * 1.3) + 0.03 * sin(t * 2.9 + 1)
        let reach = max(s.width, s.height) * 0.85 * breathe
        c.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
            Gradient(stops: [
                .init(color: th.glow.opacity(0.30 * k), location: 0),
                .init(color: th.glowDeep.opacity(0.18 * k), location: 0.4),
                .init(color: .clear, location: 1),
            ]), center: fire, startRadius: 0, endRadius: reach))
        // Embers, rising and wandering, fading as they climb.
        var embers = Seeded(state: 2941)
        for _ in 0..<26 {
            let life = 7 + embers.next() * 6
            let age = (t / life + embers.next()).truncatingRemainder(dividingBy: 1)
            let rise = s.height * 0.75 * age
            let x = fire.x + (embers.next() - 0.3) * s.width * 0.45
                + 22 * sin(t * (0.6 + embers.next()) + embers.next() * 6)
            let yy = fire.y - 20 - rise
            let r = 0.8 + embers.next() * 1.6
            c.fill(Path(ellipseIn: CGRect(x: x - r, y: yy - r, width: r * 2, height: r * 2)),
                   with: .color(Color(red: 1, green: 0.62, blue: 0.25).opacity((1 - age) * 0.7 * k)))
        }
        // The room darkens away from the fire.
        c.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.5),
                             .init(color: .black.opacity(0.45 * k), location: 1)]),
            center: CGPoint(x: s.width / 2, y: s.height / 2), startRadius: 0,
            endRadius: max(s.width, s.height) * 0.8))
    }

    // MARK: Synthwave and the Grid

    /// A violet sky with fixed stars over a magenta floor running away to the horizon.
    /// The stars do not twinkle — nothing on this screen flickers.
    private static func sunset(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                               _ k: Double, _ t: Double) {
        // Low, below where the page's content usually ends, so the horizon line does not
        // run through a card.
        let horizon = s.height * 0.84
        horizonGlow(&c, s, th.glowDeep, k * 1.4, height: 0.75)
        var rng = Seeded(state: 1986)
        for _ in 0..<Int(s.width * horizon / 6000) {
            let r = 0.4 + rng.next() * 1.0
            let star = CGRect(x: rng.next() * s.width, y: rng.next() * horizon * 0.9, width: r, height: r)
            c.fill(Path(ellipseIn: star), with: .color(th.ink.opacity((0.12 + rng.next() * 0.28) * k)))
        }
        c.fill(Path(CGRect(x: 0, y: horizon - 1, width: s.width, height: 2)),
               with: .color(th.accent.opacity(0.22 * k)))
        perspectiveGrid(&c, s, horizon: horizon, color: th.accent, k: k * 0.8, t: t, speed: 0.35)
    }

    /// Light cycles: a few trails of light drawn low across the dark, each on its own
    /// lane and at its own pace, one in the second colour. The horizon is only a glow.
    private static func grid(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                             _ k: Double, _ t: Double) {
        horizonGlow(&c, s, th.accent, k * 0.6, height: 0.4)
        // Low lanes, under where the page's content sits, so a trail does not cross a card.
        for (lane, lap, leftward, second) in [(0.86, 9.0, false, false), (0.92, 13.0, true, true),
                                              (0.97, 7.0, false, false)] {
            let y = s.height * lane
            let tail = min(260, s.width * 0.3)
            let progress = CGFloat((t / lap).truncatingRemainder(dividingBy: 1))
            let head = leftward ? s.width + tail - progress * (s.width + tail * 2)
                                : -tail + progress * (s.width + tail * 2)
            let start = leftward ? head + tail : head - tail
            let color = second ? th.accent2 : th.accent
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [.clear, color.opacity(0.55 * k)]),
                startPoint: CGPoint(x: start, y: y), endPoint: CGPoint(x: head, y: y))
            let rect = CGRect(x: min(start, head), y: y - 0.75, width: tail, height: 1.5)
            c.fill(Path(rect), with: shading)
            c.fill(Path(rect.insetBy(dx: 0, dy: -3)), with: .linearGradient(
                Gradient(colors: [.clear, color.opacity(0.12 * k)]),
                startPoint: CGPoint(x: start, y: y), endPoint: CGPoint(x: head, y: y)))
        }
    }

    /// A floor of lines running away to a vanishing point, travelling towards you: the
    /// cross-lines are spaced in perspective and slide one gap nearer every `1 / speed`
    /// seconds, so the loop has no seam.
    private static func perspectiveGrid(_ c: inout GraphicsContext, _ s: CGSize, horizon: CGFloat,
                                        color: Color, k: Double, t: Double, speed: Double) {
        var floor = Path()
        let vanish = CGPoint(x: s.width / 2, y: horizon)
        let spread = s.width * 2.4
        for i in -14...14 {
            floor.move(to: vanish)
            floor.addLine(to: CGPoint(x: s.width / 2 + CGFloat(i) / 14 * spread / 2, y: s.height))
        }
        let step = 1.45
        let phase = (t * speed).truncatingRemainder(dividingBy: 1)
        var n = -1.0
        while true {
            let depth = CGFloat(3 * pow(step, n + phase))
            if horizon + depth >= s.height { break }
            floor.move(to: CGPoint(x: 0, y: horizon + depth))
            floor.addLine(to: CGPoint(x: s.width, y: horizon + depth))
            n += 1
        }
        floor.move(to: CGPoint(x: 0, y: horizon)); floor.addLine(to: CGPoint(x: s.width, y: horizon))
        var faded = c
        faded.clip(to: Path(CGRect(x: 0, y: horizon, width: s.width, height: s.height - horizon)))
        faded.stroke(floor, with: .linearGradient(
            Gradient(colors: [color.opacity(0.05 * k), color.opacity(0.32 * k)]),
            startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: s.height)),
            lineWidth: 0.8)
    }

    // MARK: Nostromo

    /// A CRT: scanlines crawling down the glass, and the slow bright band of a picture
    /// that is not quite in sync rolling through them.
    private static func scanlines(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                                  _ k: Double, _ t: Double, glow: Bool = true, roll: Bool = true) {
        if glow {
            c.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
                Gradient(colors: [th.accent.opacity(0.08 * k), .clear]),
                center: CGPoint(x: s.width / 2, y: s.height * 0.4),
                startRadius: 0, endRadius: max(s.width, s.height) * 0.7))
        }
        if roll {
            let band: CGFloat = 180
            let span = s.height + band * 2
            let y = CGFloat((t * 38).truncatingRemainder(dividingBy: Double(span))) - band
            c.fill(Path(CGRect(x: 0, y: y, width: s.width, height: band)), with: .linearGradient(
                Gradient(colors: [.clear, th.accent.opacity(0.07 * k), .clear]),
                startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: y + band)))
        }
        let pitch: CGFloat = 3
        let crawl = roll ? CGFloat((t * 9).truncatingRemainder(dividingBy: Double(pitch))) : 0
        var lines = Path()
        stride(from: crawl - pitch, through: s.height, by: pitch).forEach {
            lines.addRect(CGRect(x: 0, y: $0, width: s.width, height: 1))
        }
        c.fill(lines, with: .color(Color.black.opacity(0.28 * k)))
    }
}

/// The Nostromo's scanlines laid over the whole screen, as the glass of a tube would be.
/// Behind the page they only show where nothing covers it, and a phone's lists cover
/// nearly all of it. Nothing for any other theme; never hit-testable.
struct CRTGlass: View {
    var body: some View {
        if Theme.active.backdrop == .scanlines {
            ThemeBackdrop(glass: true)
        }
    }
}

// MARK: - Platform chrome

/// The parts of the look that belong to the system rather than to SwiftUI.
@MainActor
enum ThemeChrome {
    #if canImport(AppKit)
    /// The Mac's Dock icon, which the app delegate owns — it already swaps Classic's
    /// between light and dark as the system appearance changes.
    static var onIconChange: (@MainActor () -> Void)?

    /// The theme's Dock icon, or nil for Classic, whose icon follows the appearance.
    static func dockIcon(for theme: Theme) -> NSImage? {
        guard theme.id != .classic,
              let url = Bundle.main.url(forResource: "AppIcon-\(theme.id.rawValue)",
                                        withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }
    #endif

    /// The app icon, to match. Only on a change the person made: iOS tells them the icon
    /// changed with an alert of its own, which at launch would be a message about nothing.
    static func applyIcon(_ theme: Theme) {
        #if canImport(AppKit)
        onIconChange?()
        #else
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        let name = theme.id == .classic ? nil : "AppIcon-\(theme.id.rawValue)"
        guard app.alternateIconName != name else { return }
        app.setAlternateIconName(name) { error in
            if let error { Log.icon.error("\(error.localizedDescription, privacy: .public)") }
        }
        #endif
    }

    static func apply(_ theme: Theme) {
        #if canImport(AppKit)
        // The window, menus and every standard control follow this; `nil` hands it back to
        // the system setting, which is what Classic wants.
        switch theme.appearance {
        case .adaptive: NSApp?.appearance = nil
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        }
        #else
        applyBars(theme)
        #endif
    }

    #if !canImport(AppKit)
    /// Navigation bar titles and segmented controls are UIKit's, and the environment's
    /// font design never reaches them. Classic resets to the system's own.
    private static func applyBars(_ theme: Theme) {
        let nav = UINavigationBarAppearance()
        let segments = UISegmentedControl.appearance()
        guard theme.id != .classic else {
            nav.configureWithDefaultBackground()
            UINavigationBar.appearance().standardAppearance = nav
            UINavigationBar.appearance().scrollEdgeAppearance = nil
            UINavigationBar.appearance().compactAppearance = nil
            segments.selectedSegmentTintColor = nil
            segments.setTitleTextAttributes(nil, for: .normal)
            segments.setTitleTextAttributes(nil, for: .selected)
            let tabs = UITabBarAppearance()
            tabs.configureWithDefaultBackground()
            UITabBar.appearance().standardAppearance = tabs
            UITabBar.appearance().scrollEdgeAppearance = nil
            return
        }
        let ink = UIColor(theme.ink)
        nav.configureWithTransparentBackground()
        nav.backgroundColor = UIColor(theme.ground).withAlphaComponent(0.92)
        nav.shadowColor = UIColor(theme.edgeTint).withAlphaComponent(0.35)
        nav.titleTextAttributes = [
            .font: displayFont(17, theme),
            .foregroundColor: ink,
            .kern: theme.type.displayTracking * 17 / 20,
        ]
        nav.largeTitleTextAttributes = [
            .font: displayFont(32, theme),
            .foregroundColor: ink,
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        // The tab bar: the theme's ground, its lettering, ink at rest and accent when on.
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(theme.ground).withAlphaComponent(0.94)
        tabs.shadowColor = UIColor(theme.edgeTint).withAlphaComponent(0.35)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance,
                     tabs.compactInlineLayoutAppearance] {
            let rest = UIColor(theme.ink).withAlphaComponent(0.55)
            let on = UIColor(theme.accent)
            item.normal.iconColor = rest
            item.normal.titleTextAttributes = [.font: bodyFont(10, .medium, theme),
                                               .foregroundColor: rest]
            item.selected.iconColor = on
            item.selected.titleTextAttributes = [.font: bodyFont(10, .semibold, theme),
                                                 .foregroundColor: on]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs

        segments.selectedSegmentTintColor = UIColor(theme.accent).withAlphaComponent(0.85)
        segments.backgroundColor = UIColor(theme.ink).withAlphaComponent(0.06)
        segments.setTitleTextAttributes([.font: bodyFont(13, .medium, theme), .foregroundColor: ink],
                                        for: .normal)
        segments.setTitleTextAttributes([.font: bodyFont(13, .semibold, theme),
                                         .foregroundColor: UIColor(theme.onFill)],
                                        for: .selected)
    }

    private static func displayFont(_ size: CGFloat, _ theme: Theme) -> UIFont {
        if let name = theme.type.displayName, let font = UIFont(name: name, size: size) { return font }
        let weight: UIFont.Weight = switch theme.type.displayWeight {
        case .light: .light
        case .semibold: .semibold
        case .bold: .bold
        default: .regular
        }
        return bodyFont(size, weight, theme, width: theme.type.displayWidth)
    }

    private static func bodyFont(_ size: CGFloat, _ weight: UIFont.Weight, _ theme: Theme,
                                 width: Font.Width? = nil) -> UIFont {
        let w: UIFont.Width = switch width ?? theme.type.width {
        case .condensed: .condensed
        case .expanded: .expanded
        case .compressed: .compressed
        default: .standard
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight, width: w)
        let design: UIFontDescriptor.SystemDesign? = switch theme.type.design {
        case .serif: .serif
        case .monospaced: .monospaced
        case .rounded: .rounded
        default: nil
        }
        guard let design, let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
    #endif
}
