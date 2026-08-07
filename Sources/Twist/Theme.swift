import AppKit
import SwiftUI

/// The game's palette.
///
/// Two things drive it. It should read as purple rather than as a grey app with a purple
/// button, so the tint reaches the surfaces and the backgrounds too. And it should not glare:
/// the light scheme is a soft lavender-white rather than `#FFFFFF`, and the dark scheme a deep
/// plum rather than black, because a flat white field behind a two-minute timer is tiring.
///
/// Colours are built as dynamic `NSColor`s rather than fixed values, so one definition serves
/// both appearances and the system switch keeps working.
enum Theme {
    /// Page background. Never pure white, never pure black.
    static let background = dynamic(light: 0xF6F2FC, dark: 0x16111F)

    /// Panels sitting on the background — the score bar and the play area.
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1E1829)

    /// An unfilled slot, or a tile that has been spoken for.
    static let slot = dynamic(light: 0xEAE2F7, dark: 0x241D31)

    /// A rack tile at rest.
    static let tile = dynamic(light: 0xE4DAF5, dark: 0x2E2540)

    /// A rack tile under the pointer.
    static let tileHover = dynamic(light: 0xD8C9F2, dark: 0x3A2F52)

    /// The accent. Deeper on light so text stays legible on it, brighter on dark so it glows
    /// slightly rather than sinking into the background.
    ///
    /// The light value is not free to lighten: a found word is drawn in this colour on
    /// `accentSoft`, and #6D3FD4 measured 4.36:1 there, under the 4.5:1 floor for body text.
    /// #6836CC gives 4.84:1 on the fill and 6.37:1 on the page.
    static let accent = dynamic(light: 0x6836CC, dark: 0xAE8CFF)

    /// Fill behind a word you have found, and behind a staged letter.
    static let accentSoft = dynamic(light: 0xDDD0F8, dark: 0x392B58)

    static let textPrimary = dynamic(light: 0x241B36, dark: 0xEFE8FB)
    static let textSecondary = dynamic(light: 0x6B5F80, dark: 0x9E92B5)

    /// The dots standing in for a word you have not found yet. Deliberately low contrast: it is
    /// a hint about length, not something to read.
    static let textFaint = dynamic(light: 0xA99BC0, dark: 0x5E5177)

    static let hairline = dynamic(light: 0xE0D6F2, dark: 0x2C2340)

    /// Border for buttons, as opposed to the tile grid. Stronger than `hairline`, which is
    /// close enough to the tile fill in light mode that a bordered button reads as edgeless.
    static let controlBorder = dynamic(light: 0xC0ACE6, dark: 0x483A63)

    /// Positive feedback. A green that belongs to this palette rather than the system's.
    static let positive = dynamic(light: 0x2E7D57, dark: 0x6FD9A6)

    /// The timer running out. Warm rather than alarming — this game does not shout.
    static let urgent = dynamic(light: 0xB4453C, dark: 0xFF9E8F)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1)
    }
}

/// Which appearance the game uses, independent of the system setting.
///
/// Worth having its own control: the system switch is a whole-machine decision, and wanting a
/// dark game on a light desktop is an ordinary preference rather than an edge case.
enum Appearance: String, CaseIterable, Identifiable, Hashable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
