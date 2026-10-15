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
    // Developer (debug builds only)
    static let simulateWalk = "debug.simulateWalk"
    static let simulateSpeed = "debug.simulateSpeed"
    static let simulateNoisyGPS = "debug.simulateNoisyGPS"
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
            offRouteAlertsEnabled: defaults.object(forKey: SettingsKey.offRouteAlerts) as? Bool ?? true,
            simulation: simulationSettings(defaults)
        )
        activeSession = session
    }

    private func simulationSettings(_ defaults: UserDefaults) -> SimulatedWalker.Settings? {
        #if DEBUG
        guard defaults.bool(forKey: SettingsKey.simulateWalk) else { return nil }
        let speed = defaults.double(forKey: SettingsKey.simulateSpeed)
        return SimulatedWalker.Settings(
            speedMultiplier: speed > 0 ? speed : 5,
            noisyGPS: defaults.bool(forKey: SettingsKey.simulateNoisyGPS)
        )
        #else
        return nil
        #endif
    }
}
