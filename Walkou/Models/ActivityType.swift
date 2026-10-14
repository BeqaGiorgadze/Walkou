import Foundation

/// Walking or running. Each has its own fixed-average stride, pace and energy estimate.
enum ActivityType: String, CaseIterable, Identifiable, Codable {
    case walk
    case run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "Walk"
        case .run: return "Run"
        }
    }

    var verb: String {
        switch self {
        case .walk: return "Walking"
        case .run: return "Running"
        }
    }

    var symbol: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        }
    }

    /// Fixed average stride length in meters.
    var strideLength: Double {
        switch self {
        case .walk: return 0.75
        case .run: return 1.0
        }
    }

    /// Typical moving speed in meters per second, used for time estimates.
    var typicalSpeed: Double {
        switch self {
        case .walk: return 5.0 / 3.6   // 5 km/h
        case .run: return 9.5 / 3.6    // 9.5 km/h
        }
    }

    /// Rough active energy per kilometer for an average 70 kg adult.
    var kilocaloriesPerKilometer: Double {
        switch self {
        case .walk: return 40
        case .run: return 70
        }
    }

    /// How close (in meters) the next turn must be before it is announced.
    var announceDistance: Double {
        switch self {
        case .walk: return 30
        case .run: return 55
        }
    }

    func distance(forSteps steps: Int) -> Double {
        Double(steps) * strideLength
    }

    func steps(forDistance meters: Double) -> Int {
        Int((meters / strideLength).rounded())
    }

    func estimatedDuration(forDistance meters: Double) -> TimeInterval {
        meters / typicalSpeed
    }
}

/// How the user wants to reach their goal.
enum WorkoutMode: String, CaseIterable, Identifiable, Codable {
    case loop
    case oneWay
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loop: return "Loop"
        case .oneWay: return "One way"
        case .free: return "Free"
        }
    }

    var subtitle: String {
        switch self {
        case .loop: return "Finish where you start"
        case .oneWay: return "End somewhere new"
        case .free: return "No route, just steps"
        }
    }

    var symbol: String {
        switch self {
        case .loop: return "arrow.triangle.capsulepath"
        case .oneWay: return "arrow.up.right"
        case .free: return "sparkles"
        }
    }

    var needsRoute: Bool { self != .free }
}

/// Everything chosen on the planning screen.
struct WorkoutPlan: Hashable {
    var activity: ActivityType
    var goalSteps: Int
    var mode: WorkoutMode

    var targetDistance: Double { activity.distance(forSteps: goalSteps) }
    var estimatedDuration: TimeInterval { activity.estimatedDuration(forDistance: targetDistance) }
}
