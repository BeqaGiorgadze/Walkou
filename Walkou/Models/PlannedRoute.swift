import Foundation
import CoreLocation
import SwiftUI

/// A turn instruction placed at a distance along a route.
struct NavigationInstruction: Identifiable, Hashable {
    let id: Int
    let text: String
    /// Meters from the route start where this maneuver happens.
    let distanceIntoRoute: Double

    var symbol: String { NavigationInstruction.symbol(for: text) }

    static func symbol(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("arrive") || lower.contains("destination") || lower.contains("finish") {
            return "flag.checkered"
        }
        if lower.contains("slight left") || lower.contains("bear left") || lower.contains("keep left") {
            return "arrow.up.left"
        }
        if lower.contains("slight right") || lower.contains("bear right") || lower.contains("keep right") {
            return "arrow.up.right"
        }
        if lower.contains("u-turn") || lower.contains("turn around") {
            return "arrow.uturn.down"
        }
        if lower.contains("left") { return "arrow.turn.up.left" }
        if lower.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
}

/// A suggested (or guidance) route the user can follow. Immutable, so safe to pass between tasks.
struct PlannedRoute: Identifiable, @unchecked Sendable {
    let id = UUID()
    let name: String
    let kind: WorkoutMode
    let coordinates: [CLLocationCoordinate2D]
    let distance: CLLocationDistance
    let instructions: [NavigationInstruction]
    var colorIndex: Int = 0
    /// Gems placed on (and beside) this route.
    var gems: [Gem] = []
    /// Bonus gems need a street lookup; true once that has run.
    var bonusGemsPlaced = false

    var start: CLLocationCoordinate2D? { coordinates.first }
    var end: CLLocationCoordinate2D? { coordinates.last }

    var color: Color { Theme.routeColors[colorIndex % Theme.routeColors.count] }

    func gemCount(_ kind: GemKind) -> Int {
        gems.filter { $0.kind.haulKind == kind }.count
    }

    /// Points available if every gem is collected.
    var gemPoints: Int { gems.reduce(0) { $0 + $1.kind.points } }

    func estimatedSteps(for activity: ActivityType) -> Int {
        activity.steps(forDistance: distance)
    }
}
