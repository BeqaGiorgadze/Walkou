import Foundation
import AVFoundation

/// Spoken guidance. Ducks other audio (music, podcasts) while talking, also when the screen is locked.
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    /// One coach for the whole app. Creating the speech engine and loading a voice is slow the first
    /// time (it can block the screen for a second), so it's made once and warmed up at launch.
    static let shared = VoiceCoach()

    /// Loading the voice reads it from disk; `static let` makes this happen once, on whichever
    /// thread touches it first (the launch warm-up does it in the background).
    static let englishVoice = AVSpeechSynthesisVoice(language: "en-US")

    var isEnabled = true

    private let synthesizer = AVSpeechSynthesizer()
    /// One hold on the audio session for as long as anything is being spoken.
    private var holdingSession = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String, interrupt: Bool = false) {
        guard isEnabled, !text.isEmpty else { return }
        if interrupt, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        if !holdingSession {
            holdingSession = true
            AudioSessionController.shared.hold()
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.englishVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        releaseIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        releaseIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        releaseIfIdle()
    }

    private func releaseIfIdle() {
        DispatchQueue.main.async { [self] in
            guard holdingSession, !synthesizer.isSpeaking else { return }
            holdingSession = false
            AudioSessionController.shared.release()
        }
    }
}
