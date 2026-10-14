import Foundation
import CoreLocation

/// Builds walking routes of a target length.
///
/// Directions services only do A→B (via waypoints), so routes are shaped by picking waypoints:
/// - Loop: a triangle start → A → B → start, sized so the walked distance matches the goal.
/// - One way: a single destination in some direction.
/// Each candidate is measured and re-scaled once if it misses the target.
struct RoutePlanner {
    enum PlannerError: LocalizedError {
        case noRoutesFound(String?)

        var errorDescription: String? {
            switch self {
            case .noRoutesFound(let detail):
                var message = "We couldn't find walkable routes around you. Try a different goal or move closer to streets or paths."
                #if DEBUG
                if let detail { message += "\n\n(\(detail))" }
                #endif
                return message
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
        var errors: [Error] = []
        await withTaskGroup(of: Result<PlannedRoute, Error>?.self) { group in
            for bearing in bearings {
                group.addTask {
                    do {
                        switch plan.mode {
                        case .loop:
                            return .success(try await loopRoute(from: origin, bearing: bearing, target: target))
                        case .oneWay:
                            return .success(try await oneWayRoute(from: origin, bearing: bearing, target: target))
                        case .free:
                            return nil
                        }
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let route): routes.append(route)
                case .failure(let error): errors.append(error)
                case nil: break
                }
            }
        }

        if routes.isEmpty {
            // Prefer the most actionable error.
            let directionsErrors = errors.compactMap { $0 as? DirectionsError }
            let throttled = directionsErrors.first { if case .throttled = $0 { return true } else { return false } }
            let network = directionsErrors.first { if case .network = $0 { return true } else { return false } }
            if let error = throttled ?? network {
                throw error
            }
            throw PlannerError.noRoutesFound(errors.first.map { ($0 as? LocalizedError)?.errorDescription ?? $0.localizedDescription })
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
        let legs = try await WalkingDirections.legs(through: [origin, destination])
        return combine(legs: legs, name: name, kind: .oneWay, finishText: "You've arrived")
    }

    // MARK: - Shapes

    private func loopRoute(from origin: CLLocationCoordinate2D, bearing: Double, target: Double) async throws -> PlannedRoute {
        // Equilateral triangle with the start as one corner.
        var side = target / (3 * detourFactor)
        var best: (legs: [RouteLeg], distance: Double)?

        for _ in 0..<2 {
            let a = Geo.destination(from: origin, bearing: bearing - 30, meters: side)
            let b = Geo.destination(from: origin, bearing: bearing + 30, meters: side)
            let legs = try await WalkingDirections.legs(through: [origin, a, b, origin])
            let distance = legs.reduce(0) { $0 + $1.distance }
            if best == nil || abs(distance - target) < abs(best!.distance - target) {
                best = (legs, distance)
            }
            if abs(distance - target) / target <= tolerance || distance <= 0 { break }
            side *= target / distance
        }

        guard let best else { throw PlannerError.noRoutesFound(nil) }
        let name = "\(Geo.compassName(forBearing: bearing)) loop" + viaName(best.legs)
        return combine(legs: best.legs, name: name, kind: .loop, finishText: "Loop complete. You're back at the start")
    }

    private func oneWayRoute(from origin: CLLocationCoordinate2D, bearing: Double, target: Double) async throws -> PlannedRoute {
        var straight = target / detourFactor
        var best: (legs: [RouteLeg], distance: Double)?

        for _ in 0..<2 {
            let destination = Geo.destination(from: origin, bearing: bearing, meters: straight)
            let legs = try await WalkingDirections.legs(through: [origin, destination])
            let distance = legs.reduce(0) { $0 + $1.distance }
            if best == nil || abs(distance - target) < abs(best!.distance - target) {
                best = (legs, distance)
            }
            if abs(distance - target) / target <= tolerance || distance <= 0 { break }
            straight *= target / distance
        }

        guard let best else { throw PlannerError.noRoutesFound(nil) }
        let name = "\(Geo.compassName(forBearing: bearing))bound" + viaName(best.legs)
        return combine(legs: best.legs, name: name, kind: .oneWay, finishText: "You've reached the finish")
    }

    private func viaName(_ legs: [RouteLeg]) -> String {
        guard let longest = legs.max(by: { $0.distance < $1.distance }), !longest.name.isEmpty else { return "" }
        return " via \(longest.name)"
    }

    /// Stitches legs into one polyline with turn instructions placed along it.
    private func combine(legs: [RouteLeg], name: String, kind: WorkoutMode, finishText: String) -> PlannedRoute {
        var coordinates: [CLLocationCoordinate2D] = []
        var instructions: [NavigationInstruction] = []
        var offset = 0.0

        for (legIndex, leg) in legs.enumerated() {
            var legCoordinates = leg.coordinates
            if !coordinates.isEmpty, !legCoordinates.isEmpty {
                legCoordinates.removeFirst() // shared with the previous leg's last point
            }
            coordinates.append(contentsOf: legCoordinates)

            // The service's step distances and our polyline geometry differ slightly; scale to match.
            let geometryLength = Geo.length(leg.coordinates)
            let scale = leg.distance > 0 ? geometryLength / leg.distance : 1
            let isLastLeg = legIndex == legs.count - 1
            var stepStart = 0.0

            for (stepIndex, step) in leg.steps.enumerated() {
                defer { stepStart += step.distance * scale }
                let isLastStep = stepIndex == leg.steps.count - 1
                if isLastStep && !isLastLeg { continue } // "Arrive at …" between our own waypoints
                if stepIndex == 0 && legIndex > 0 { continue } // "Head north" after our own waypoints
                var text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
