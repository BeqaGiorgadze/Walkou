import XCTest
import CoreLocation
@testable import Walkou

final class SimulatedWalkerTests: XCTestCase {
    private let start = CLLocationCoordinate2D(latitude: 41.7151, longitude: 44.8271)

    func testFollowsRouteToTheEnd() {
        let coordinates = stride(from: 0.0, through: 600, by: 50).map { Geo.destination(from: start, bearing: 45, meters: $0) }
        let route = PlannedRoute(name: "Test", kind: .oneWay, coordinates: coordinates, distance: 600, instructions: [])
        var walker = SimulatedWalker(start: start, settings: .init(speedMultiplier: 10, noisyGPS: false))
        var fix = walker.advance(seconds: 1, route: route, gems: [])
        XCTAssertLessThan(fix.speed, 7, "Reported speed must stay at walking pace so gems count")
        for _ in 0..<60 { fix = walker.advance(seconds: 1, route: route, gems: []) }
        XCTAssertLessThan(Geo.distance(fix.coordinate, coordinates.last!), 1)
    }

    func testFreeWalkHeadsToNearestGem() {
        let gemSpot = Geo.destination(from: start, bearing: 120, meters: 200)
        let gems = [Gem(id: 1, kind: .common, coordinate: gemSpot, distanceIntoRoute: nil)]
        var walker = SimulatedWalker(start: start, settings: .init(speedMultiplier: 10, noisyGPS: false))
        var fix = walker.advance(seconds: 1, route: nil, gems: gems)
        for _ in 0..<20 { fix = walker.advance(seconds: 1, route: nil, gems: gems) }
        XCTAssertLessThan(Geo.distance(fix.coordinate, gemSpot), 1)
    }

    func testStandsStillWithZeroTime() {
        var walker = SimulatedWalker(start: start, settings: .init(speedMultiplier: 20, noisyGPS: false))
        let fix = walker.advance(seconds: 0, route: nil, gems: [])
        XCTAssertLessThan(Geo.distance(fix.coordinate, start), 0.01)
    }
}
