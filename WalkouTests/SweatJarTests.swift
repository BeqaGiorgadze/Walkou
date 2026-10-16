import XCTest
@testable import Walkou

final class SweatJarTests: XCTestCase {
    func testJarsSealAtEachGoalAndCapAtThree() {
        XCTAssertEqual(SweatJar.sealed(steps: 5999, goal: 6000), 0)
        XCTAssertEqual(SweatJar.sealed(steps: 6000, goal: 6000), 1)
        XCTAssertEqual(SweatJar.sealed(steps: 12_500, goal: 6000), 2)
        XCTAssertEqual(SweatJar.sealed(steps: 50_000, goal: 6000), SweatJar.maxPerWorkout)
        XCTAssertEqual(SweatJar.sealed(steps: 100, goal: 0), 0)
    }

    func testCurrentJarFillStartsOverAfterASeal() {
        XCTAssertEqual(SweatJar.currentJarFill(steps: 3000, goal: 6000), 0.5, accuracy: 0.001)
        XCTAssertEqual(SweatJar.currentJarFill(steps: 7500, goal: 6000), 0.25, accuracy: 0.001)
        XCTAssertEqual(SweatJar.currentJarFill(steps: 30_000, goal: 6000), 1, accuracy: 0.001)
    }

    func testMascotStages() {
        XCTAssertEqual(MascotStage.forJars(0).title, "Couch Bean")
        XCTAssertEqual(MascotStage.forJars(3).title, "Warming Up")
        XCTAssertEqual(MascotStage.forJars(29).title, "Getting Fit")
        XCTAssertEqual(MascotStage.forJars(250).title, "Legend")
        XCTAssertNil(MascotStage.forJars(250).next)
        XCTAssertEqual(MascotStage.forJars(5).progress(jars: 5), 2.0 / 7.0, accuracy: 0.001)
    }

    func testSealedJarCrystalIsWorthTenPoints() {
        var tally = GemTally()
        tally[.crystal] += 2
        XCTAssertEqual(tally.points, 20)
    }
}
