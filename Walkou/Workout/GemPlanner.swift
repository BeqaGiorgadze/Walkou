import Foundation
import CoreLocation

/// Places gems for a workout.
///
/// - On a planned route: common gems about every 350 m, one or two rare ones, and a legendary gem at the finish.
/// - Bonus gems: a few spots 50–150 m off the route on a real street, with the extra steps of the detour.
/// - Free walk: gems pop up ahead of you as you walk, and a gold gem waits at your start after halfway.
enum GemPlanner {
    static let spacing: Double = 350
    /// Bonus detours longer than this (one way) are dropped.
    static let maxDetour: Double = 260
    /// Every placed gem gets an id from its own range so lists never collide.
    static let bonusIDBase = 1000
    static let freeIDBase = 2000

    // MARK: - On-route gems

    static func routeGems(for route: PlannedRoute) -> [Gem] {
        var generator = SystemRandomNumberGenerator()
        return routeGems(for: route, using: &generator)
    }

    static func routeGems<G: RandomNumberGenerator>(for route: PlannedRoute, using generator: inout G) -> [Gem] {
        let tracker = RouteTracker(route: route)
        let total = tracker.totalDistance
        guard total > 0, let end = route.end else { return [] }

        var gems: [Gem] = []
        if total >= 300 {
            let count = max(3, Int(total / spacing))
            let step = total / Double(count + 1)
            for k in 1...count {
                let along = step * Double(k)
                guard let coordinate = tracker.coordinate(atDistance: along) else { continue }
                gems.append(Gem(id: k, kind: .common, coordinate: coordinate, distanceIntoRoute: along))
            }
            // Turn one or two of them (never the first) into rare gems, sometimes a special one.
            let rareCount = total > 3000 ? 2 : 1
            var candidates = Array(1..<gems.count)
            candidates.shuffle(using: &generator)
            for index in candidates.prefix(rareCount) {
                let roll = Double.random(in: 0..<1, using: &generator)
                let kind: GemKind = roll < 0.06 ? .heart : (roll < 0.12 ? .amber : .rare)
                let old = gems[index]
                gems[index] = Gem(id: old.id, kind: kind, coordinate: old.coordinate, distanceIntoRoute: old.distanceIntoRoute)
            }
        }
        gems.append(Gem(id: 999, kind: .legendary, coordinate: end, distanceIntoRoute: total))
        return gems
    }

    /// How many bonus gems a route of this length offers.
    static func bonusCount(forDistance meters: Double) -> Int {
        switch meters {
        case ..<1500: return 0
        case ..<3000: return 1
        case ..<5500: return 2
        default: return 3
        }
    }

    // MARK: - Bonus gems (need walking directions to find a real street)

    static func bonusGems(for route: PlannedRoute, strideLength: Double) async -> [Gem] {
        let tracker = RouteTracker(route: route)
        let total = tracker.totalDistance
        let count = bonusCount(forDistance: total)
        guard count > 0 else { return [] }

        let fractions = [0.3, 0.55, 0.8].prefix(count)
        var gems: [Gem] = []
        for (index, fraction) in fractions.enumerated() {
            let along = total * fraction
            guard let base = tracker.coordinate(atDistance: along),
                  let before = tracker.coordinate(atDistance: along - 15),
                  let after = tracker.coordinate(atDistance: along + 15) else { continue }
            let routeBearing = Geo.bearing(from: before, to: after)
            let side: Double = Bool.random() ? 90 : -90
            let target = Geo.destination(from: base, bearing: routeBearing + side, meters: Double.random(in: 80...130))

            guard let legs = try? await WalkingDirections.legs(through: [base, target]),
                  let path = legs.first?.coordinates, let spot = path.last else { continue }
            let detour = legs.reduce(0) { $0 + $1.distance }
            // Skip spots that snapped back onto the route or need a long trek.
            guard detour >= 40, detour <= maxDetour,
                  distance(from: spot, toPolyline: route.coordinates) >= 35 else { continue }

            var gem = Gem(id: bonusIDBase + index, kind: .bonus, coordinate: spot, distanceIntoRoute: nil)
            gem.detourPath = path
            gem.detourSteps = Int((detour * 2 / strideLength).rounded(.up))
            gems.append(gem)
        }
        return gems
    }

    // MARK: - Free walk

    /// A gem 120–200 m ahead of the walker, on a street they can reach.
    static func freeWalkGem(near location: CLLocation, id: Int) async -> Gem? {
        let course = location.course >= 0 ? location.course : Double.random(in: 0..<360)
        let bearing = course + Double.random(in: -60...60)
        let target = Geo.destination(from: location.coordinate, bearing: bearing, meters: Double.random(in: 120...200))
        guard let legs = try? await WalkingDirections.legs(through: [location.coordinate, target]),
              let spot = legs.first?.coordinates.last else { return nil }
        let walk = legs.reduce(0) { $0 + $1.distance }
        guard walk >= 60, walk <= 350 else { return nil }
        let kind: GemKind = Double.random(in: 0..<1) < 0.15 ? .bonus : .common
        return Gem(id: id, kind: kind, coordinate: spot, distanceIntoRoute: nil)
    }

    static func goldGemAtStart(_ start: CLLocationCoordinate2D) -> Gem {
        Gem(id: 1999, kind: .legendary, coordinate: start, distanceIntoRoute: nil)
    }

    // MARK: - Helpers

    static func distance(from point: CLLocationCoordinate2D, toPolyline coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return coordinates.first.map { Geo.distance(point, $0) } ?? .infinity }
        var best = Double.infinity
        for i in 1..<coordinates.count {
            best = min(best, Geo.project(point, ontoSegment: coordinates[i - 1], coordinates[i]).distance)
        }
        return best
    }
}

/// Deterministic generator for tests and repeatable previews.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
