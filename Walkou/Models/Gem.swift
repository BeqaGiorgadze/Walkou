import Foundation
import CoreLocation
import SwiftUI

/// The kinds of gems you can find on a walk.
enum GemKind: String, Codable, CaseIterable, Identifiable {
    case common
    case bonus
    case rare
    case legendary
    /// A sealed sweat jar crystallizes into one of these.
    case crystal
    // Special rare finds shown on the collection shelf.
    case heart
    case amber
    // Seasonal, not dropping yet (locked on the shelf).
    case shard
    case cushion

    var id: String { rawValue }

    var points: Int {
        switch self {
        case .common: return 1
        case .bonus: return 3
        case .rare, .heart, .amber, .shard, .cushion: return 5
        case .legendary, .crystal: return 10
        }
    }

    var imageName: String {
        switch self {
        case .common: return "GemCommon"
        case .bonus: return "GemBonus"
        case .rare: return "GemRare"
        case .legendary: return "GemLegendary"
        case .crystal: return "GemCrystal"
        case .heart: return "GemHeart"
        case .amber: return "GemAmber"
        case .shard: return "GemShard"
        case .cushion: return "GemCushion"
        }
    }

    /// Short label for the collect tag ("RARE GEM").
    var tagTitle: String {
        switch self {
        case .common: return "GEM"
        case .bonus: return "BONUS GEM"
        case .rare: return "RARE GEM"
        case .legendary: return "LEGENDARY"
        case .crystal: return "SWEAT CRYSTAL"
        case .heart: return "SAPPHIRE HEART"
        case .amber: return "AMBER DROP"
        case .shard: return "RUBY SHARD"
        case .cushion: return "JADE SQUARE"
        }
    }

    /// Name on the collection shelf.
    var shelfName: String {
        switch self {
        case .common: return "Blue Oval"
        case .bonus: return "Green Kite"
        case .rare: return "Pink Crystal"
        case .legendary: return "Gold Diamond"
        case .crystal: return "Sweat Crystal"
        case .heart: return "Sapphire Heart"
        case .amber: return "Amber Drop"
        case .shard: return "Ruby Shard"
        case .cushion: return "Jade Square"
        }
    }

    /// Glow color used behind the gem when it's collected.
    var glow: Color {
        switch self {
        case .common, .heart: return Color(hex: 0x2F6BFF)
        case .bonus, .cushion: return Color(hex: 0x1FB863)
        case .rare, .shard: return Color(hex: 0xE8337E)
        case .legendary: return Color(hex: 0xFFB020)
        case .crystal: return Color(hex: 0x4FC3FF)
        case .amber: return Color(hex: 0xE86A00)
        }
    }

    /// Size on the map in points.
    var mapSize: CGFloat {
        switch self {
        case .common: return 24
        case .bonus, .rare, .heart, .amber, .shard, .cushion, .crystal: return 30
        case .legendary: return 38
        }
    }

    var isSeasonal: Bool { self == .shard || self == .cushion }

    /// Order used on the shelf and in summaries.
    static let shelfOrder: [GemKind] = [.common, .rare, .legendary, .crystal, .bonus, .heart, .amber, .shard, .cushion]
    static let haulOrder: [GemKind] = [.common, .rare, .legendary, .bonus]

    /// Kinds counted together in summaries (specials count as rare).
    var haulKind: GemKind {
        switch self {
        case .heart, .amber, .shard, .cushion: return .rare
        default: return self
        }
    }
}

/// A gem placed on the map for one workout.
struct Gem: Identifiable, Equatable {
    let id: Int
    let kind: GemKind
    let coordinate: CLLocationCoordinate2D
    /// Meters along the route for gems that sit on it. Nil for off-route gems (bonus, free walk, gold-at-start).
    let distanceIntoRoute: Double?
    /// Walking path from the route to an off-route bonus gem (drawn dashed).
    var detourPath: [CLLocationCoordinate2D] = []
    /// Extra steps for the round trip to a bonus gem.
    var detourSteps: Int?
    var isCollected = false

    static func == (lhs: Gem, rhs: Gem) -> Bool {
        lhs.id == rhs.id && lhs.isCollected == rhs.isCollected && lhs.kind == rhs.kind && lhs.detourSteps == rhs.detourSteps
    }
}

/// Gem counts per kind, stored with each workout.
struct GemTally: Codable, Equatable {
    var counts: [String: Int] = [:]

    subscript(kind: GemKind) -> Int {
        get { counts[kind.rawValue] ?? 0 }
        set { counts[kind.rawValue] = newValue }
    }

    var total: Int { counts.values.reduce(0, +) }

    var points: Int { GemKind.allCases.reduce(0) { $0 + self[$1] * $1.points } }

    static func + (lhs: GemTally, rhs: GemTally) -> GemTally {
        var result = lhs
        for (key, value) in rhs.counts { result.counts[key, default: 0] += value }
        return result
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data?) -> GemTally {
        guard let data, let tally = try? JSONDecoder().decode(GemTally.self, from: data) else { return GemTally() }
        return tally
    }
}

/// Levels and titles from lifetime gem points.
struct GemLevel: Equatable {
    let number: Int
    let title: String
    /// Points needed to reach this level.
    let threshold: Int
    /// Points needed for the next level (nil at the top of the table).
    let nextThreshold: Int?

    static let table: [(title: String, threshold: Int)] = [
        ("Walker", 0),
        ("Explorer", 50),
        ("Pathfinder", 150),
        ("Trailblazer", 400),
        ("Legend", 1000),
    ]

    static func forPoints(_ points: Int) -> GemLevel {
        let table = GemLevel.table
        if points >= table.last!.threshold {
            // Beyond Legend: a new level every 1,000 points.
            let extra = (points - table.last!.threshold) / 1000
            let number = table.count + extra
            let threshold = table.last!.threshold + extra * 1000
            let title = extra == 0 ? "Legend" : "Legend \(romanNumeral(extra + 1))"
            return GemLevel(number: number, title: title, threshold: threshold, nextThreshold: threshold + 1000)
        }
        var index = 0
        for (i, entry) in table.enumerated() where points >= entry.threshold { index = i }
        return GemLevel(number: index + 1, title: table[index].title, threshold: table[index].threshold, nextThreshold: table[index + 1].threshold)
    }

    var nextTitle: String? {
        guard number < GemLevel.table.count else { return nil }
        return GemLevel.table[number].title
    }

    func progress(points: Int) -> Double {
        guard let next = nextThreshold, next > threshold else { return 1 }
        return min(1, max(0, Double(points - threshold) / Double(next - threshold)))
    }

    private static func romanNumeral(_ n: Int) -> String {
        let table: [(Int, String)] = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n, result = ""
        for (value, symbol) in table { while n >= value { result += symbol; n -= value } }
        return result
    }
}
