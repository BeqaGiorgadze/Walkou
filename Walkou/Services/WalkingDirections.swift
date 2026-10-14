import Foundation
import MapKit

/// One stretch of a route between two consecutive waypoints.
struct RouteLeg: @unchecked Sendable {
    struct Step {
        let text: String
        /// Meters from this maneuver to the next one.
        let distance: Double
    }

    let coordinates: [CLLocationCoordinate2D]
    let distance: Double
    /// Main street name, used to name suggestions ("via Rustaveli Avenue").
    let name: String
    let steps: [Step]
}

enum DirectionsError: LocalizedError {
    case throttled
    case noRoute(String)
    case network

    var errorDescription: String? {
        switch self {
        case .throttled: return "The map service needs a short break. Please try again in a minute."
        case .noRoute(let detail): return detail
        case .network: return "Couldn't reach the route service. Check your internet connection and try again."
        }
    }
}

/// Walking directions through a list of waypoints.
///
/// Uses Apple Maps first. Apple doesn't offer walking directions in every country (for example
/// Georgia), so when it can't route we fall back to OpenStreetMap (FOSSGIS OSRM foot profile)
/// and remember that choice for the rest of the session.
enum WalkingDirections {
    private static let memory = ProviderMemory()

    static func legs(through waypoints: [CLLocationCoordinate2D]) async throws -> [RouteLeg] {
        precondition(waypoints.count >= 2, "Need at least a start and an end")

        var appleError: Error?
        let skipApple = await memory.prefersOpenStreetMap
        if !skipApple {
            do {
                return try await appleLegs(through: waypoints)
            } catch let error as MKError where error.code == .loadingThrottled {
                throw DirectionsError.throttled
            } catch {
                appleError = error
            }
        }

        do {
            let legs = try await openStreetMapLegs(through: waypoints)
            if appleError != nil { await memory.useOpenStreetMap() }
            return legs
        } catch let error as DirectionsError {
            throw error
        } catch is URLError {
            throw DirectionsError.network
        } catch {
            throw DirectionsError.noRoute(appleError?.localizedDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Apple Maps

    private static func appleLegs(through waypoints: [CLLocationCoordinate2D]) async throws -> [RouteLeg] {
        var legs: [RouteLeg] = []
        for (from, to) in zip(waypoints, waypoints.dropFirst()) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
            request.transportType = .walking
            request.requestsAlternateRoutes = false
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw DirectionsError.noRoute("Apple Maps returned no walking route.")
            }
            legs.append(RouteLeg(
                coordinates: route.polyline.coordinateArray,
                distance: route.distance,
                name: route.name,
                steps: route.steps.map { RouteLeg.Step(text: $0.instructions, distance: $0.distance) }
            ))
        }
        return legs
    }

    // MARK: - OpenStreetMap (OSRM)

    private static func openStreetMapLegs(through waypoints: [CLLocationCoordinate2D]) async throws -> [RouteLeg] {
        let path = waypoints
            .map { String(format: "%.6f,%.6f", $0.longitude, $0.latitude) }
            .joined(separator: ";")
        guard let url = URL(string: "https://routing.openstreetmap.de/routed-foot/route/v1/driving/\(path)?overview=false&steps=true&geometries=geojson&alternatives=false&continue_straight=false") else {
            throw DirectionsError.noRoute("Invalid route request.")
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Walkou/1.0 (iOS step-goal walking app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            throw DirectionsError.throttled
        }
        let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
        guard decoded.code == "Ok", let route = decoded.routes?.first else {
            throw DirectionsError.noRoute(decoded.message ?? "No walking route found (\(decoded.code)).")
        }

        return route.legs.map { leg in
            var coordinates: [CLLocationCoordinate2D] = []
            for step in leg.steps {
                for pair in step.geometry.coordinates where pair.count >= 2 {
                    let point = CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                    if let last = coordinates.last, last.latitude == point.latitude, last.longitude == point.longitude {
                        continue
                    }
                    coordinates.append(point)
                }
            }
            let mainStreet = leg.steps.max { $0.distance < $1.distance }?.name ?? ""
            return RouteLeg(
                coordinates: coordinates,
                distance: leg.distance,
                name: mainStreet,
                steps: leg.steps.map { RouteLeg.Step(text: instruction(for: $0), distance: $0.distance) }
            )
        }
    }

    /// Turns an OSRM maneuver into a short English instruction.
    private static func instruction(for step: OSRMResponse.Step) -> String {
        let name = (step.name ?? "").trimmingCharacters(in: .whitespaces)
        let onto = name.isEmpty ? "" : " onto \(name)"
        let maneuver = step.maneuver
        let modifier = maneuver.modifier ?? "straight"

        switch maneuver.type {
        case "depart":
            let heading = Geo.compassName(forBearing: maneuver.bearingAfter ?? 0).lowercased()
            return name.isEmpty ? "Head \(heading)" : "Head \(heading) on \(name)"
        case "arrive":
            return "Arrive at your destination"
        case "roundabout", "rotary", "roundabout turn", "exit roundabout", "exit rotary":
            if let exit = maneuver.exit {
                return "At the roundabout, take the \(ordinal(exit)) exit\(onto)"
            }
            return "Go through the roundabout\(onto)"
        case "new name", "continue", "notification", "use lane", "merge":
            if modifier == "straight" || modifier.isEmpty {
                return name.isEmpty ? "" : "Continue onto \(name)"
            }
            return turnPhrase(modifier) + onto
        default: // turn, end of road, fork, on ramp, off ramp
            if modifier == "straight" {
                return name.isEmpty ? "Continue straight" : "Continue straight onto \(name)"
            }
            return turnPhrase(modifier) + onto
        }
    }

    private static func turnPhrase(_ modifier: String) -> String {
        switch modifier {
        case "uturn": return "Make a U-turn"
        case "sharp right": return "Turn sharp right"
        case "right": return "Turn right"
        case "slight right": return "Bear right"
        case "slight left": return "Bear left"
        case "left": return "Turn left"
        case "sharp left": return "Turn sharp left"
        default: return "Continue"
        }
    }

    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        case 4: return "fourth"
        case 5: return "fifth"
        default: return "\(n)th"
        }
    }
}

/// Remembers which provider works here so we don't ask Apple Maps again after it failed.
private actor ProviderMemory {
    private(set) var prefersOpenStreetMap = false

    func useOpenStreetMap() {
        prefersOpenStreetMap = true
    }
}

private struct OSRMResponse: Decodable {
    let code: String
    let message: String?
    let routes: [Route]?

    struct Route: Decodable {
        let distance: Double
        let legs: [Leg]
    }

    struct Leg: Decodable {
        let distance: Double
        let steps: [Step]
    }

    struct Step: Decodable {
        let distance: Double
        let name: String?
        let geometry: Geometry
        let maneuver: Maneuver
    }

    struct Geometry: Decodable {
        let coordinates: [[Double]]
    }

    struct Maneuver: Decodable {
        let type: String
        let modifier: String?
        let bearingAfter: Double?
        let exit: Int?

        enum CodingKeys: String, CodingKey {
            case type
            case modifier
            case bearingAfter = "bearing_after"
            case exit
        }
    }
}

extension MKMultiPoint {
    var coordinateArray: [CLLocationCoordinate2D] {
        var result = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}
