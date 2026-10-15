import XCTest
import CoreLocation
@testable import Walkou

final class GemTests: XCTestCase {
    private func straightRoute(meters: Double) -> PlannedRoute {
        let start = CLLocationCoordinate2D(latitude: 41.7151, longitude: 44.8271)
        let coordinates = stride(from: 0.0, through: meters, by: 50).map { Geo.destination(from: start, bearing: 0, meters: $0) }
        return PlannedRoute(name: "Test", kind: .oneWay, coordinates: coordinates, distance: meters, instructions: [])
    }

    func testRouteGemsAreSpacedWithLegendaryAtFinish() {
        var generator = SeededGenerator(seed: 42)
        let route = straightRoute(meters: 4500)
        let gems = GemPlanner.routeGems(for: route, using: &generator)

        XCTAssertEqual(gems.last?.kind, .legendary)
        XCTAssertEqual(gems.last?.distanceIntoRoute ?? 0, 4500, accuracy: 5)
        XCTAssertEqual(gems.filter { $0.kind == .legendary }.count, 1)
        XCTAssertEqual(gems.filter { $0.kind.haulKind == .rare }.count, 2)
        XCTAssertEqual(gems.count, Int(4500 / GemPlanner.spacing) + 1)
        // Ordered along the route, nothing at the very start.
        let along = gems.compactMap(\.distanceIntoRoute)
        XCTAssertEqual(along, along.sorted())
        XCTAssertGreaterThan(along.first ?? 0, 200)
        XCTAssertEqual(Set(gems.map(\.id)).count, gems.count)
    }

    func testShortRouteOnlyGetsTheFinishGem() {
        var generator = SeededGenerator(seed: 1)
        let gems = GemPlanner.routeGems(for: straightRoute(meters: 250), using: &generator)
        XCTAssertEqual(gems.map(\.kind), [.legendary])
    }

    func testBonusCountGrowsWithDistance() {
        XCTAssertEqual(GemPlanner.bonusCount(forDistance: 1000), 0)
        XCTAssertEqual(GemPlanner.bonusCount(forDistance: 2000), 1)
        XCTAssertEqual(GemPlanner.bonusCount(forDistance: 4500), 2)
        XCTAssertEqual(GemPlanner.bonusCount(forDistance: 8000), 3)
    }

    func testLevels() {
        XCTAssertEqual(GemLevel.forPoints(0).title, "Walker")
        XCTAssertEqual(GemLevel.forPoints(49).number, 1)
        XCTAssertEqual(GemLevel.forPoints(50).title, "Explorer")
        XCTAssertEqual(GemLevel.forPoints(112).title, "Explorer")
        XCTAssertEqual(GemLevel.forPoints(150).title, "Pathfinder")
        XCTAssertEqual(GemLevel.forPoints(400).title, "Trailblazer")
        XCTAssertEqual(GemLevel.forPoints(1000).title, "Legend")
        XCTAssertEqual(GemLevel.forPoints(2500).title, "Legend II")
        XCTAssertEqual(GemLevel.forPoints(2500).number, 6)
        XCTAssertEqual(GemLevel.forPoints(100).progress(points: 100), 0.5, accuracy: 0.001)
        XCTAssertEqual(GemLevel.forPoints(150).nextTitle, "Trailblazer")
    }

    func testTallyPoints() {
        var tally = GemTally()
        tally[.common] = 11
        tally[.rare] = 2
        tally[.legendary] = 1
        tally[.bonus] = 2
        XCTAssertEqual(tally.points, 11 + 10 + 10 + 6)
        XCTAssertEqual(GemTally.decode(tally.encoded()), tally)
    }

    func testBearing() {
        let a = CLLocationCoordinate2D(latitude: 41.7, longitude: 44.8)
        XCTAssertEqual(Geo.bearing(from: a, to: Geo.destination(from: a, bearing: 90, meters: 500)), 90, accuracy: 0.5)
        XCTAssertEqual(Geo.bearing(from: a, to: Geo.destination(from: a, bearing: 225, meters: 500)), 225, accuracy: 0.5)
    }

    func testSimplifyKeepsCornersAndDropsStraightPoints() {
        let a = CLLocationCoordinate2D(latitude: 41.7, longitude: 44.8)
        var line = stride(from: 0.0, through: 500, by: 5).map { Geo.destination(from: a, bearing: 0, meters: $0) }
        let corner = line.last!
        line += stride(from: 5.0, through: 300, by: 5).map { Geo.destination(from: corner, bearing: 90, meters: $0) }
        let simple = Geo.simplify(line)
        XCTAssertEqual(simple.count, 3)
        XCTAssertEqual(Geo.length(simple), Geo.length(line), accuracy: 1)
    }
}
