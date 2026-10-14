import Foundation
import Observation

/// UserDefaults keys shared by @AppStorage across screens.
enum SettingsKey {
    static let hasOnboarded = "hasOnboarded"
    static let distanceUnit = "distanceUnit"
    static let voiceGuidance = "voiceGuidance"
    static let offRouteAlerts = "offRouteAlerts"
    static let saveToHealth = "saveToHealth"
    static let goalSteps = "goalSteps"
    static let activity = "activity"
    static let mode = "mode"
}

enum AppTab: Hashable {
    case home
    case start
    case activity
    case settings
}

/// App-wide state: the shared location service, the selected tab and the workout in progress.
@MainActor
@Observable
final class AppModel {
    let location = LocationService()
    var selectedTab: AppTab = .home
    var activeSession: WorkoutSession?

    func startWorkout(plan: WorkoutPlan, route: PlannedRoute?) {
        let defaults = UserDefaults.standard
        let unit = DistanceUnit(rawValue: defaults.string(forKey: SettingsKey.distanceUnit) ?? "") ?? .kilometers
        let session = WorkoutSession(
            plan: plan,
            route: route,
            location: location,
            unit: unit,
            voiceEnabled: defaults.object(forKey: SettingsKey.voiceGuidance) as? Bool ?? true,
            offRouteAlertsEnabled: defaults.object(forKey: SettingsKey.offRouteAlerts) as? Bool ?? true
        )
        activeSession = session
    }
}
