import XCTest
import CoreLocation
@testable import Walkou

final class RouteTrackerTests: XCTestCase {
    /// A straight 1 km route heading north with turns at 300 m and the finish at 1 km.
    private func straightRoute() -> (tracker: RouteTracker, start: CLLocationCoordinate2D) {
        let start = CLLocationCoordinate2D(latitude: 41.7151, longitude: 44.8271)
        let coordinates = stride(from: 0.0, through: 1000.0, by: 100.0).map {
            Geo.destination(from: start, bearing: 0, meters: $0)
        }
        let instructions = [
            NavigationInstruction(id: 0, text: "Turn right onto Main Street", distanceIntoRoute: 300),
            NavigationInstruction(id: 1, text: "You've reached the finish", distanceIntoRoute: 1000),
        ]
        return (RouteTracker(coordinates: coordinates, instructions: instructions), start)
    }

    func testProgressFollowsTheUser() {
        var (tracker, start) = straightRoute()
        let snapshot = tracker.update(with: Geo.destination(from: start, bearing: 0, meters: 120))
        XCTAssertEqual(snapshot.progress, 120, accuracy: 2)
        XCTAssertEqual(snapshot.remaining, 880, accuracy: 3)
        XCTAssertFalse(snapshot.isOffRoute)
        XCTAssertEqual(snapshot.nextInstruction?.id, 0)
        XCTAssertEqual(snapshot.distanceToNextInstruction ?? 0, 180, accuracy: 3)
    }

    func testOffRouteNeedsSeveralFixes() {
        var (tracker, start) = straightRoute()
        let away = Geo.destination(from: Geo.destination(from: start, bearing: 0, meters: 100), bearing: 90, meters: 80)
        XCTAssertFalse(tracker.update(with: away).isOffRoute)
        XCTAssertFalse(tracker.update(with: away).isOffRoute)
        XCTAssertTrue(tracker.update(with: away).isOffRoute)

        let back = Geo.destination(from: start, bearing: 0, meters: 110)
        XCTAssertFalse(tracker.update(with: back).isOffRoute)
    }

    func testCompletesNearTheEnd() {
        var (tracker, start) = straightRoute()
        // Walk the route in 50 m steps so the matching window keeps up.
        var snapshot = tracker.update(with: start)
        for meters in stride(from: 50.0, through: 990.0, by: 50.0) {
            snapshot = tracker.update(with: Geo.destination(from: start, bearing: 0, meters: meters))
        }
        XCTAssertTrue(snapshot.isComplete)
        XCTAssertEqual(snapshot.nextInstruction?.id, 1)
    }

    func testLoopDoesNotJumpToTheEndAtTheStart() {
        // Square loop: start → north → east → south → back to start.
        let start = CLLocationCoordinate2D(latitude: 41.7151, longitude: 44.8271)
        let north = Geo.destination(from: start, bearing: 0, meters: 400)
        let northEast = Geo.destination(from: north, bearing: 90, meters: 400)
        let east = Geo.destination(from: start, bearing: 90, meters: 400)
        var tracker = RouteTracker(coordinates: [start, north, northEast, east, start], instructions: [])

        let snapshot = tracker.update(with: Geo.destination(from: start, bearing: 0, meters: 5))
        XCTAssertLessThan(snapshot.progress, 50)
        XCTAssertFalse(snapshot.isComplete)
    }

    func testSplitCoversTheWholeRoute() {
        var (tracker, start) = straightRoute()
        _ = tracker.update(with: Geo.destination(from: start, bearing: 0, meters: 150))
        let parts = tracker.split()
        XCTAssertEqual(Geo.length(parts.walked), 150, accuracy: 3)
        XCTAssertEqual(Geo.length(parts.remaining), 850, accuracy: 3)
    }
}

final class GeoAndFormatTests: XCTestCase {
    func testDestinationRoundTrip() {
        let origin = CLLocationCoordinate2D(latitude: 51.5007, longitude: -0.1246)
        let point = Geo.destination(from: origin, bearing: 135, meters: 2500)
        XCTAssertEqual(Geo.distance(origin, point), 2500, accuracy: 5)
    }

    func testStepsToDistance() {
        XCTAssertEqual(ActivityType.walk.distance(forSteps: 6000), 4500, accuracy: 0.001)
        XCTAssertEqual(ActivityType.run.distance(forSteps: 6000), 6000, accuracy: 0.001)
        XCTAssertEqual(ActivityType.walk.steps(forDistance: 4500), 6000)
    }

    func testFormatting() {
        XCTAssertEqual(Format.duration(2698), "44:58")
        XCTAssertEqual(Format.duration(3898), "1:04:58")
        XCTAssertEqual(Format.distanceValue(4910, unit: .kilometers), "4.91")
        XCTAssertEqual(Format.pace(distance: 1000, duration: 549, unit: .kilometers), "9'09\"")
        XCTAssertEqual(Format.shortDistance(124, unit: .kilometers), "120 m")
    }

    func testCompassNames() {
        XCTAssertEqual(Geo.compassName(forBearing: 0), "North")
        XCTAssertEqual(Geo.compassName(forBearing: 359), "North")
        XCTAssertEqual(Geo.compassName(forBearing: 90), "East")
        XCTAssertEqual(Geo.compassName(forBearing: 225), "Southwest")
    }
}
