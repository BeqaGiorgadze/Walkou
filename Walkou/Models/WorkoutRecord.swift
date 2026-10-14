import Foundation
import SwiftData
import CoreLocation

/// A finished workout, stored on the device with SwiftData.
@Model
final class WorkoutRecord {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date
    var activityRaw: String
    var modeRaw: String
    var goalSteps: Int
    var steps: Int
    var distanceMeters: Double
    /// Active (not paused) time in seconds.
    var duration: TimeInterval
    var calories: Double
    var elevationGain: Double
    var routeName: String?
    @Attribute(.externalStorage) var trackData: Data?
    var savedToHealth: Bool
    // Gem Trail (defaults keep older saved workouts readable)
    var gemPoints: Int = 0
    var gemsAvailable: Int = 0
    var bonusSteps: Int = 0
    var gemTallyData: Data? = nil

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        activity: ActivityType,
        mode: WorkoutMode,
        goalSteps: Int,
        steps: Int,
        distanceMeters: Double,
        duration: TimeInterval,
        calories: Double,
        elevationGain: Double,
        routeName: String?,
        track: [CLLocationCoordinate2D],
        savedToHealth: Bool = false,
        gemTally: GemTally = GemTally(),
        gemsAvailable: Int = 0,
        bonusSteps: Int = 0
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.activityRaw = activity.rawValue
        self.modeRaw = mode.rawValue
        self.goalSteps = goalSteps
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.calories = calories
        self.elevationGain = elevationGain
        self.routeName = routeName
        self.trackData = CoordinateCoding.encode(track)
        self.savedToHealth = savedToHealth
        self.gemPoints = gemTally.points
        self.gemsAvailable = gemsAvailable
        self.bonusSteps = bonusSteps
        self.gemTallyData = gemTally.encoded()
    }

    var activity: ActivityType { ActivityType(rawValue: activityRaw) ?? .walk }
    var mode: WorkoutMode { WorkoutMode(rawValue: modeRaw) ?? .free }
    var goalReached: Bool { steps >= goalSteps }
    var track: [CLLocationCoordinate2D] { CoordinateCoding.decode(trackData) }
    var gemTally: GemTally { GemTally.decode(gemTallyData) }

    var title: String {
        let hour = Calendar.current.component(.hour, from: startDate)
        let partOfDay: String
        switch hour {
        case 5..<12: partOfDay = "Morning"
        case 12..<17: partOfDay = "Afternoon"
        case 17..<22: partOfDay = "Evening"
        default: partOfDay = "Night"
        }
        return "\(partOfDay) \(activity.title)"
    }
}

/// Compact storage for coordinate arrays.
enum CoordinateCoding {
    private struct Point: Codable {
        let lat: Double
        let lon: Double
    }

    static func encode(_ coordinates: [CLLocationCoordinate2D]) -> Data? {
        guard !coordinates.isEmpty else { return nil }
        return try? JSONEncoder().encode(coordinates.map { Point(lat: $0.latitude, lon: $0.longitude) })
    }

    static func decode(_ data: Data?) -> [CLLocationCoordinate2D] {
        guard let data, let points = try? JSONDecoder().decode([Point].self, from: data) else { return [] }
        return points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }
}
