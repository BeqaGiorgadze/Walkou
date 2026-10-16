import Foundation
import AVFoundation

/// Short chimes for collecting gems and levelling up. Music is ducked briefly, never stopped.
@MainActor
enum SoundEffects {
    enum Effect: String {
        case gemCommon = "gem_common"
        case gemBonus = "gem_bonus"
        case gemRare = "gem_rare"
        case gemLegendary = "gem_legendary"
        case levelUp = "level_up"
        case jarSeal = "jar_seal"

        static func forGem(_ kind: GemKind) -> Effect {
            switch kind {
            case .common: return .gemCommon
            case .bonus: return .gemBonus
            case .legendary: return .gemLegendary
            case .crystal: return .jarSeal
            case .rare, .heart, .amber, .shard, .cushion: return .gemRare
            }
        }
    }

    private static var players: [Effect: AVAudioPlayer] = [:]

    /// Loads all chimes so the first gem doesn't stall while a file is decoded.
    static func preload() {
        for effect in [Effect.gemCommon, .gemBonus, .gemRare, .gemLegendary, .levelUp, .jarSeal] { _ = player(for: effect) }
    }

    private static func player(for effect: Effect) -> AVAudioPlayer? {
        if let player = players[effect] { return player }
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = 0.8
        player.prepareToPlay()
        players[effect] = player
        return player
    }

    static func play(_ effect: Effect) {
        guard let player = player(for: effect) else { return }
        AudioSessionController.shared.hold()
        player.currentTime = 0
        player.play()
        AudioSessionController.shared.release(after: player.duration + 0.2)
    }
}
