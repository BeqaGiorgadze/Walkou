import Foundation
import MapKit

/// Loads the heavy system parts a workout needs (map engine, speech voice, chimes, haptics)
/// shortly after launch, while the user is still on Home. Without this, the first workout
/// paid for all of it at once and the countdown froze on "3" the first time.
@MainActor
enum AppWarmUp {
    private static var started = false
    /// Keeps one tiny map alive so MapKit's renderer and caches stay loaded.
    private static var mapView: MKMapView?

    static func run() async {
        guard !started else { return }
        started = true
        // Let the first screen finish appearing before doing anything.
        try? await Task.sleep(for: .seconds(1))

        // Speech engine + voice: slow and safe to do off the main thread.
        await Task.detached(priority: .utility) {
            _ = VoiceCoach.englishVoice
            _ = VoiceCoach.shared
        }.value

        // Map engine (must be created on the main thread).
        mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 4, height: 4))

        await Task.yield()
        Haptics.prepare()
        SoundEffects.preload()
    }
}
