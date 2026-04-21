import AVFoundation
import Foundation

enum MacraAudioSound: String {
    case noraGreeting = "nora-greeting"

    var fileExtension: String {
        "mp3"
    }
}

final class MacraAudioService: NSObject {
    static let sharedInstance = MacraAudioService()
    private var audioPlayer: AVAudioPlayer?

    private override init() {
        super.init()
        Self.configurePlaybackSessionForAppSounds()
    }

    static func configurePlaybackSessionForAppSounds() {
        #if !os(visionOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("🔇 [MacraAudioService] Failed to configure audio session: \(error)")
        }
        #endif
    }

    func playSound(_ sound: MacraAudioSound, volume: Float = 0.45) {
        guard let soundURL = Bundle.main.url(forResource: sound.rawValue, withExtension: sound.fileExtension) else {
            print("🔇 [MacraAudioService] Sound file not found in bundle: \(sound.rawValue).\(sound.fileExtension)")
            return
        }

        do {
            Self.configurePlaybackSessionForAppSounds()
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.delegate = self
            audioPlayer?.volume = volume
            audioPlayer?.prepareToPlay()
            let started = audioPlayer?.play() ?? false
            print("🔊 [MacraAudioService] playSound(\(sound.rawValue)) vol=\(volume) → started=\(started)")
        } catch {
            print("🔇 [MacraAudioService] Failed to create player for \(sound.rawValue): \(error.localizedDescription)")
        }
    }
}

extension MacraAudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioPlayer = nil
    }
}
