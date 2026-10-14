import Foundation
import CoreLocation

/// Small geodesy helpers. Distances are good to well under 1% at walking scales.
enum Geo {
    static let earthRadius: Double = 6_371_000

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude.radians
        let lat2 = b.latitude.radians
        let dLat = (b.latitude - a.latitude).radians
        let dLon = (b.longitude - a.longitude).radians
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }

    /// The point `meters` away from `origin` in direction `bearing` (degrees, 0 = north).
    static func destination(from origin: CLLocationCoordinate2D, bearing: Double, meters: Double) -> CLLocationCoordinate2D {
        let angular = meters / earthRadius
        let theta = bearing.radians
        let lat1 = origin.latitude.radians
        let lon1 = origin.longitude.radians
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2.degrees, longitude: lon2.degrees)
    }

    /// Cumulative distance at every vertex of a polyline (first element is 0).
    static func cumulativeDistances(_ coordinates: [CLLocationCoordinate2D]) -> [Double] {
        guard !coordinates.isEmpty else { return [] }
        var result = [0.0]
        result.reserveCapacity(coordinates.count)
        for i in 1..<coordinates.count {
            result.append(result[i - 1] + distance(coordinates[i - 1], coordinates[i]))
        }
        return result
    }

    static func length(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        cumulativeDistances(coordinates).last ?? 0
    }

    struct Projection {
        /// Distance in meters from the point to the segment.
        let distance: Double
        /// 0...1 position along the segment.
        let fraction: Double
    }

    /// Projects `point` onto the segment a→b using a local flat-earth approximation.
    static func project(_ point: CLLocationCoordinate2D, ontoSegment a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Projection {
        let metersPerDegreeLat = earthRadius * .pi / 180
        let metersPerDegreeLon = metersPerDegreeLat * cos(a.latitude.radians)
        let bx = (b.longitude - a.longitude) * metersPerDegreeLon
        let by = (b.latitude - a.latitude) * metersPerDegreeLat
        let px = (point.longitude - a.longitude) * metersPerDegreeLon
        let py = (point.latitude - a.latitude) * metersPerDegreeLat
        let lengthSquared = bx * bx + by * by
        var t = 0.0
        if lengthSquared > 0 {
            t = min(1, max(0, (px * bx + py * by) / lengthSquared))
        }
        let dx = px - t * bx
        let dy = py - t * by
        return Projection(distance: sqrt(dx * dx + dy * dy), fraction: t)
    }

    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, fraction t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    static func compassName(forBearing bearing: Double) -> String {
        let names = ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest"]
        let normalized = (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 45).rounded()) % names.count
        return names[index]
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
