import Foundation
import AVFoundation

/// Owns the shared audio session. Activating and deactivating it can block for hundreds of
/// milliseconds (longer while music is playing), so all of it happens on a background queue.
/// Callers "hold" the session while they play and release it after; it is deactivated
/// (letting music return to full volume) only once nobody holds it for a moment.
final class AudioSessionController: @unchecked Sendable {
    static let shared = AudioSessionController()

    private let queue = DispatchQueue(label: "app.walkou.audio-session", qos: .userInitiated)
    private var isConfigured = false
    private var isActive = false
    private var holds = 0
    private var pendingDeactivation: DispatchWorkItem?

    func hold() {
        queue.async { [self] in
            holds += 1
            pendingDeactivation?.cancel()
            pendingDeactivation = nil
            let session = AVAudioSession.sharedInstance()
            if !isConfigured {
                try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
                isConfigured = true
            }
            if !isActive {
                isActive = (try? session.setActive(true)) != nil
            }
        }
    }

    func release(after delay: TimeInterval = 0) {
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            holds = max(0, holds - 1)
            guard holds == 0, isActive else { return }
            pendingDeactivation?.cancel()
            let work = DispatchWorkItem { [self] in
                guard holds == 0, isActive else { return }
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                isActive = false
            }
            pendingDeactivation = work
            queue.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
    }
}
