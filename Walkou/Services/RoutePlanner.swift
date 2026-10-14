import Foundation
import MapKit

/// Builds walking routes of a target length with Apple MapKit.
///
/// MapKit only does A→B directions, so routes are shaped by picking waypoints:
/// - Loop: a triangle start → A → B → start, sized so the walked distance matches the goal.
/// - One way: a single destination in some direction.
/// Each candidate is measured and re-scaled once if it misses the target.
struct RoutePlanner {
    enum PlannerError: LocalizedError {
        case noRoutesFound
        case throttled

        var errorDescription: String? {
            switch self {
            case .noRoutesFound:
                return "We couldn't find walkable routes around you. Try a different goal or move closer to streets or paths."
            case .throttled:
                return "Apple Maps needs a short break. Please try again in a minute."
            }
        }
    }

    /// Walking routes are longer than straight lines; this is the usual ratio in cities.
    private let detourFactor = 1.3
    /// A candidate within this fraction of the target is good enough.
    private let tolerance = 0.07

    /// Up to `count` route suggestions for the plan, ordered by how close they are to the target.
    func suggestions(from origin: CLLocationCoordinate2D, plan: WorkoutPlan, count: Int = 3) async throws -> [PlannedRoute] {
        let target = plan.targetDistance
        let baseBearing = Double.random(in: 0..<360)
        let bearings = (0..<count).map { baseBearing + Double($0) * 360 / Double(count) }

        var routes: [PlannedRoute] = []
        var throttled = false
        try await withThrowingTaskGroup(of: PlannedRoute?.self) { group in
            for bearing in bearings {
                group.addTask {
                    do {
                        switch plan.mode {
                        case .loop:
                            return try await loopRoute(from: origin, bearing: bearing, target: target)
                        case .oneWay:
                            return try await oneWayRoute(from: origin, bearing: bearing, target: target)
                        case .free:
                            return nil
                        }
                    } catch let error as MKError where error.code == .loadingThrottled {
                        throw PlannerError.throttled
                    } catch {
                        return nil
                    }
                }
            }
            do {
                for try await route in group {
                    if let route { routes.append(route) }
                }
            } catch PlannerError.throttled {
                throttled = true
            }
        }

        if routes.isEmpty {
            throw throttled ? PlannerError.throttled : PlannerError.noRoutesFound
        }

        return routes
            .sorted { abs($0.distance - target) < abs($1.distance - target) }
            .enumerated()
            .map { index, route in
                var route = route
                route.colorIndex = index
                return route
            }
    }

    /// Simple A→B walking directions, used for detours and "take me back to start".
    func directions(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, name: String) async throws -> PlannedRoute {
        let leg = try await walkingLeg(from: origin, to: destination)
        return combine(legs: [leg], name: name, kind: .oneWay, finishText: "You've arrived")
    }

    // MARK: - Shapes

    private func loopRoute(from origin: CLLocationCoordinate2D, bearing: Double, target: Double) async throws -> PlannedRoute {
        // Equilateral triangle with the start as one corner.
        var side = target / (3 * detourFactor)
        var best: (legs: [MKRoute], distance: Double)?

        for _ in 0..<2 {
            let a = Geo.destination(from: origin, bearing: bearing - 30, meters: side)
            let b = Geo.destination(from: origin, bearing: bearing + 30, meters: side)
            let legs = [
                try await walkingLeg(from: origin, to: a),
                try await walkingLeg(from: a, to: b),
                try await walkingLeg(from: b, to: origin),
            ]
            let distance = legs.reduce(0) { $0 + $1.distance }
            if best == nil || abs(distance - target) < abs(best!.distance - target) {
                best = (legs, distance)
            }
            if abs(distance - target) / target <= tolerance || distance <= 0 { break }
            side *= target / distance
        }

        guard let best else { throw PlannerError.noRoutesFound }
        let name = "\(Geo.compassName(forBearing: bearing)) loop" + viaName(best.legs)
        return combine(legs: best.legs, name: name, kind: .loop, finishText: "Loop complete. You're back at the start")
    }

    private func oneWayRoute(from origin: CLLocationCoordinate2D, bearing: Double, target: Double) async throws -> PlannedRoute {
        var straight = target / detourFactor
        var best: MKRoute?

        for _ in 0..<2 {
            let destination = Geo.destination(from: origin, bearing: bearing, meters: straight)
            let leg = try await walkingLeg(from: origin, to: destination)
            if best == nil || abs(leg.distance - target) < abs(best!.distance - target) {
                best = leg
            }
            if abs(leg.distance - target) / target <= tolerance || leg.distance <= 0 { break }
            straight *= target / leg.distance
        }

        guard let best else { throw PlannerError.noRoutesFound }
        let name = "\(Geo.compassName(forBearing: bearing))bound" + viaName([best])
        return combine(legs: [best], name: name, kind: .oneWay, finishText: "You've reached the finish")
    }

    // MARK: - MapKit

    private func walkingLeg(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw PlannerError.noRoutesFound }
        return route
    }

    private func viaName(_ legs: [MKRoute]) -> String {
        guard let longest = legs.max(by: { $0.distance < $1.distance }), !longest.name.isEmpty else { return "" }
        return " via \(longest.name)"
    }

    /// Stitches legs into one polyline with turn instructions placed along it.
    private func combine(legs: [MKRoute], name: String, kind: WorkoutMode, finishText: String) -> PlannedRoute {
        var coordinates: [CLLocationCoordinate2D] = []
        var instructions: [NavigationInstruction] = []
        var offset = 0.0

        for (legIndex, leg) in legs.enumerated() {
            var legCoordinates = leg.polyline.coordinateArray
            if !coordinates.isEmpty, !legCoordinates.isEmpty {
                legCoordinates.removeFirst() // shared with the previous leg's last point
            }
            coordinates.append(contentsOf: legCoordinates)

            // MapKit's step distances and our polyline geometry differ slightly; scale to match.
            let geometryLength = Geo.length(leg.polyline.coordinateArray)
            let scale = leg.distance > 0 ? geometryLength / leg.distance : 1
            let isLastLeg = legIndex == legs.count - 1
            var stepStart = 0.0

            for (stepIndex, step) in leg.steps.enumerated() {
                defer { stepStart += step.distance * scale }
                let isLastStep = stepIndex == leg.steps.count - 1
                if isLastStep && !isLastLeg { continue } // "Arrive at …" between our own waypoints
                var text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                if isLastStep && isLastLeg { text = finishText }
                guard !text.isEmpty else { continue }
                instructions.append(NavigationInstruction(
                    id: instructions.count,
                    text: text,
                    distanceIntoRoute: offset + stepStart
                ))
            }
            offset += geometryLength
        }

        // Make the finish instruction sit exactly at the end of the route.
        let total = Geo.length(coordinates)
        if let last = instructions.last, last.text == finishText {
            instructions[instructions.count - 1] = NavigationInstruction(id: last.id, text: finishText, distanceIntoRoute: total)
        }

        return PlannedRoute(
            name: name,
            kind: kind,
            coordinates: coordinates,
            distance: total,
            instructions: instructions
        )
    }
}

extension MKMultiPoint {
    var coordinateArray: [CLLocationCoordinate2D] {
        var result = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}
