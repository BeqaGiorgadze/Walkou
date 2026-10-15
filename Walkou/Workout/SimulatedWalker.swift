import Foundation
import CoreLocation

/// Test autopilot: produces fake GPS fixes that walk the route (or toward gems in free walk),
/// so gems, voice guidance and milestones can be tried in the Simulator or at a desk.
/// Only switched on from the Developer section in Settings (debug builds).
struct SimulatedWalker {
    struct Settings: Equatable {
        /// 1 = real walking speed (1.4 m/s).
        var speedMultiplier: Double = 5
        /// Adds GPS jitter and occasional weak fixes, like a night walk between buildings.
        var noisyGPS = false
    }

    static let walkingSpeed: Double = 1.4

    let settings: Settings
    private(set) var position: CLLocationCoordinate2D
    private(set) var course: Double = Double.random(in: 0..<360)

    private var routeID: UUID?
    private var tracker: RouteTracker?
    private var along: Double = 0
    private var visitedBonus = Set<Int>()
    private var detour: Detour?
    private var tick = 0

    private enum Detour {
        case toGem(id: Int, returnTo: CLLocationCoordinate2D)
        case back(to: CLLocationCoordinate2D)
    }

    init(start: CLLocationCoordinate2D, settings: Settings) {
        self.position = start
        self.settings = settings
    }

    /// Moves for `seconds` and returns the GPS fix a phone would report there.
    mutating func advance(seconds: Double, route: PlannedRoute?, gems: [Gem]) -> CLLocation {
        let meters = Self.walkingSpeed * settings.speedMultiplier * seconds
        if let detour {
            followDetour(detour, meters: meters, gems: gems)
        } else if let route {
            followRoute(route, meters: meters, gems: gems)
        } else {
            wander(meters: meters, gems: gems)
        }
        return makeFix()
    }

    // MARK: - Movement

    private mutating func followRoute(_ route: PlannedRoute, meters: Double, gems: [Gem]) {
        if routeID != route.id {
            routeID = route.id
            tracker = RouteTracker(route: route)
            along = 0
            if let start = route.start { position = start }
        }
        guard let tracker else { return }

        // Pop over to a bonus gem when passing close to it, then come back.
        if let bonus = gems.first(where: {
            !$0.isCollected && $0.detourSteps != nil && !visitedBonus.contains($0.id)
                && Geo.distance(position, $0.coordinate) < 160
        }) {
            visitedBonus.insert(bonus.id)
            detour = .toGem(id: bonus.id, returnTo: position)
            followDetour(detour!, meters: meters, gems: gems)
            return
        }

        along = min(tracker.totalDistance, along + meters)
        if let next = tracker.coordinate(atDistance: along) {
            if Geo.distance(position, next) > 0.5 { course = Geo.bearing(from: position, to: next) }
            position = next
        }
    }

    private mutating func followDetour(_ current: Detour, meters: Double, gems: [Gem]) {
        switch current {
        case let .toGem(id, returnTo):
            guard let gem = gems.first(where: { $0.id == id }), !gem.isCollected else {
                detour = .back(to: returnTo)
                return
            }
            if move(toward: gem.coordinate, meters: meters) { detour = .back(to: returnTo) }
        case let .back(target):
            if move(toward: target, meters: meters) { detour = nil }
        }
    }

    private mutating func wander(meters: Double, gems: [Gem]) {
        let nearest = gems
            .filter { !$0.isCollected }
            .min { Geo.distance(position, $0.coordinate) < Geo.distance(position, $1.coordinate) }
        if let nearest, Geo.distance(position, nearest.coordinate) < 600 {
            _ = move(toward: nearest.coordinate, meters: meters)
        } else {
            course = (course + Double.random(in: -8...8) + 360).truncatingRemainder(dividingBy: 360)
            position = Geo.destination(from: position, bearing: course, meters: meters)
        }
    }

    /// Returns true once the target is reached.
    private mutating func move(toward target: CLLocationCoordinate2D, meters: Double) -> Bool {
        let distance = Geo.distance(position, target)
        guard distance > meters else {
            position = target
            return true
        }
        course = Geo.bearing(from: position, to: target)
        position = Geo.destination(from: position, bearing: course, meters: meters)
        return false
    }

    // MARK: - GPS fix

    private mutating func makeFix() -> CLLocation {
        tick += 1
        var reported = position
        var accuracy = 5.0
        if settings.noisyGPS {
            if tick % 7 == 0 {
                // Weak fix: far off and inaccurate, like a narrow street at night.
                accuracy = Double.random(in: 40...60)
                reported = Geo.destination(from: position, bearing: Double.random(in: 0..<360), meters: Double.random(in: 15...35))
            } else {
                accuracy = Double.random(in: 10...25)
                reported = Geo.destination(from: position, bearing: Double.random(in: 0..<360), meters: Double.random(in: 0...10))
            }
        }
        // Report walking speed, not the sped-up speed, so gems still count (they're ignored above 25 km/h).
        return CLLocation(
            coordinate: reported,
            altitude: 450,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            course: course,
            speed: Self.walkingSpeed,
            timestamp: Date()
        )
    }
}
