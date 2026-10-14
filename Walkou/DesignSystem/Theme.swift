import SwiftUI
import UIKit

/// Colors and type from the Walkou moodboard: bright cards, indigo accents,
/// heavy italic numbers and a dark teal navigation map.
enum Theme {
    // Brand
    static let indigo = Color(hex: 0x5B5CE2)
    static let indigoDeep = Color(hex: 0x4338CA)
    static let green = Color(hex: 0x57C15C)
    static let orange = Color(hex: 0xFF8A2A)
    static let blue = Color(hex: 0x1E8FFF)
    static let mint = Color(hex: 0x6FE3C8)
    static let mintDeep = Color(hex: 0x16B8A6)
    static let danger = Color(hex: 0xFF5A4E)

    // Navigation (always dark)
    static let navBackground = Color(hex: 0x0B1416)
    static let navSurface = Color(hex: 0x12262A)
    static let navSurfaceRaised = Color(hex: 0x1A3438)

    // Adaptive surfaces
    static let background = Color(light: 0xF2F3F8, dark: 0x0B0B0F)
    static let card = Color(light: 0xFFFFFF, dark: 0x1B1C22)
    static let cardSecondary = Color(light: 0xF0F1F6, dark: 0x25262D)
    static let textSecondary = Color(light: 0x6B6E7B, dark: 0x9A9DAA)
    static let separator = Color(light: 0xE6E7EE, dark: 0x2C2D35)

    /// Colors for the three suggested routes.
    static let routeColors: [Color] = [indigo, orange, mintDeep]

    static let cornerRadius: CGFloat = 28

    static let sunsetGradient = LinearGradient(
        colors: [Color(hex: 0xFFB36B), Color(hex: 0xFF7A3D), Color(hex: 0x6D4CE0), Color(hex: 0x231B4D)],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension Font {
    /// Big italic numbers like "4,91K".
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default).italic()
    }

    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
