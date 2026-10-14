import Foundation
import AVFoundation

/// Short chimes for collecting gems and levelling up. Mixes with music instead of stopping it.
@MainActor
enum SoundEffects {
    enum Effect: String {
        case gemCommon = "gem_common"
        case gemBonus = "gem_bonus"
        case gemRare = "gem_rare"
        case gemLegendary = "gem_legendary"
        case levelUp = "level_up"

        static func forGem(_ kind: GemKind) -> Effect {
            switch kind {
            case .common: return .gemCommon
            case .bonus: return .gemBonus
            case .legendary: return .gemLegendary
            case .rare, .heart, .amber, .shard, .cushion: return .gemRare
            }
        }
    }

    private static var players: [Effect: AVAudioPlayer] = [:]

    static func play(_ effect: Effect) {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)

        if players[effect] == nil,
           let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = 0.8
            player.prepareToPlay()
            players[effect] = player
        }
        guard let player = players[effect] else { return }
        player.currentTime = 0
        player.play()
    }
}
