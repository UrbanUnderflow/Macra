import AVFoundation
import Combine
import FirebaseFirestore
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

    static func configurePlaybackSessionForNarration() {
        #if !os(visionOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("🔇 [MacraAudioService] Failed to configure narration audio session: \(error)")
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

@MainActor
final class MacraNoraVoiceService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = MacraNoraVoiceService()

    private struct NarrationAsset: Sendable {
        let downloadURL: String

        init?(dictionary: [String: Any]) {
            guard
                let downloadURL = dictionary["downloadURL"] as? String,
                !downloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }

            self.downloadURL = downloadURL
        }
    }

    private enum Constants {
        static let preferenceKey = "macra.noraOnboardingVoiceEnabled"
        static let configRefreshInterval: TimeInterval = 300
        static let configCollection = "app-config"
        static let configDocument = "ai-voice"
        static let narrationField = "macraOnboardingNarrations"
    }

    private var audioPlayer: AVAudioPlayer?
    private var cachedAssets: [String: NarrationAsset] = [:]
    private var lastConfigFetchAt: Date?
    private var audioDataCache: [String: Data] = [:]
    private var narrationRunID = UUID()
    private var narrationTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var meteringTimer: Timer?
    private var lastNarrationKey: String?
    private var lastLoggedFailureMessage: String?
    @Published private(set) var isEnabled: Bool
    @Published private(set) var activeNarrationKey: String?
    @Published private(set) var lastCompletedNarrationKey: String?
    @Published private(set) var isNarrating: Bool = false
    @Published private(set) var voiceLevel: Double = 0

    private override init() {
        if UserDefaults.standard.object(forKey: Constants.preferenceKey) == nil {
            UserDefaults.standard.set(true, forKey: Constants.preferenceKey)
        }
        self.isEnabled = UserDefaults.standard.bool(forKey: Constants.preferenceKey)
        super.init()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Constants.preferenceKey)
        if enabled {
            preloadOnboardingNarrations()
        } else {
            preloadTask?.cancel()
            preloadTask = nil
            stop(resetLastKey: false, markCompleted: true)
        }
    }

    func preloadOnboardingNarrations() {
        guard isEnabled else { return }
        guard preloadTask == nil else { return }
        preloadTask = Task { [weak self] in
            await self?.warmOnboardingNarrationCache()
            await MainActor.run {
                self?.preloadTask = nil
            }
        }
    }

    func narrateOnboarding(stepId: String, fallbackText: String, key: String, force: Bool = false) {
        guard isEnabled, !stepId.isEmpty else { return }
        guard force || lastNarrationKey != key else { return }

        lastNarrationKey = key
        activeNarrationKey = key
        if lastCompletedNarrationKey == key {
            lastCompletedNarrationKey = nil
        }
        narrationRunID = UUID()
        let runID = narrationRunID
        narrationTask?.cancel()
        stopPlayback()

        narrationTask = Task { [weak self] in
            guard let self else { return }

            do {
                guard let asset = await self.narrationAsset(for: stepId) else {
                    self.logNarrationFailureIfNeeded("No Macra onboarding narration asset configured for \(stepId).")
                    self.completeNarrationIfCurrent(key: key)
                    return
                }

                let data = try await self.audioData(for: asset)
                guard !Task.isCancelled, runID == self.narrationRunID else { return }
                self.playNarrationAudio(data, runID: runID, key: key)
                self.lastLoggedFailureMessage = nil
            } catch {
                guard !Task.isCancelled, runID == self.narrationRunID else { return }
                let spokenText = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                let textSuffix = spokenText.isEmpty ? "" : " Text: \(spokenText)"
                self.logNarrationFailureIfNeeded("\(error.localizedDescription)\(textSuffix)")
                self.completeNarrationIfCurrent(key: key)
            }
        }
    }

    func stop(resetLastKey: Bool = false, markCompleted: Bool = false) {
        let keyToComplete = activeNarrationKey
        narrationRunID = UUID()
        narrationTask?.cancel()
        narrationTask = nil
        stopPlayback()
        if markCompleted, let keyToComplete {
            completeNarration(key: keyToComplete)
        } else {
            activeNarrationKey = nil
            isNarrating = false
        }
        if resetLastKey {
            lastNarrationKey = nil
        }
    }

    private func narrationAsset(for stepId: String) async -> NarrationAsset? {
        let assets = await loadNarrationAssets()
        return assets[stepId]
    }

    private func warmOnboardingNarrationCache(force: Bool = false) async {
        let assets = await loadNarrationAssets(force: force)
        guard !Task.isCancelled else { return }
        let uncachedAssets = assets.values.filter { force || audioDataCache[$0.downloadURL] == nil }
        guard !uncachedAssets.isEmpty else { return }

        await withTaskGroup(of: (String, Data?, String?).self) { group in
            for asset in uncachedAssets {
                group.addTask {
                    do {
                        let data = try await Self.fetchAudioData(from: asset.downloadURL)
                        return (asset.downloadURL, data, nil)
                    } catch {
                        return (asset.downloadURL, nil, error.localizedDescription)
                    }
                }
            }

            for await (downloadURL, data, errorMessage) in group {
                if let data {
                    audioDataCache[downloadURL] = data
                } else if let errorMessage {
                    logNarrationFailureIfNeeded(errorMessage)
                }
            }
        }
    }

    private func loadNarrationAssets(force: Bool = false) async -> [String: NarrationAsset] {
        if !force,
           let lastConfigFetchAt,
           Date().timeIntervalSince(lastConfigFetchAt) < Constants.configRefreshInterval {
            return cachedAssets
        }

        do {
            let snapshot = try await Firestore.firestore()
                .collection(Constants.configCollection)
                .document(Constants.configDocument)
                .getDocument()

            let rawAssets = snapshot.data()?[Constants.narrationField] as? [String: Any] ?? [:]
            cachedAssets = rawAssets.reduce(into: [String: NarrationAsset]()) { result, pair in
                guard let dictionary = pair.value as? [String: Any],
                      let asset = NarrationAsset(dictionary: dictionary) else { return }
                result[pair.key] = asset
            }
            lastConfigFetchAt = Date()
            return cachedAssets
        } catch {
            logNarrationFailureIfNeeded(error.localizedDescription)
            lastConfigFetchAt = Date()
            return cachedAssets
        }
    }

    private func audioData(for asset: NarrationAsset) async throws -> Data {
        if let cached = audioDataCache[asset.downloadURL] {
            return cached
        }

        let data = try await Self.fetchAudioData(from: asset.downloadURL)
        audioDataCache[asset.downloadURL] = data
        return data
    }

    private nonisolated static func fetchAudioData(from downloadURL: String) async throws -> Data {
        guard let url = URL(string: downloadURL) else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "MacraNoraVoiceService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch Nora onboarding narration."]
            )
        }

        return data
    }

    private func playNarrationAudio(_ data: Data, runID: UUID, key: String) {
        guard runID == narrationRunID else { return }
        stopPlayback()
        activeNarrationKey = key

        do {
            MacraAudioService.configurePlaybackSessionForNarration()
            let player = try AVAudioPlayer(data: data)
            audioPlayer = player
            player.delegate = self
            player.isMeteringEnabled = true
            player.volume = 0.92
            player.prepareToPlay()
            if player.play() {
                isNarrating = true
                startMetering()
            } else {
                audioPlayer = nil
                stopMetering()
                completeNarrationIfCurrent(key: key)
            }
        } catch {
            logNarrationFailureIfNeeded(error.localizedDescription)
            completeNarrationIfCurrent(key: key)
        }
    }

    private func stopPlayback() {
        stopMetering()
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func startMetering() {
        meteringTimer?.invalidate()
        meteringTimer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateVoiceMeter()
            }
        }
        if let meteringTimer {
            RunLoop.main.add(meteringTimer, forMode: .common)
        }
        updateVoiceMeter()
    }

    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        voiceLevel = 0
    }

    private func updateVoiceMeter() {
        guard let audioPlayer, audioPlayer.isPlaying else {
            stopMetering()
            return
        }

        audioPlayer.updateMeters()
        let channelCount = max(audioPlayer.numberOfChannels, 1)
        let loudestPower = (0..<channelCount)
            .map { audioPlayer.averagePower(forChannel: $0) }
            .max() ?? -60
        let normalizedLevel = max(0, min(1, (Double(loudestPower) + 48) / 38))
        voiceLevel = normalizedLevel
    }

    private func completeNarrationIfCurrent(key: String) {
        guard activeNarrationKey == key else { return }
        completeNarration(key: key)
    }

    private func completeNarration(key: String) {
        activeNarrationKey = nil
        isNarrating = false
        voiceLevel = 0
        lastCompletedNarrationKey = key
    }

    private func logNarrationFailureIfNeeded(_ message: String) {
        guard lastLoggedFailureMessage != message else { return }
        print("🔇 [MacraNoraVoiceService] Nora narration failed: \(message)")
        lastLoggedFailureMessage = message
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            let completedKey = self?.activeNarrationKey
            self?.stopMetering()
            self?.audioPlayer = nil
            if let completedKey {
                self?.completeNarration(key: completedKey)
            } else {
                self?.isNarrating = false
            }
        }
    }
}
