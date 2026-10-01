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
        case classic, bladeRunner, dune, middleEarth, synthwave, grid, nostromo, nostromoTeal
        var id: String { rawValue }
    }

    enum Appearance: Sendable { case adaptive, dark, light }

    /// How a container's corners are cut. The radius a call site asks for is scaled, so
    /// a 14pt card and a 7pt button keep their relationship in every theme.
    enum Corners: Sendable {
        case rounded(scale: CGFloat)
        case chamfered(scale: CGFloat)
        /// All four corners cut, small: a slab of machined stone, Arrakeen's architecture
        /// and the ornithopters' instruments — related to Blade Runner's two-corner cut,
        /// not the same.
        case facetted(scale: CGFloat)
        /// Torn: square, but with a stepped notch out of two corners and a segment of an
        /// edge slipped out of line, placed differently for each size of container —
        /// Retro's broken signal, in the panels' own outline.
        case glitched(scale: CGFloat)
        case square
    }

    /// What `themeEdge` draws around a container, on top of its own hairline.
    enum Edge: Sendable {
        case none
        /// A lit tube of `edgeTint`, with a little light spilling off it.
        case neon
        /// A gilt double rule with an interlaced knot in each corner — elven work.
        case knotwork
        /// Misregistration: the shape's rule printed twice, in `accent` and `accent2`,
        /// a pixel or two apart — a glitched signal, held still.
        case glitch
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
    enum Backdrop: Sendable { case aurora, city, dunes, parchment, glitch, grid, scanlines }

    /// The display a skin reads its title and time from — Winamp's LCD. A dark well set
    /// into the panel, its own lettering colour, and a little of that colour's light.
    struct LCD: Sendable {
        let background: Color
        let ink: Color
        let glow: Color
        /// A face of its own for what the display reads out, where the theme has one and
        /// the device has it (see `Font.lcd`). Otherwise the system face.
        var font: String? = nil
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
        /// Headings lit in the theme's glow, as if the light were on them — Arrakis's sun.
        var displayGlow = false
        /// Headings printed out of register in `accent` and `accent2` — Retro's glitch.
        var displaySplit = false

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
    /// What a lit panel's inner rule and a chosen segment glow in — hover, focus,
    /// selection — where it is not `edgeTint`. Dune's Water of Life teal.
    var highlight: Color? = nil

    var litTint: Color { highlight ?? edgeTint }
    /// Now and then a glint of light on the hero's title and mark (`Glint`).
    var glints = false

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

    /// The city at night, 2049: a street of signage seen through mist and rain. The
    /// colours are the picture's — pink and red neon, cold teal in the haze, near-black
    /// everywhere the light does not reach — and the backdrop is the picture itself, when
    /// the build carries it (see `ThemeBackdrop.city`). Thin, light capitals; bevelled
    /// panels rather than glowing tubes, so the neon stays in the scene.
    static let bladeRunner = Theme(
        id: .bladeRunner,
        name: "Blade Runner 2049",
        tagline: "Neon through mist and rain",
        appearance: .dark,
        ink: hex(0xD9E6EA),
        accent: hex(0xF0438C),
        accentHot: hex(0xFF6AA6),
        accent2: hex(0x3CCFD6),
        edgeTint: hex(0x3CCFD6),
        brand: hex(0xF0438C),
        ground: hex(0x06090C),
        surface: hex(0x0B1015),
        card: hex(0x0F151B).opacity(0.88),
        field: hex(0x0F161D),
        fieldInk: hex(0xD9E6EA),
        fieldRaised: hex(0x1B2630),
        onFill: .white,
        good: hex(0x4FE0B0),
        warn: hex(0xFFB04A),
        glow: hex(0xE0407F),
        glowDeep: hex(0x1F5E70),
        pickedMid: hex(0x0E1220),
        pickedFar: hex(0x1E1022),
        pickedEdge: hex(0x1F4A5C),
        pickedEdgeHot: hex(0x2E7A90),
        // Cut on the diagonal, top-leading and bottom-trailing, like the film's displays:
        // machined rather than moulded.
        corners: .chamfered(scale: 1),
        edge: .bevel,
        // Michroma for headings — wide and smooth, the lettering of a city's signage —
        // bundled with the app (OFL). The system's light face if it is missing.
        type: Typeface(display: ["Michroma"], displayWeight: .light,
                       displayCaps: true, displayTracking: 0.6),
        backdrop: .city,
        aurora: [hex(0xF0438C), hex(0xFF8A3D), hex(0x1F5E70), hex(0x3CCFD6)],
        lcd: LCD(background: hex(0x04080B), ink: hex(0x5FE3EA), glow: hex(0x3CCFD6),
                 font: "Rajdhani-Medium")
    )

    /// Arrakis at dusk. Umber and sand, spice orange for anything that matters, and the
    /// Water of Life's glowing teal as the rare second colour, in the interface only: what
    /// is lit (hovered, focused, chosen) and what is done. Thin, spaced capitals.
    static let dune = Theme(
        id: .dune,
        name: "Dune",
        tagline: "Sand, spice and a long horizon",
        appearance: .dark,
        ink: hex(0xF0DEC0),
        accent: hex(0xE0822F),
        accentHot: hex(0xF29A45),
        accent2: hex(0x3FE6D2),
        edgeTint: hex(0xE0822F),
        brand: hex(0xE0822F),
        ground: hex(0x130C06),
        surface: hex(0x1B120A),
        card: hex(0x22170E).opacity(0.9),
        field: hex(0x2A1C10),
        fieldInk: hex(0xF0DEC0),
        fieldRaised: hex(0x3A2816),
        onFill: hex(0x1B1007),
        good: hex(0x4FE8D0),
        warn: hex(0xF4C55A),
        glow: hex(0xE0822F),
        glowDeep: hex(0x7A3A12),
        pickedMid: hex(0x1F140B),
        pickedFar: hex(0x2E1C0D),
        pickedEdge: hex(0x4A2E15),
        pickedEdgeHot: hex(0x6A3F1A),
        corners: .facetted(scale: 0.55),
        edge: .bevel,
        // Josefin Sans Light (bundled, OFL): thin geometric capitals, widely spaced — the
        // posters' restraint without their stretch.
        type: Typeface(display: ["JosefinSansRoman-Light"], displayWeight: .light,
                       displayCaps: true, displayTracking: 2.5, displayGlow: true),
        backdrop: .dunes,
        aurora: [hex(0xE0822F), hex(0xF2B45A), hex(0x8A3C12), hex(0xF7D08A)],
        lcd: LCD(background: hex(0x0E0804), ink: hex(0xF2B45A), glow: hex(0xE0822F),
                 font: "Jura-Medium"),
        highlight: hex(0x3FE6D2)
    )

    /// The map in Bag End's study, by candlelight: dark aged paper, sepia ink gone pale
    /// with age, gilt rules, oxblood for what you press, and the light pooled in the
    /// middle of the page with the edges falling into shadow. Headings in Uncial
    /// Antiqua's map hand where the app carries it, Baskerville otherwise.
    static let middleEarth = Theme(
        id: .middleEarth,
        name: "Middle-earth",
        tagline: "An old map by candlelight",
        appearance: .dark,
        ink: hex(0xEAD8B4),
        accent: hex(0xC0503A),
        accentHot: hex(0xD8644A),
        accent2: hex(0xC9A04A),
        edgeTint: hex(0xB08A3E),
        // Gilt, not oxblood: the mark is drawn as an outline, and oxblood vanished on the
        // dark paper.
        brand: hex(0xD9B060),
        ground: hex(0x120C07),
        surface: hex(0x1B130B),
        card: hex(0x21170D).opacity(0.92),
        field: hex(0x22180E),
        fieldInk: hex(0xEAD8B4),
        fieldRaised: hex(0x33241A),
        onFill: hex(0xFBF0DA),
        good: hex(0x9DB86A),
        warn: hex(0xE0A040),
        glow: hex(0xC9883A),
        glowDeep: hex(0x5A3416),
        pickedMid: hex(0x231709),
        pickedFar: hex(0x34200C),
        pickedEdge: hex(0x5A3E1C),
        pickedEdgeHot: hex(0x7A5626),
        // Rounder than the other skins: a hobbit-hole door, not a machined panel.
        corners: .rounded(scale: 0.8),
        // The skin's bevel with its gilt rule, not a knot in every corner: on every row,
        // card and button at once that was a page of swirls.
        edge: .bevel,
        // Uncial Antiqua (bundled, OFL): the rounded uncial hand the map is lettered in.
        // In its own capitals and lower case, as the map is, not set in all caps.
        type: Typeface(design: .serif, display: ["UncialAntiqua-Regular", "Baskerville-SemiBold"],
                       displayCaps: false, displayTracking: 0.3, displayGlow: true),
        backdrop: .parchment,
        aurora: [hex(0xC9883A), hex(0xE0B060), hex(0x5A3416), hex(0xEAD7A8)],
        // Ink on darker paper rather than a lit screen — nothing electric in Rivendell.
        lcd: LCD(background: hex(0x0C0804), ink: hex(0xE8C77A), glow: hex(0xC9883A))
    )

    /// Glitch: a signal coming apart. The palette is the glitch picture's — a pink-orange,
    /// teal and a cold pale grey on black — the panels' rules printed twice out of register,
    /// headings in Rubik Glitch (its letters already broken) with the same red and cyan
    /// split, a terminal's VT323 in the LCD, and every outline torn (`Torn`).
    /// The `synthwave` id is kept so a saved choice and its icon carry over.
    static let synthwave = Theme(
        id: .synthwave,
        name: "Glitch",
        tagline: "A glitched signal on old tape",
        appearance: .dark,
        ink: hex(0xE4EAEC),
        accent: hex(0xFF7A6E),
        accentHot: hex(0xFF9C8C),
        accent2: hex(0x3CC8C0),
        edgeTint: hex(0xFF7A6E),
        brand: hex(0xFF7A6E),
        ground: hex(0x090A0C),
        surface: hex(0x111316),
        card: hex(0x15181B).opacity(0.9),
        field: hex(0x15181C),
        fieldInk: hex(0xE4EAEC),
        fieldRaised: hex(0x23272C),
        onFill: .white,
        good: hex(0x3CC8C0),
        warn: hex(0xFFC44A),
        glow: hex(0xFF7A6E),
        glowDeep: hex(0x1E5A5A),
        pickedMid: hex(0x1A1214),
        pickedFar: hex(0x2A1416),
        pickedEdge: hex(0x5A2A24),
        pickedEdgeHot: hex(0x7A3A30),
        corners: .glitched(scale: 0.9),
        edge: .glitch,
        type: Typeface(display: ["RubikGlitch-Regular"], displayCaps: true,
                       displayTracking: 0.5, displaySplit: true),
        backdrop: .glitch,
        aurora: [hex(0xFF7A6E), hex(0x3CC8C0), hex(0x1E5A5A), hex(0xE4EAEC)],
        lcd: LCD(background: hex(0x050607), ink: hex(0x3CC8C0), glow: hex(0x3CC8C0),
                 font: "VT323-Regular"),
        highlight: hex(0x3CC8C0)
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
        // Orbitron (bundled, OFL): thin geometric capitals, the Grid's own lettering.
        type: Typeface(display: ["Orbitron-Regular"], displayWeight: .semibold,
                       displayCaps: true, displayTracking: 1.2),
        backdrop: .grid,
        aurora: [hex(0x18E4FF), hex(0x0A6FA8), hex(0x0B3D66), hex(0x7FF3FF)],
        lcd: LCD(background: hex(0x00070A), ink: hex(0x7FF3FF), glow: hex(0x18E4FF)),
        // The other side's orange, where something is lit or chosen.
        highlight: hex(0xFF9B26),
        glints: true
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

    fileprivate static func hex(_ value: UInt32) -> Color {
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
            // Design only, and no width: an environment width (even `.standard`) made
            // SwiftUI re-resolve a theme's named heading face and fall back to the system.
            .fontDesign(theme.type.design == .default ? nil : theme.type.design)
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
    /// Which tear, for a theme that tears its outlines (`Torn`): a list's rows are all
    /// one size, so each passes its own seed or they would all break the same way.
    var seed: Int = 0
    private var inset: CGFloat = 0

    init(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular, seed: Int = 0) {
        self.cornerRadius = cornerRadius
        self.style = style
        self.seed = seed
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        switch Theme.active.corners {
        case .rounded(let scale):
            return RoundedRectangle(cornerRadius: max(cornerRadius * scale - inset, 0),
                                    style: style).path(in: r)
        case .chamfered(let scale):
            return Chamfer(cut: max(cornerRadius * scale - inset * 0.4, 0)).path(in: r)
        case .facetted(let scale):
            return Facet(cut: max(cornerRadius * scale - inset * 0.4, 0)).path(in: r)
        case .glitched(let scale):
            return Torn(cut: max(cornerRadius * scale - inset * 0.4, 0), seed: seed).path(in: r)
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
        case .facetted(let scale):
            return Facet(cut: half * 0.5 * scale).path(in: r)
        case .glitched(let scale):
            return Torn(cut: half * 0.5 * scale).path(in: r)
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

/// A rectangle with all four corners cut off on the diagonal.
struct Facet: Shape {
    var cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = min(cut, rect.width / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.closeSubpath()
        return p
    }
}

/// A rectangle torn the way a bad signal tears a picture: a stepped notch out of the
/// top-trailing and bottom-leading corners, a shallow bite out of the top edge and a
/// segment of the trailing edge slipped inward. Where the steps fall comes from the
/// rectangle's own size, so neighbouring panels of different sizes break differently
/// but one panel never changes shape as it is redrawn.
struct Torn: Shape {
    var cut: CGFloat
    var seed: Int = 0

    /// A seed that is the same for the same thing on every launch (unlike `hashValue`).
    static func seed(_ id: String) -> Int {
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(truncatingIfNeeded: h % 100_000)
    }

    func path(in rect: CGRect) -> Path {
        let c = min(max(cut, 1.5), rect.width / 4, rect.height / 4)
        // A stable 0…1 from the size and the seed, salted per use.
        func f(_ salt: Double) -> CGFloat {
            let v = sin(Double(rect.width) * 12.9898 + Double(rect.height) * 78.233
                        + Double(seed) * 0.6180339 + salt * 37.719) * 43758.5453
            return CGFloat(v - floor(v))
        }
        let w = rect.width, h = rect.height
        let biteX = rect.minX + w * (0.25 + f(1) * 0.35), biteW = w * (0.06 + f(2) * 0.12)
        let slipY = rect.minY + h * (0.35 + f(3) * 0.3), slipH = h * (0.12 + f(4) * 0.18)
        let bite = c * 0.45, slip = c * 0.5
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: biteX, y: rect.minY))
        p.addLine(to: CGPoint(x: biteX, y: rect.minY + bite))
        p.addLine(to: CGPoint(x: biteX + biteW, y: rect.minY + bite))
        p.addLine(to: CGPoint(x: biteX + biteW, y: rect.minY))
        // The top-trailing notch, in two steps.
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY + c * 0.5))
        p.addLine(to: CGPoint(x: rect.maxX - c * 0.5, y: rect.minY + c * 0.5))
        p.addLine(to: CGPoint(x: rect.maxX - c * 0.5, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        // The trailing edge, with a segment slipped in.
        p.addLine(to: CGPoint(x: rect.maxX, y: slipY))
        p.addLine(to: CGPoint(x: rect.maxX - slip, y: slipY))
        p.addLine(to: CGPoint(x: rect.maxX - slip, y: slipY + slipH))
        p.addLine(to: CGPoint(x: rect.maxX, y: slipY + slipH))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // The bottom-leading notch.
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY - c * 0.5))
        p.addLine(to: CGPoint(x: rect.minX + c * 0.5, y: rect.maxY - c * 0.5))
        p.addLine(to: CGPoint(x: rect.minX + c * 0.5, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
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
    func themeEdge(radius: CGFloat, lit: Bool = false, seed: Int = 0) -> some View {
        themeEdge(ThemedRect(cornerRadius: radius, style: .continuous, seed: seed), lit: lit)
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
        case .glitch:
            if lit {
                GlitchEdge(shape: shape)
            } else {
                // At rest, one quiet rule. The signal only breaks up when you reach for it.
                shape.strokeBorder(theme.ink.opacity(0.2), lineWidth: 1)
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

/// A lens glint on a point of the hero — the end of the title's last letter, the corner
/// of the mark: every so often, at an uneven moment, a small four-pointed star of light
/// swells there over a fraction of a second and fades. Nothing in themes without
/// `glints`, and still (absent) under Reduce Motion.
struct Glint: View {
    /// Keeps two glints from firing together.
    var seed: UInt64 = 0
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = Theme.active
        if theme.glints && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let level = Self.level(t, seed: seed)
                Canvas { c, s in
                    guard level > 0 else { return }
                    c.blendMode = .plusLighter
                    let p = CGPoint(x: s.width / 2, y: s.height / 2)
                    let white = Color.white
                    c.fill(Path(ellipseIn: CGRect(x: p.x - s.width / 2, y: p.y - s.height / 2,
                                                  width: s.width, height: s.height)),
                           with: .radialGradient(Gradient(colors: [theme.accent.opacity(0.45 * level), .clear]),
                                                 center: p, startRadius: 0, endRadius: s.width / 2))
                    for (w, h) in [(s.width, 1.6), (1.6, s.height * 0.7)] {
                        c.fill(Path(ellipseIn: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)),
                               with: .radialGradient(Gradient(colors: [white.opacity(0.95 * level), .clear]),
                                                     center: p, startRadius: 0, endRadius: max(w, h) / 2))
                    }
                    c.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)),
                           with: .color(white.opacity(level)))
                }
                .frame(width: size, height: size)
                .rotationEffect(.degrees(12 * level))
            }
            .allowsHitTesting(false)
        }
    }

    /// 0 most of the time; a swell lasting about 0.9s at uneven moments, a few seconds
    /// apart.
    private static func level(_ t: Double, seed: UInt64) -> Double {
        let slot = 4.5
        let shifted = t + Double(seed) * 2.1
        let index = UInt64(max(0, floor(shifted / slot)))
        var x = (index &+ seed &* 7919) &* 6364136223846793005 &+ 1442695040888963407
        x ^= x >> 33
        let roll = Double(x % 1000) / 1000
        guard roll < 0.55 else { return 0 }
        let start = Double((x >> 10) % 1000) / 1000 * (slot - 1)
        let age = shifted.truncatingRemainder(dividingBy: slot) - start
        guard age > 0, age < 0.9 else { return 0 }
        return sin(.pi * age / 0.9)
    }
}

/// Retro's hover: the control's rule breaking up — printed in red and cyan out of
/// register by an amount that jumps a few times a second, slices of it torn sideways,
/// and a thin bar of noise across it now and then. Only while the pointer is on it, and
/// only over that one control: small, and asked for, rather than anything on the screen
/// flashing at you.
private struct GlitchEdge<S: InsettableShape>: View {
    let shape: S

    /// The last tick, at or before this one, that threw a change — so a reading holds
    /// for an uneven run of ticks.
    private static func heldTick(_ tick: Double, _ h: (Double) -> Double) -> Double {
        var key = tick
        for _ in 0..<10 where h(key * 1.7) < 0.6 { key -= 1 }
        return key
    }

    var body: some View {
        let theme = Theme.active
        GeometryReader { geo in
            let size = geo.size
            // Each control its own noise, from its size, so no two glitch in step.
            let salt = Double(size.width * 0.731 + size.height * 1.37)
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let h = { (x: Double) -> Double in
                    let v = sin(x * 12.9898 + salt * 78.233) * 43758.5453
                    return v - floor(v)
                }
                // Bursts and quiet spells of uneven length: the time is cut into short
                // windows, and each is lively or calm by its own throw.
                let window = floor(t / 0.3)
                let active = h(window * 3.1) < 0.55
                // Within a burst a reading holds for an uneven number of ticks: walk back
                // to the last tick that threw a change.
                let key = Self.heldTick(floor(t * 30), h)
                let j = { (n: Double) -> CGFloat in CGFloat(h(key * 0.913 + n * 17.1)) * 2 - 1 }
                let split = active ? 1.2 + abs(j(1)) * 3.5 : 0.8
                ZStack {
                    // Each misprinted rule glows in its own colour, as a lit tube would.
                    shape.strokeBorder(theme.accent.opacity(0.9), lineWidth: 1)
                        .shadow(color: theme.accent.opacity(0.85), radius: 4)
                        .offset(x: -split, y: active ? j(2) * 1.4 : 0)
                    shape.strokeBorder(theme.accent2.opacity(0.9), lineWidth: 1)
                        .shadow(color: theme.accent2.opacity(0.85), radius: 4)
                        .offset(x: split, y: active ? j(3) * 1.4 : 0)
                    shape.strokeBorder(theme.ink.opacity(0.5), lineWidth: 1)
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<3, id: \.self) { i in
                            let n = Double(i)
                            let show = active && j(10 + n) > -0.2
                            let y = size.height * abs(j(20 + n))
                            let w = size.width * (0.15 + abs(j(30 + n)) * 0.6)
                            let x = (size.width - w) * abs(j(40 + n))
                            let tint = j(70 + n) > 0 ? theme.accent : theme.accent2
                            Rectangle()
                                .fill(tint.opacity(show ? 0.6 : 0))
                                .frame(width: w, height: 1 + abs(j(50 + n)) * 2)
                                .shadow(color: tint.opacity(show ? 0.8 : 0), radius: 3)
                                .offset(x: x + j(60 + n) * 6, y: y)
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipShape(shape)
                }
            }
        }
    }
}

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
                .stroke((lit ? theme.litTint : theme.edgeTint).opacity(lit ? 0.7 : 0.28),
                        lineWidth: lit ? 0.8 : 0.6)
                .shadow(color: lit && theme.highlight != nil ? theme.litTint.opacity(0.6) : .clear,
                        radius: 3)
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

extension Font {
    /// What an LCD reads out — a title, a time — in the theme's display face where it has
    /// one. Rajdhani, Blade Runner's, sets small for its size, hence the step up.
    static func lcd(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let name = Theme.active.lcd?.font, Theme.hasFont(name) {
            return .custom(name, size: size * 1.15)
        }
        return .system(size: size, weight: weight)
    }
}

extension View {
    /// `Font.display`, with the theme's capitals and spacing.
    func displayType(_ size: CGFloat, classic: Font.Weight = .bold) -> some View {
        let theme = Theme.active
        let type = theme.type
        // No environment design on a named face: a theme's app-wide `.serif` (Middle-
        // earth's) made SwiftUI re-resolve Uncial Antiqua to the system serif.
        return fontDesign(type.displayName == nil ? theme.type.design : nil)
            .font(.display(size, classic: classic))
            .textCase(type.displayCaps ? .uppercase : nil)
            .tracking(type.displayTracking * min(size, 24) / 20)
            .shadow(color: type.displayGlow ? theme.glow.opacity(0.75) : .clear,
                    radius: type.displayGlow ? min(size * 0.35, 10) : 0)
            .shadow(color: type.displaySplit ? theme.accent.opacity(0.8) : .clear,
                    radius: 0, x: type.displaySplit ? -max(1, size * 0.05) : 0)
            .shadow(color: type.displaySplit ? theme.accent2.opacity(0.8) : .clear,
                    radius: 0, x: type.displaySplit ? max(1, size * 0.05) : 0)
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
            case .city: Self.city(&context, size, theme, k, t)
            case .dunes: Self.dunes(&context, size, theme, k, t)
            case .parchment: Self.parchment(&context, size, theme, k, t)
            case .glitch: Self.glitch(&context, size, theme, k, t)
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

    /// The street, if this build has its picture: `Backdrop-bladeRunner.jpg` in the app's
    /// resources, which only the family build carries (the art is not ours to hand out).
    /// Read once; nil means draw the scene without it.
    nonisolated(unsafe) private static let cityPicture = picture("bladeRunner")
    /// Arrakis, likewise: `Backdrop-dune.jpg`, family build only.
    nonisolated(unsafe) private static let dunePicture = picture("dune")
    /// Rivendell: `Backdrop-middleEarth.jpg`, family build only.
    nonisolated(unsafe) private static let shirePicture = picture("middleEarth")

    nonisolated private static func picture(_ name: String) -> Image? {
        guard let url = Bundle.main.url(forResource: "Backdrop-\(name)", withExtension: "jpg")
        else { return nil }
        #if canImport(AppKit)
        return NSImage(contentsOf: url).map(Image.init(nsImage:))
        #else
        return UIImage(contentsOfFile: url.path).map(Image.init(uiImage:))
        #endif
    }

    /// A picture filling the backdrop, breathing very slowly in and out so it never sits
    /// dead still. Returns where it was drawn, for anything placed on it.
    @discardableResult
    private static func drawPicture(_ c: inout GraphicsContext, _ s: CGSize, _ picture: Image,
                                    _ k: Double, _ t: Double) -> CGRect {
        let image = c.resolve(picture)
        let fit = max(s.width / image.size.width, s.height / image.size.height)
        let zoom = fit * (1.04 + 0.02 * sin(t * 0.025))
        let size = CGSize(width: image.size.width * zoom, height: image.size.height * zoom)
        let frame = CGRect(x: (s.width - size.width) / 2, y: (s.height - size.height) / 2,
                           width: size.width, height: size.height)
        var layer = c
        layer.opacity = min(1, 0.95 * k)
        layer.draw(image, in: frame)
        return frame
    }

    /// The picture, breathing very slowly in and out so it never sits dead still; mist
    /// rolling across it in banks, low and heavy like ground fog, tinted by the signs; and
    /// rain over everything on one slant, in two depths. Darkened under the page so what
    /// is on it stays readable. With no picture it is the mist and rain on near-black.
    private static func city(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                             _ k: Double, _ t: Double) {
        let all = Path(CGRect(origin: .zero, size: s))
        var flares: [Flare] = []
        if let picture = cityPicture {
            let frame = drawPicture(&c, s, picture, k, t)
            flares = signs(&c, frame, k, t)
            // Darker at the top, where the page's title and search sit, and at the edges.
            c.fill(all, with: .linearGradient(
                Gradient(stops: [.init(color: th.ground.opacity(0.55), location: 0),
                                 .init(color: th.ground.opacity(0.30), location: 0.55),
                                 .init(color: th.ground.opacity(0.45), location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
        }
        // Mist: soft banks drifting sideways at their own pace, wrapping round, and
        // rising and sinking a little as they go. Enough of them, fast enough, that the
        // air is visibly moving.
        for (i, (y, r, speed, tint)) in [(0.84, 0.42, 26.0, th.accent2), (0.70, 0.36, -18.0, th.glow),
                                         (0.93, 0.50, 14.0, th.ink), (0.58, 0.32, 22.0, th.accent2),
                                         (0.88, 0.40, -30.0, th.ink), (0.76, 0.30, 34.0, th.glow),
                                         (0.97, 0.45, -12.0, th.accent2)].enumerated() {
            let reach = max(s.width, s.height) * r
            let span = s.width + reach * 2
            let offset = Double(i) * 0.37 * Double(span)
            let x = (offset + t * speed).truncatingRemainder(dividingBy: Double(span))
            let cx = CGFloat(x < 0 ? x + Double(span) : x) - reach
            let center = CGPoint(x: cx, y: s.height * y + 24 * CGFloat(sin(t * 0.12 + Double(i) * 1.7)))
            c.fill(all, with: .radialGradient(
                Gradient(stops: [.init(color: tint.opacity(0.16 * k), location: 0),
                                 .init(color: tint.opacity(0.06 * k), location: 0.5),
                                 .init(color: .clear, location: 1)]),
                center: center, startRadius: 0, endRadius: reach))
        }
        // Rain: far drops short, dim and slow; near ones longer and faster. One slant,
        // which is what makes it read as falling through wind rather than as scratches.
        let slant = 0.16
        let area = s.width * s.height
        for (layer, count, speed, length, weight, width) in [
            (0, area / 2600, 560.0, 14.0, 0.10, 0.6),
            (1, area / 8000, 1050.0, 30.0, 0.18, 0.9),
        ] {
            var rng = Seeded(state: 2049 + UInt64(layer))
            var streaks = Path()
            for _ in 0..<Int(count) {
                let x0 = rng.next() * (s.width + s.height * slant)
                let phase = rng.next()
                let len = length * (0.7 + rng.next() * 0.6)
                let v = speed * (0.85 + rng.next() * 0.3)
                let span = s.height + len
                let y = (phase * span + t * v).truncatingRemainder(dividingBy: span) - len
                let x = x0 - y * slant
                streaks.move(to: CGPoint(x: x, y: y))
                streaks.addLine(to: CGPoint(x: x - len * slant, y: y + len))
            }
            c.stroke(streaks, with: .color(th.ink.opacity(weight * k)), lineWidth: width)
            // The same drops again where a flare is, in its colour: rain catching the
            // light as it falls through it.
            for flare in flares {
                var lit = c
                lit.blendMode = .plusLighter
                let reach = flare.reach * 0.9
                lit.clip(to: Path(ellipseIn: CGRect(x: flare.at.x - reach, y: flare.at.y - reach,
                                                    width: reach * 2, height: reach * 2)))
                lit.stroke(streaks, with: .radialGradient(
                    Gradient(colors: [flare.color.opacity(0.75 * flare.level * k), .clear]),
                    center: flare.at, startRadius: 0, endRadius: reach),
                    lineWidth: width + 0.4)
            }
        }
        for flare in flares { drawFlare(&c, s, flare, k) }
    }

    /// A flare off a sign: where it is, its colour, how far its light reaches, and how
    /// bright it is right now (0…1).
    private struct Flare {
        let at: CGPoint
        let color: Color
        let reach: CGFloat
        let level: Double
    }

    /// A film lens's flare off a sign's corner, as the tube peaks: a pin-point of light,
    /// a four-pointed glint, the long horizontal streak an anamorphic lens throws, and a
    /// light leak washing in from the nearer side of the frame. No ghost discs — loose
    /// circles of light read as orbs, not as a lens.
    private static func drawFlare(_ c: inout GraphicsContext, _ s: CGSize, _ flare: Flare, _ k: Double) {
        var light = c
        light.blendMode = .plusLighter
        let p = flare.at, a = flare.level * k
        // The leak: from whichever side edge is nearer, at the sign's height.
        let edge = CGPoint(x: p.x < s.width / 2 ? 0 : s.width, y: p.y)
        light.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
            Gradient(colors: [flare.color.opacity(0.05 * a), .clear]),
            center: edge, startRadius: 0, endRadius: s.width * 0.4))
        // The streak, centred on the corner.
        let streak = min(s.width * 0.55, flare.reach * 7)
        for (height, weight) in [(1.5, 0.38), (9.0, 0.06)] {
            let rect = CGRect(x: p.x - streak / 2, y: p.y - height / 2, width: streak, height: height)
            light.fill(Path(ellipseIn: rect), with: .linearGradient(
                Gradient(colors: [.clear, flare.color.opacity(weight * a), .clear]),
                startPoint: CGPoint(x: rect.minX, y: p.y), endPoint: CGPoint(x: rect.maxX, y: p.y)))
        }
        // The glint: four thin rays, the vertical pair shorter, as a lens's star is.
        let ray = flare.reach * 0.9
        for rect in [CGRect(x: p.x - ray, y: p.y - 0.6, width: ray * 2, height: 1.2),
                     CGRect(x: p.x - 0.6, y: p.y - ray * 0.55, width: 1.2, height: ray * 1.1)] {
            light.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.4 * a), flare.color.opacity(0.18 * a), .clear]),
                center: p, startRadius: 0, endRadius: ray))
        }
        let pin: CGFloat = 3
        light.fill(Path(ellipseIn: CGRect(x: p.x - pin, y: p.y - pin, width: pin * 2, height: pin * 2)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.8 * a), .clear]),
                                         center: p, startRadius: 0, endRadius: pin))
    }

    /// The picture's signs, by where each sits in it (0…1 across and down) and its colour.
    private static let citySigns: [(x: Double, y: Double, r: Double, color: Color)] = [
        (0.05, 0.34, 0.07, Theme.hex(0xFF3EB0)),   // pink arrow
        (0.07, 0.46, 0.06, Theme.hex(0xFFD23A)),   // yellow arrow
        (0.13, 0.41, 0.04, Theme.hex(0xFFD23A)),   // small yellow arrow
        (0.115, 0.49, 0.035, Theme.hex(0x2EE6E6)), // cyan arrow
        (0.37, 0.14, 0.06, Theme.hex(0xFF3A2E)),   // the tall red sign
        (0.32, 0.30, 0.04, Theme.hex(0xFF3A2E)),   // red ovals
        (0.35, 0.41, 0.035, Theme.hex(0xFF4A3A)),  // red lettering
        (0.43, 0.40, 0.05, Theme.hex(0xFF3E9A)),   // pink sign
        (0.475, 0.33, 0.045, Theme.hex(0x5FD8FF)), // the hologram
        (0.645, 0.38, 0.07, Theme.hex(0xFF3E9A)),  // LEVEL UP
        (0.75, 0.33, 0.06, Theme.hex(0xFFB23A)),   // the burger
    ]

    /// Each sign breathing on its own slow cycle — brightening over a few seconds and
    /// easing back, sometimes all but out — so the street looks lit and alive. Slow on
    /// purpose: a neon buzz would be a flicker, and nothing on this screen flickers.
    /// Light added over the picture (`plusLighter`), not paint, so it reads as the tube
    /// glowing harder.
    ///
    /// Returns a flare for each sign at the top of its cycle, off one of its corners, so
    /// the lens flares belong to something in the picture and come and go with it.
    private static func signs(_ c: inout GraphicsContext, _ picture: CGRect,
                              _ k: Double, _ t: Double) -> [Flare] {
        var glow = c
        glow.blendMode = .plusLighter
        var flares: [Flare] = []
        let corners: [(Double, Double)] = [(0.7, -0.6), (-0.7, -0.55), (0.65, 0.5), (-0.6, 0.6)]
        for (i, sign) in citySigns.enumerated() {
            let period = 3.5 + Double((i * 7) % 5) * 1.3
            let phase = Double(i) * 1.9
            // 0…1, lingering near the ends: smoothstep of a sine.
            let wave = (sin(t * 2 * .pi / period + phase) + 1) / 2
            let level = wave * wave * (3 - 2 * wave)
            let center = CGPoint(x: picture.minX + picture.width * sign.x,
                                 y: picture.minY + picture.height * sign.y)
            let radius = picture.width * sign.r
            glow.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2)),
                      with: .radialGradient(
                        Gradient(colors: [sign.color.opacity((0.10 + 0.32 * level) * k), .clear]),
                        center: center, startRadius: 0, endRadius: radius))
            // Only a few signs flare — the tall red one, the hologram, LEVEL UP — and each
            // over the upper half of its own cycle, so the flare swells and fades with the
            // sign over seconds. A narrow window, or picking one sign's flare at a time,
            // made them blink.
            guard Self.flaringSigns.contains(i) else { continue }
            let peak = max(0, (level - 0.5) / 0.5)
            guard peak > 0 else { continue }
            let corner = corners[i % corners.count]
            flares.append(Flare(
                at: CGPoint(x: center.x + radius * 0.8 * corner.0, y: center.y + radius * 0.8 * corner.1),
                color: sign.color,
                reach: radius * 1.6,
                level: peak * peak * (3 - 2 * peak)))
        }
        return flares
    }

    /// The signs that throw a flare, by index into `citySigns`.
    private static let flaringSigns: Set<Int> = [4, 8, 9]

    // MARK: Dune

    /// Arrakis in a sandstorm: the picture (when the build has it) under a moving sky of
    /// dust — wide banks of it rolling across on the wind and turning as they go — fine
    /// sand streaming low, and spice drifting through the air in two depths, the near
    /// motes large, soft and quick, the far ones pin-points that glint slowly. Without the
    /// picture, the same weather over the warm horizon.
    private static func dunes(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                              _ k: Double, _ t: Double) {
        let all = Path(CGRect(origin: .zero, size: s))
        if let picture = dunePicture {
            drawPicture(&c, s, picture, k, t)
            c.fill(all, with: .linearGradient(
                Gradient(stops: [.init(color: th.ground.opacity(0.55), location: 0),
                                 .init(color: th.ground.opacity(0.25), location: 0.5),
                                 .init(color: th.ground.opacity(0.45), location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
        } else {
            horizonGlow(&c, s, th.glow, k * 0.8, height: 0.6)
        }
        // Dust banks, mostly with the wind (left to right), each at its own pace, swelling
        // and sinking as they roll.
        let dust = th.accentHot, sand = th.ink, shadow = th.glowDeep
        for (i, (y, r, speed, tint, a)) in [(0.30, 0.45, 38.0, dust, 0.12), (0.62, 0.50, 24.0, sand, 0.10),
                                            (0.85, 0.55, 46.0, dust, 0.14), (0.48, 0.38, 30.0, shadow, 0.16),
                                            (0.92, 0.60, 18.0, sand, 0.10), (0.15, 0.40, 52.0, dust, 0.08),
                                            (0.72, 0.42, -14.0, shadow, 0.12), (0.55, 0.32, 60.0, sand, 0.08)
                                           ].enumerated() {
            let reach = max(s.width, s.height) * r
            let span = Double(s.width + reach * 2)
            let x = (Double(i) * 0.31 * span + t * speed).truncatingRemainder(dividingBy: span)
            let cx = CGFloat(x < 0 ? x + span : x) - reach
            let cy = s.height * y + 30 * CGFloat(sin(t * 0.15 + Double(i) * 1.3))
            let swell = reach * CGFloat(1 + 0.12 * sin(t * 0.2 + Double(i)))
            c.fill(all, with: .radialGradient(
                Gradient(stops: [.init(color: tint.opacity(a * k), location: 0),
                                 .init(color: tint.opacity(a * 0.4 * k), location: 0.55),
                                 .init(color: .clear, location: 1)]),
                center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: swell))
        }
        // Sand streaming low on the wind.
        var rng = Seeded(state: 10191)
        for _ in 0..<Int(s.width * s.height / 2200) {
            let speed = 30 + rng.next() * 60
            let span = s.width + 20
            let x = (rng.next() * span + t * speed).truncatingRemainder(dividingBy: span) - 10
            let y = s.height * (1 - pow(rng.next(), 1.8) * 0.9)
                + 4 * sin(t * (0.3 + rng.next() * 0.4) + rng.next() * 6)
            let r = 0.5 + rng.next() * 0.9
            c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2.5, height: r)),
                   with: .color(sand.opacity((0.06 + rng.next() * 0.10) * k)))
        }
        var glow = c
        glow.blendMode = .plusLighter
        // Spice blows in from the right, into Paul's face, against the dust's drift.
        // Far spice: pin-points drifting up and across, each glinting on a slow cycle.
        var far = Seeded(state: 0xD0E)
        for _ in 0..<Int(s.width * s.height / 9000) {
            let speed = 8 + far.next() * 18
            let rise = 3 + far.next() * 8
            let span = Double(s.width + 40), tall = Double(s.height + 40)
            let x = span - (far.next() * span + t * speed).truncatingRemainder(dividingBy: span) - 20
            let y = tall - (far.next() * tall + t * rise).truncatingRemainder(dividingBy: tall) - 20
            let glint = 0.5 + 0.5 * sin(t * (0.4 + far.next() * 0.5) + far.next() * 6)
            let r = 0.8 + far.next() * 1.2
            glow.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                      with: .color(th.accent.opacity((0.15 + 0.35 * glint) * k)))
        }
        // Near spice: few, large, soft and quick, bobbing as they pass the lens.
        var near = Seeded(state: 0x5B1CE)
        for _ in 0..<16 {
            let speed = 50 + near.next() * 70
            let span = Double(s.width + 80)
            let x = span - (near.next() * span + t * speed).truncatingRemainder(dividingBy: span) - 40
            let y = near.next() * Double(s.height) + 26 * sin(t * (0.5 + near.next() * 0.5) + near.next() * 6)
            let r = CGFloat(3 + near.next() * 5)
            let point = CGPoint(x: x, y: y)
            glow.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                      with: .radialGradient(Gradient(colors: [th.accentHot.opacity(0.32 * k), .clear]),
                                            center: point, startRadius: 0, endRadius: r))
        }
    }

    // MARK: Middle-earth

    /// The map's look, whatever is on it: dark paper lit by one candle. The Rivendell
    /// painting where the build has it (family build only), in its own colours and only a
    /// little darkened, or the paper alone; then the candlelight — a warm pool a little above the middle, breathing
    /// very slowly — and the edges falling away into shadow. Nothing drifting through it.
    private static func parchment(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                                  _ k: Double, _ t: Double) {
        let all = Path(CGRect(origin: .zero, size: s))
        let pictured = shirePicture != nil
        var frame: CGRect?
        if let picture = shirePicture {
            // The painting in its own colours, only a little darker, so the page's text
            // stays readable over it.
            frame = drawPicture(&c, s, picture, k, t)
            c.fill(all, with: .color(th.ground.opacity(0.25)))
            if let frame { windows(&c, frame, k, t) }
        } else {
            // Paper grain: fine flecks of darker ink.
            var rng = Seeded(state: 1954)
            for _ in 0..<Int(s.width * s.height / 900) {
                let r = 0.4 + rng.next() * 1.1
                let dot = CGRect(x: rng.next() * s.width, y: rng.next() * s.height, width: r, height: r)
                c.fill(Path(ellipseIn: dot), with: .color(Color.black.opacity((0.10 + rng.next() * 0.12) * k)))
            }
        }
        let candle = CGPoint(x: s.width * 0.5, y: s.height * 0.42)
        let breathe = 1 + 0.04 * sin(t * 0.5) + 0.02 * sin(t * 1.1 + 1)
        let reach = max(s.width, s.height) * 0.62 * breathe
        var light = c
        light.blendMode = .plusLighter
        light.fill(all, with: .radialGradient(
            Gradient(stops: [.init(color: th.glow.opacity((pictured ? 0.08 : 0.22) * k), location: 0),
                             .init(color: th.glowDeep.opacity(0.10 * k), location: 0.5),
                             .init(color: .clear, location: 1)]),
            center: candle, startRadius: 0, endRadius: reach))
        c.fill(all, with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.4),
                             .init(color: Color.black.opacity((pictured ? 0.45 : 0.65) * k), location: 1)]),
            center: candle, startRadius: 0, endRadius: max(s.width, s.height) * 0.78))
        if pictured {
            sunlight(&c, s, k, t)
            mist(&c, s, k, t)
        }
    }

    /// Lights in the Rivendell painting, as fractions of it across and down, measured off
    /// the painting itself: the flames and lamps it already shows, at full strength, and
    /// a few of the left hall's dark windows, softly.
    private static let rivendellWindows: [(x: Double, y: Double, lit: Bool)] = [
        (0.7716, 0.5138, true), (0.8200, 0.5138, true),   // the far hall's two fires
        (0.7177, 0.5232, true), (0.7258, 0.5207, true),   // its lamps by the stair
        (0.4968, 0.3903, true), (0.5060, 0.3903, true),   // lamps under the balcony
        (0.3070, 0.4478, false), (0.3410, 0.4480, false), // the left hall's arches
        (0.2656, 0.2947, false), (0.3768, 0.3560, false), // a tower, the tall window
    ]

    /// Candlelight in the windows: each a small warm point with a halo, flickering as a
    /// flame does — several quick beats on top of a slow one, irregular, never going out.
    /// Points this small dancing a little are not the full-screen flashing the "nothing
    /// flickers" rule guards against; the owner asked for flames that move.
    private static func windows(_ c: inout GraphicsContext, _ picture: CGRect, _ k: Double, _ t: Double) {
        var light = c
        light.blendMode = .plusLighter
        let flame = Color(red: 1, green: 0.74, blue: 0.38)
        for (i, window) in rivendellWindows.enumerated() {
            let n = Double(i)
            let waver = 0.72 + 0.10 * sin(t * (0.9 + n * 0.07) + n * 2.3)
                + 0.08 * sin(t * (4.3 + n * 0.37) + n * 1.1)
                + 0.06 * sin(t * (7.1 + n * 0.53) + n * 0.4)
                + 0.04 * sin(t * (11.3 + n * 0.71) + n * 2.9)
            let p = CGPoint(x: picture.minX + picture.width * window.x,
                            y: picture.minY + picture.height * window.y)
            let r = picture.width * (window.lit ? 0.0035 : 0.005)
            let layers: [(CGFloat, Double)] = window.lit ? [(1.0, 0.6), (4.0, 0.12)] : [(1.0, 0.22), (3.0, 0.06)]
            for (scale, weight) in layers {
                let radius = r * scale
                light.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                                  width: radius * 2, height: radius * 2)),
                           with: .radialGradient(Gradient(colors: [flame.opacity(weight * waver * k), .clear]),
                                                 center: p, startRadius: 0, endRadius: radius))
            }
        }
    }

    /// The sun the painting is lit by, from beyond the top-left corner: a warm bloom where
    /// it enters and long beams falling across the valley. Drawn soft — the beams are
    /// blurred heavily, so they read as light through haze rather than as shapes — each
    /// brightening and fading on a long slow breath and swinging a hair as it does.
    private static func sunlight(_ c: inout GraphicsContext, _ s: CGSize, _ k: Double, _ t: Double) {
        let sun = CGPoint(x: -s.width * 0.04, y: -s.height * 0.08)
        let warm = Color(red: 1, green: 0.88, blue: 0.64)
        var light = c
        light.blendMode = .plusLighter
        light.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
            Gradient(stops: [.init(color: warm.opacity((0.42 + 0.10 * sin(t * 0.21)) * k), location: 0),
                             .init(color: warm.opacity(0.14 * k), location: 0.3),
                             .init(color: .clear, location: 1)]),
            center: sun, startRadius: 0,
            endRadius: max(s.width, s.height) * (0.6 + 0.05 * CGFloat(sin(t * 0.17)))))
        light.drawLayer { layer in
            layer.addFilter(.blur(radius: max(s.width, s.height) * 0.03))
            let length = hypot(s.width, s.height) * 1.2
            for (i, (angle, spread, weight)) in [(0.42, 0.035, 0.42), (0.55, 0.05, 0.34), (0.70, 0.03, 0.46),
                                                 (0.84, 0.045, 0.30), (1.0, 0.03, 0.26)].enumerated() {
                let n = Double(i)
                // Each beam brightens and fades, and swings across the valley and back,
                // as light through moving cloud does.
                let breath = 0.45 + 0.55 * sin(t * (0.11 + n * 0.023) + n * 1.9)
                let a = angle + 0.07 * sin(t * (0.07 + n * 0.017) + n * 1.3)
                var beam = Path()
                beam.move(to: sun)
                beam.addLine(to: CGPoint(x: sun.x + length * CGFloat(cos(a - spread)),
                                         y: sun.y + length * CGFloat(sin(a - spread))))
                beam.addLine(to: CGPoint(x: sun.x + length * CGFloat(cos(a + spread)),
                                         y: sun.y + length * CGFloat(sin(a + spread))))
                beam.closeSubpath()
                layer.fill(beam, with: .radialGradient(
                    Gradient(colors: [warm.opacity(weight * breath * k), .clear]),
                    center: sun, startRadius: 0, endRadius: length * 0.85))
            }
        }
    }

    /// Spray from the falls rising out of the valley: a standing bank of it along the
    /// bottom, and puffs that lift off it, swell and thin out as they climb, each on its
    /// own long cycle. Drawn as mist — pale and matte, not lit.
    private static func mist(_ c: inout GraphicsContext, _ s: CGSize, _ k: Double, _ t: Double) {
        let all = Path(CGRect(origin: .zero, size: s))
        let haze = Color(red: 0.86, green: 0.88, blue: 0.90)
        c.fill(all, with: .linearGradient(
            Gradient(stops: [.init(color: .clear, location: 0.5),
                             .init(color: haze.opacity(0.12 * k), location: 0.8),
                             .init(color: haze.opacity(0.30 * k), location: 1)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
        for i in 0..<16 {
            let n = Double(i)
            let life = 12 + (n * 7).truncatingRemainder(dividingBy: 9)
            let shifted = t + n * 4.7
            let cycle = UInt64(max(0, floor(shifted / life)))
            let p = shifted.truncatingRemainder(dividingBy: life) / life
            var rng = Seeded(state: 0x41DE &+ cycle &* 6151 &+ UInt64(i) &* 9973)
            let x = s.width * CGFloat(rng.next()) + CGFloat(p) * s.width * CGFloat(rng.next() * 0.12 - 0.06)
            let y = s.height * (1.1 - 0.6 * CGFloat(p))
            let r = max(s.width, s.height) * CGFloat(0.12 + 0.24 * p + rng.next() * 0.05)
            let alpha = sin(.pi * p) * 0.30 * k
            c.fill(all, with: .radialGradient(
                Gradient(stops: [.init(color: haze.opacity(alpha), location: 0),
                                 .init(color: haze.opacity(alpha * 0.4), location: 0.5),
                                 .init(color: .clear, location: 1)]),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        }
    }

    // MARK: Synthwave and the Grid

    /// How strong a burst of fringing is at `t`, 0…1: most of the time nothing, now and
    /// then a swell lasting a fraction of a second, at uneven moments.
    private static func glitchBurst(_ t: Double, salt: UInt64) -> Double {
        let slot = 1.7
        let cycle = UInt64(max(0, floor(t / slot)))
        var rng = Seeded(state: 0xB0257 &+ cycle &* 7919 &+ salt &* 104729)
        guard rng.next() < 0.45 else { return 0 }
        let start = rng.next() * (slot - 0.5)
        let span = 0.2 + rng.next() * 0.3
        let age = t.truncatingRemainder(dividingBy: slot) - start
        guard age > 0, age < span else { return 0 }
        return sin(.pi * age / span)
    }

    /// The Glitch theme's picture: `Backdrop-synthwave.jpg`, family build only.
    nonisolated(unsafe) private static let retroPicture = picture("synthwave")

    /// A glitched signal: the picture (when the build has it) darkened, its colour
    /// fringing red and cyan, a few bands of it slid sideways and sliding back, small
    /// blocks of noise coming and going, scanlines, and a tracking band rolling slowly
    /// down. Everything moves smoothly — a real glitch jumps and flashes, and nothing on
    /// this screen may.
    private static func glitch(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                               _ k: Double, _ t: Double) {
        let all = Path(CGRect(origin: .zero, size: s))
        if let picture = retroPicture {
            let image = c.resolve(picture)
            // A burst: a stretch of a fraction of a second, at uneven moments, in which
            // the picture breaks up. Inside it time moves in hard steps — a new broken
            // frame every ~70ms, held — which is what makes it a glitch and not a slide.
            let burst = glitchBurst(t, salt: 1)
            let breaking = burst > 0
            let step = UInt64(max(0, floor(t * 15)))
            var frameRNG = Seeded(state: 0xF4A3E &+ step &* 2654435761)
            // The whole picture jolts a little when it breaks.
            let jolt = breaking && frameRNG.next() < 0.5
                ? CGPoint(x: CGFloat(frameRNG.next() * 12 - 6), y: CGFloat(frameRNG.next() * 6 - 3))
                : .zero
            var base = c
            base.translateBy(x: jolt.x, y: jolt.y)
            let frame = drawPicture(&base, s, picture, k, t)
            // Colour fringing: slight at rest; in a burst it snaps wide.
            let split: CGFloat = breaking ? CGFloat(6 + frameRNG.next() * 18) : 3
            for (dx, tint) in [(-split, th.accent), (split, th.accent2)] {
                var fringe = c
                fringe.blendMode = .plusLighter
                fringe.opacity = (breaking ? 0.32 : 0.16) * k
                fringe.addFilter(.colorMultiply(tint))
                fringe.draw(image, in: frame.offsetBy(dx: dx + jolt.x, dy: jolt.y))
            }
            if breaking {
                // Torn slices: strips of the picture shifted hard sideways, some printed
                // in one colour only.
                for _ in 0..<(4 + Int(frameRNG.next() * 7)) {
                    let y = s.height * CGFloat(frameRNG.next())
                    let h = s.height * CGFloat(0.004 + frameRNG.next() * 0.06)
                    let dx = s.width * CGFloat(frameRNG.next() * 0.3 - 0.15)
                    var slice = c
                    slice.clip(to: Path(CGRect(x: 0, y: y, width: s.width, height: h)))
                    if frameRNG.next() < 0.35 {
                        slice.addFilter(.colorMultiply(frameRNG.next() < 0.5 ? th.accent : th.accent2))
                    }
                    slice.draw(image, in: frame.offsetBy(dx: dx, dy: 0))
                }
                // Macroblocks: squares of the picture copied from somewhere else.
                for _ in 0..<(2 + Int(frameRNG.next() * 5)) {
                    let side = s.width * CGFloat(0.03 + frameRNG.next() * 0.09)
                    let rect = CGRect(x: s.width * CGFloat(frameRNG.next()), y: s.height * CGFloat(frameRNG.next()),
                                      width: side * CGFloat(1 + frameRNG.next() * 3), height: side)
                    var block = c
                    block.clip(to: Path(rect))
                    block.draw(image, in: frame.offsetBy(dx: CGFloat(frameRNG.next() * 160 - 80),
                                                         dy: CGFloat(frameRNG.next() * 120 - 60)))
                }
            }
            c.fill(all, with: .color(th.ground.opacity(0.5)))
        }
        // Blocks of noise: small rectangles of the two colours, each fading in, holding a
        // moment and fading out, at a place drawn from its slot's seed.
        for i in 0..<10 {
            let n = Double(i)
            let life = 5 + (n * 3).truncatingRemainder(dividingBy: 4)
            let shifted = t + n * 1.3
            let cycle = UInt64(max(0, floor(shifted / life)))
            let p = shifted.truncatingRemainder(dividingBy: life) / life
            var rng = Seeded(state: 0x6117 &+ cycle &* 7919 &+ UInt64(i) &* 104729)
            let rect = CGRect(x: s.width * CGFloat(rng.next()), y: s.height * CGFloat(rng.next()),
                              width: s.width * CGFloat(0.02 + rng.next() * 0.08),
                              height: CGFloat(2 + rng.next() * 10))
            let fade = min(1, min(p, 1 - p) * 4)
            let tint = rng.next() < 0.5 ? th.accent : th.accent2
            c.fill(Path(rect), with: .color(tint.opacity(0.35 * fade * k)))
        }
        scanlines(&c, s, th, k * 0.55, t, glow: false, roll: true)
    }

    /// Light cycles: a few trails of light drawn low across the dark, each on its own
    /// lane and at its own pace, one in the second colour. The horizon is only a glow.
    /// The Grid's picture: `Backdrop-grid.jpg`, family build only.
    nonisolated(unsafe) private static let gridPicture = picture("grid")

    /// Lines in the Grid picture that light runs along, as (near end, far end) in
    /// fractions of the picture — fitted to the brightest pixels along each line in the
    /// picture itself: the road's solid lane lines running to the gate (not the dashed
    /// ones: a cycle over painted dashes lit them up as beads), and the beams.
    private static let gridRoads: [((Double, Double), (Double, Double))] = [
        ((0.2716, 0.980), (0.4719, 0.560)),   // the bright line left of centre
        ((0.5143, 0.980), (0.5093, 0.550)),   // the centre line
        ((0.6419, 0.960), (0.5338, 0.600)),   // the road's right edge
    ]
    /// Fitted to the picture's brightest pixels along each beam, near end (the gate)
    /// first.
    private static let gridBeams: [((Double, Double), (Double, Double))] = [
        ((0.4776, 0.330), (0.3606, 0.030)), ((0.4639, 0.330), (0.3286, 0.030)),
        ((0.5565, 0.330), (0.6386, 0.030)), ((0.5773, 0.330), (0.6789, 0.030)),
    ]

    private static func grid(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                             _ k: Double, _ t: Double) {
        if let picture = gridPicture {
            gridScene(&c, s, th, picture, k, t)
            return
        }
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

    /// The picture, with the city running: light cycles racing up the lane lines into the
    /// distance, each dragging its long wall of light — quick and large near, small and
    /// slow far off, as perspective has it — more climbing the beams into the sky, the gate's light breathing, and haze
    /// drifting across the horizon.
    private static func gridScene(_ c: inout GraphicsContext, _ s: CGSize, _ th: Theme,
                                  _ picture: Image, _ k: Double, _ t: Double) {
        let all = Path(CGRect(origin: .zero, size: s))
        let frame = drawPicture(&c, s, picture, k, t)
        c.fill(all, with: .color(th.ground.opacity(0.3)))
        func at(_ p: (Double, Double)) -> CGPoint {
            CGPoint(x: frame.minX + frame.width * p.0, y: frame.minY + frame.height * p.1)
        }
        var light = c
        light.blendMode = .plusLighter
        let white = Color(red: 0.85, green: 0.98, blue: 1)
        // The gate.
        let gate = at((0.515, 0.42))
        let breathe = 0.75 + 0.25 * sin(t * 0.6)
        light.fill(all, with: .radialGradient(
            Gradient(colors: [white.opacity(0.22 * breathe * k), th.accent.opacity(0.08 * k), .clear]),
            center: gate, startRadius: 0, endRadius: frame.width * 0.12))
        // Pulses along a line, from its near end to its far end.
        let orange = th.accent2
        // One light cycle on a line, `e` of the way from its near end to its far end,
        // its wall of light trailing `trail` of the line behind it — towards the near end
        // when it is heading away, towards the far end when it is coming at you.
        func cycle(_ line: ((Double, Double), (Double, Double)), e: Double, away: Bool,
                   trail: Double, size: CGFloat, tint: Color, fade: Double) {
            let near = at(line.0), far = at(line.1)
            func point(_ e: Double) -> CGPoint {
                CGPoint(x: near.x + (far.x - near.x) * e, y: near.y + (far.y - near.y) * e)
            }
            func width(_ e: Double, _ scale: CGFloat) -> CGFloat { size * CGFloat(1 - e * 0.85) * scale }
            let head = point(e)
            let tailE = min(1, max(0, away ? e - trail : e + trail))
            let back = point(tailE)
            let dx = head.x - back.x, dy = head.y - back.y
            let length = max(hypot(dx, dy), 0.001)
            let nx = -dy / length, ny = dx / length
            let wHead = max(1, width(e, 0.45)), wBack = max(0.4, width(tailE, 0.12))
            func ribbon(_ scale: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: back.x + nx * wBack * scale / 2, y: back.y + ny * wBack * scale / 2))
                p.addLine(to: CGPoint(x: head.x + nx * wHead * scale / 2, y: head.y + ny * wHead * scale / 2))
                p.addLine(to: CGPoint(x: head.x - nx * wHead * scale / 2, y: head.y - ny * wHead * scale / 2))
                p.addLine(to: CGPoint(x: back.x - nx * wBack * scale / 2, y: back.y - ny * wBack * scale / 2))
                p.closeSubpath()
                return p
            }
            let along = { (a: Double) in GraphicsContext.Shading.linearGradient(
                Gradient(colors: [tint.opacity(0), tint.opacity(a * fade * k)]),
                startPoint: back, endPoint: head) }
            light.drawLayer { glow in
                glow.addFilter(.blur(radius: max(2, wHead * 1.5)))
                glow.fill(ribbon(3), with: along(0.45))
            }
            light.fill(ribbon(1), with: along(0.9))
            let r = width(e, 1)
            light.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                       with: .radialGradient(Gradient(colors: [white.opacity(0.9 * fade * k),
                                                               tint.opacity(0.5 * fade * k), .clear]),
                                             center: head, startRadius: 0, endRadius: r))
        }
        // Riders: each, run after run, picks a line at random — mostly the road, now and
        // then a beam — a speed, a trail, a colour (blue for the users, orange for the
        // other side) and which way it rides, after an uneven pause. Seeded per run, so
        // it is random to watch and steady frame to frame.
        let lines = gridRoads.map { ($0, true) } + gridBeams.map { ($0, false) }
        for rider in 0..<4 {
            var pace = Seeded(state: 0xC1C1E &+ UInt64(rider) &* 7919)
            let slot = 3.2 + pace.next() * 3.5
            let shifted = t + Double(rider) * 1.73
            let run = UInt64(max(0, floor(shifted / slot)))
            var rng = Seeded(state: 0xB1CE &+ run &* 104729 &+ UInt64(rider) &* 7919)
            let pause = rng.next() * 0.45 * slot
            let u = (shifted.truncatingRemainder(dividingBy: slot) - pause) / (slot - pause)
            guard u >= 0, u < 1 else { continue }
            let onRoad = rng.next() < 0.72
            let choices = lines.filter { $0.1 == onRoad }
            let line = choices[Int(rng.next() * Double(choices.count)) % choices.count].0
            let away = rng.next() < 0.7
            // Away: fast near, slowing into the distance; towards you: the reverse.
            let e = away ? 1 - pow(1 - u, 2.2) : 1 - pow(u, 2.2)
            let fade = min(1, u * 8) * min(1, (1 - u) * 5)
            cycle(line, e: e, away: away,
                  trail: onRoad ? 0.35 + rng.next() * 0.35 : 0.2 + rng.next() * 0.25,
                  size: onRoad ? 9 : 5,
                  tint: rng.next() < 0.38 ? orange : th.accentHot, fade: fade)
        }
        // Haze across the horizon, drifting.
        for i in 0..<5 {
            let n = Double(i)
            let span = Double(s.width) * 1.6
            let x = (n * 0.37 * span + t * (10 + n * 4)).truncatingRemainder(dividingBy: span) - Double(s.width) * 0.3
            let center = CGPoint(x: x, y: Double(at((0.5, 0.44 + 0.04 * n)).y))
            c.fill(all, with: .radialGradient(
                Gradient(colors: [(i == 2 ? orange : th.accent).opacity(0.07 * k), .clear]),
                center: center, startRadius: 0, endRadius: frame.width * 0.22))
        }
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
