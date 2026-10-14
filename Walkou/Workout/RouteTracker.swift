import Foundation
import CoreLocation

/// Follows the user's position along a route: progress, off-route detection and the next turn.
///
/// Matching is restricted to a window around the current progress so loops (start == end) and
/// out-and-back sections on the same street do not make progress jump.
struct RouteTracker {
    struct Snapshot: Equatable {
        var progress: Double
        var remaining: Double
        var distanceFromRoute: Double
        var isOffRoute: Bool
        var isComplete: Bool
        var nextInstruction: NavigationInstruction?
        var distanceToNextInstruction: Double?
    }

    let coordinates: [CLLocationCoordinate2D]
    let cumulative: [Double]
    let instructions: [NavigationInstruction]

    /// Beyond this distance from the route a fix counts as "off route".
    var offRouteThreshold: Double = 40
    /// The user is back on route once closer than this.
    var onRouteThreshold: Double = 25
    /// Consecutive off-route fixes needed before we flag it (GPS jitter guard).
    var offRouteFixesRequired = 3
    /// How far ahead of current progress a normal match may land.
    var lookAhead: Double = 250
    /// How far behind current progress a normal match may land.
    var lookBehind: Double = 30
    /// Remaining distance at which the route counts as finished.
    var completionDistance: Double = 25

    private(set) var progress: Double = 0
    private(set) var isOffRoute = false
    private(set) var isComplete = false
    private var offRouteFixes = 0

    init(coordinates: [CLLocationCoordinate2D], instructions: [NavigationInstruction]) {
        self.coordinates = coordinates
        self.cumulative = Geo.cumulativeDistances(coordinates)
        self.instructions = instructions.sorted { $0.distanceIntoRoute < $1.distanceIntoRoute }
    }

    init(route: PlannedRoute) {
        self.init(coordinates: route.coordinates, instructions: route.instructions)
    }

    var totalDistance: Double { cumulative.last ?? 0 }

    /// Index of the last vertex at or before the current progress (for splitting walked/remaining).
    var progressVertexIndex: Int {
        guard !cumulative.isEmpty else { return 0 }
        var low = 0
        var high = cumulative.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if cumulative[mid] <= progress { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The coordinate at a distance along the route (clamped to the route).
    func coordinate(atDistance meters: Double) -> CLLocationCoordinate2D? {
        guard let first = coordinates.first else { return nil }
        guard coordinates.count > 1 else { return first }
        let target = min(max(0, meters), totalDistance)
        for i in 1..<coordinates.count where cumulative[i] >= target {
            let segment = cumulative[i] - cumulative[i - 1]
            let t = segment > 0 ? (target - cumulative[i - 1]) / segment : 0
            return Geo.interpolate(coordinates[i - 1], coordinates[i], fraction: t)
        }
        return coordinates.last
    }

    /// The part of the route already covered, and the part still ahead.
    func split() -> (walked: [CLLocationCoordinate2D], remaining: [CLLocationCoordinate2D]) {
        guard coordinates.count > 1, let here = coordinate(atDistance: progress) else {
            return ([], coordinates)
        }
        let index = progressVertexIndex
        let walked = Array(coordinates[0...index]) + [here]
        let remaining = [here] + Array(coordinates[min(index + 1, coordinates.count - 1)...])
        return (walked, remaining)
    }

    mutating func update(with location: CLLocationCoordinate2D) -> Snapshot {
        guard coordinates.count > 1 else {
            isComplete = true
            return snapshot(distanceFromRoute: 0)
        }

        let windowMatch = bestMatch(for: location, from: progress - lookBehind, to: progress + lookAhead)
        var matchedDistance = windowMatch?.distance ?? .infinity

        if let match = windowMatch, match.distance <= offRouteThreshold {
            progress = max(progress - lookBehind, match.along)
        } else if let rejoin = firstMatchAhead(for: location, after: progress + lookAhead, within: onRouteThreshold) {
            // The user cut across to a later part of the route: snap forward.
            progress = rejoin.along
            matchedDistance = rejoin.distance
        }

        if matchedDistance > offRouteThreshold {
            offRouteFixes += 1
            if offRouteFixes >= offRouteFixesRequired { isOffRoute = true }
        } else {
            offRouteFixes = 0
            if matchedDistance <= onRouteThreshold || !isOffRoute { isOffRoute = false }
        }

        if totalDistance - progress <= completionDistance {
            isComplete = true
        }

        return snapshot(distanceFromRoute: matchedDistance)
    }

    // MARK: - Private

    private struct Match {
        let distance: Double
        let along: Double
    }

    private func bestMatch(for point: CLLocationCoordinate2D, from start: Double, to end: Double) -> Match? {
        var best: Match?
        for i in 1..<coordinates.count {
            // Skip segments that lie entirely outside the window.
            if cumulative[i] < start || cumulative[i - 1] > end { continue }
            let projection = Geo.project(point, ontoSegment: coordinates[i - 1], coordinates[i])
            let along = cumulative[i - 1] + projection.fraction * (cumulative[i] - cumulative[i - 1])
            if best == nil || projection.distance < best!.distance {
                best = Match(distance: projection.distance, along: along)
            }
        }
        return best
    }

    private func firstMatchAhead(for point: CLLocationCoordinate2D, after start: Double, within threshold: Double) -> Match? {
        for i in 1..<coordinates.count where cumulative[i] >= start {
            let projection = Geo.project(point, ontoSegment: coordinates[i - 1], coordinates[i])
            if projection.distance <= threshold {
                let along = cumulative[i - 1] + projection.fraction * (cumulative[i] - cumulative[i - 1])
                return Match(distance: projection.distance, along: along)
            }
        }
        return nil
    }

    private func snapshot(distanceFromRoute: Double) -> Snapshot {
        let next = instructions.first { $0.distanceIntoRoute > progress + 3 }
        return Snapshot(
            progress: progress,
            remaining: max(0, totalDistance - progress),
            distanceFromRoute: distanceFromRoute.isFinite ? distanceFromRoute : 0,
            isOffRoute: isOffRoute,
            isComplete: isComplete,
            nextInstruction: next,
            distanceToNextInstruction: next.map { max(0, $0.distanceIntoRoute - progress) }
        )
    }
}
