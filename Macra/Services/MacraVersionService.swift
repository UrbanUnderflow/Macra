//
//  MacraVersionService.swift
//  Macra
//
//  Mirrors the PulseCheck/Fit With Pulse app-release feed contract, reading
//  from Macra-specific Firestore collections. The web admin lives at
//  QuickLifts-Web/src/pages/admin/addVersion.tsx — it writes to the same
//  collections/config document and admin toggles can disable the modal.
//

import Foundation
import SwiftUI
import AVKit
import FirebaseFirestore

// MARK: - Models

struct MacraAppVersionMediaItem: Identifiable {
    enum MediaType: String {
        case video
        case image
    }

    let id: String
    let type: MediaType
    let url: String
    let storagePath: String?
    let fileName: String?
    let mimeType: String?
}

struct MacraAppVersionPayload: Identifiable {
    let version: String
    let buildNumber: String?
    let changeNotes: [String]
    let isCriticalUpdate: Bool
    let mediaItems: [MacraAppVersionMediaItem]

    var id: String {
        MacraVersionService.releaseKey(version: version, buildNumber: buildNumber)
    }
}

struct MacraAppUpdateModalConfig {
    let isEnabled: Bool
}

struct MacraAppUpdateModalState {
    let latestRelease: MacraAppVersionPayload?
    let config: MacraAppUpdateModalConfig
}

// MARK: - Service

final class MacraVersionService {
    static let sharedInstance = MacraVersionService()

    private lazy var db = Firestore.firestore()
    private let collectionNamesToTry = ["macra-version", "macra-versions"]
    private let modalCollectionName = "company-config"
    private let modalDocumentId = "macra-app-update-modal"
    private let lastSeenReleaseKeyName = "macraLastSeenReleaseKey"

    var currentInstalledVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var currentInstalledBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var currentInstalledReleaseDisplay: String {
        "v\(currentInstalledVersion) (\(currentInstalledBuild))"
    }

    var lastSeenReleaseKey: String {
        UserDefaults.standard.string(forKey: lastSeenReleaseKeyName) ?? ""
    }

    private init() {}

    func fetchLatestVersion(completion: @escaping (MacraAppVersionPayload?) -> Void) {
        fetchAllVersionPayloads { payloads in
            completion(payloads.first)
        }
    }

    func fetchLatestVersionState(completion: @escaping (MacraAppUpdateModalState) -> Void) {
        let dispatchGroup = DispatchGroup()
        let stateQueue = DispatchQueue(label: "com.fitwithpulse.macra.version-state-sync")

        var latestRelease: MacraAppVersionPayload?
        var config = MacraAppUpdateModalConfig(isEnabled: true)

        dispatchGroup.enter()
        fetchLatestVersion { payload in
            stateQueue.sync { latestRelease = payload }
            dispatchGroup.leave()
        }

        dispatchGroup.enter()
        fetchModalConfig { modalConfig in
            stateQueue.sync { config = modalConfig }
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .global(qos: .userInitiated)) {
            completion(MacraAppUpdateModalState(latestRelease: latestRelease, config: config))
        }
    }

    func markReleaseSeen(version: String, buildNumber: String?) {
        UserDefaults.standard.set(
            Self.releaseKey(version: version, buildNumber: buildNumber),
            forKey: lastSeenReleaseKeyName
        )
    }

    static func compareVersionStrings(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = parseVersionParts(lhs)
        let rhsParts = parseVersionParts(rhs)
        let maxLength = max(lhsParts.count, rhsParts.count)

        for index in 0..<maxLength {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }

        if lhs == rhs { return .orderedSame }
        return lhs.localizedStandardCompare(rhs)
    }

    static func compareBuildNumbers(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        let left = Int((lhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        let right = Int((rhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines))

        switch (left, right) {
        case let (left?, right?):
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
            return .orderedSame
        case (_?, nil): return .orderedDescending
        case (nil, _?): return .orderedAscending
        case (nil, nil): return .orderedSame
        }
    }

    static func compareRelease(
        installedVersion: String,
        installedBuild: String,
        latestVersion: String,
        latestBuild: String?
    ) -> ComparisonResult {
        let versionComparison = compareVersionStrings(installedVersion, latestVersion)
        if versionComparison != .orderedSame { return versionComparison }
        return compareBuildNumbers(installedBuild, latestBuild)
    }

    static func releaseKey(version: String, buildNumber: String?) -> String {
        let normalizedBuild = (buildNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedBuild.isEmpty ? version : "\(version) (\(normalizedBuild))"
    }

    static func shouldShowUpdate(
        installedVersion: String,
        installedBuild: String,
        latestVersion: String,
        latestBuild: String?,
        lastSeenReleaseKey: String,
        isCriticalUpdate: Bool
    ) -> Bool {
        let installedComparison = compareRelease(
            installedVersion: installedVersion,
            installedBuild: installedBuild,
            latestVersion: latestVersion,
            latestBuild: latestBuild
        )

        if installedComparison == .orderedDescending { return false }
        if isCriticalUpdate && installedComparison == .orderedAscending { return true }
        return lastSeenReleaseKey != releaseKey(version: latestVersion, buildNumber: latestBuild)
    }

    private func fetchModalConfig(completion: @escaping (MacraAppUpdateModalConfig) -> Void) {
        db.collection(modalCollectionName).document(modalDocumentId).getDocument { snapshot, error in
            if let error {
                print("[Macra][VersionService] modal config error: \(error.localizedDescription)")
                completion(MacraAppUpdateModalConfig(isEnabled: true))
                return
            }
            let data = snapshot?.data() ?? [:]
            let isEnabled = data["isEnabled"] as? Bool ?? true
            completion(MacraAppUpdateModalConfig(isEnabled: isEnabled))
        }
    }

    private func fetchAllVersionPayloads(completion: @escaping ([MacraAppVersionPayload]) -> Void) {
        let dispatchGroup = DispatchGroup()
        let syncQueue = DispatchQueue(label: "com.fitwithpulse.macra.version-sync")
        var documentsById: [String: QueryDocumentSnapshot] = [:]

        for collectionName in collectionNamesToTry {
            dispatchGroup.enter()
            db.collection(collectionName).getDocuments { snapshot, error in
                defer { dispatchGroup.leave() }

                if let error {
                    print("[Macra][VersionService] fetch '\(collectionName)' failed: \(error.localizedDescription)")
                    return
                }

                let documents = snapshot?.documents ?? []
                guard !documents.isEmpty else { return }

                syncQueue.sync {
                    for document in documents {
                        let existing = documentsById[document.documentID]
                        documentsById[document.documentID] = self.preferredDocument(existing, candidate: document)
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .global(qos: .userInitiated)) {
            let payloads = documentsById.values
                .map { self.makePayload(from: $0) }
                .sorted { lhs, rhs in
                    let versionComparison = Self.compareVersionStrings(lhs.version, rhs.version)
                    if versionComparison != .orderedSame {
                        return versionComparison == .orderedDescending
                    }
                    return Self.compareBuildNumbers(lhs.buildNumber, rhs.buildNumber) == .orderedDescending
                }
            completion(payloads)
        }
    }

    private func preferredDocument(_ current: QueryDocumentSnapshot?, candidate: QueryDocumentSnapshot) -> QueryDocumentSnapshot {
        guard let current else { return candidate }
        let currentScore = score(for: current.data())
        let candidateScore = score(for: candidate.data())

        if candidateScore == currentScore {
            let currentBuild = current.data()["buildNumber"] as? String
            let candidateBuild = candidate.data()["buildNumber"] as? String
            return Self.compareBuildNumbers(candidateBuild, currentBuild) == .orderedDescending ? candidate : current
        }

        return candidateScore >= currentScore ? candidate : current
    }

    private func score(for data: [String: Any]) -> Int {
        let noteScore = normalizeChangeNotes(from: data).count
        let mediaScore = normalizeMediaItems(from: data).count * 2
        let buildScore = ((data["buildNumber"] as? String) ?? "").isEmpty ? 0 : 1
        return noteScore + mediaScore + buildScore
    }

    private func makePayload(from document: QueryDocumentSnapshot) -> MacraAppVersionPayload {
        let data = document.data()
        return MacraAppVersionPayload(
            version: document.documentID,
            buildNumber: normalizeBuildNumber(from: data),
            changeNotes: normalizeChangeNotes(from: data),
            isCriticalUpdate: (data["isCriticalUpdate"] as? Bool) ?? (data["isCritical"] as? Bool) ?? false,
            mediaItems: normalizeMediaItems(from: data)
        )
    }

    private func normalizeBuildNumber(from data: [String: Any]) -> String? {
        if let buildNumber = data["buildNumber"] as? String {
            let trimmed = buildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let buildNumber = data["buildNumber"] as? Int { return String(buildNumber) }
        if let build = data["build"] as? String {
            let trimmed = build.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let build = data["build"] as? Int { return String(build) }
        return nil
    }

    private func normalizeChangeNotes(from data: [String: Any]) -> [String] {
        if let changeNotes = data["changeNotes"] as? [String] {
            return changeNotes.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        let noteKeys = data.keys
            .filter { Int($0) != nil }
            .sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }

        return noteKeys.compactMap { key in
            guard let value = data[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func normalizeMediaItems(from data: [String: Any]) -> [MacraAppVersionMediaItem] {
        var items: [MacraAppVersionMediaItem] = []

        if let media = data["media"] as? [Any] {
            for (index, item) in media.enumerated() {
                if let normalized = normalizeMediaItem(from: item, fallbackType: nil, fallbackId: "media-\(index)") {
                    items.append(normalized)
                }
            }
        }

        if items.isEmpty {
            if let video = normalizeMediaItem(from: data["video"], fallbackType: .video, fallbackId: "video-0") {
                items.append(video)
            }
            if let images = data["images"] as? [Any] {
                for (index, item) in images.enumerated() {
                    if let normalized = normalizeMediaItem(from: item, fallbackType: .image, fallbackId: "image-\(index)") {
                        items.append(normalized)
                    }
                }
            }
        }

        return items
    }

    private func normalizeMediaItem(
        from rawValue: Any?,
        fallbackType: MacraAppVersionMediaItem.MediaType?,
        fallbackId: String
    ) -> MacraAppVersionMediaItem? {
        if let url = rawValue as? String, let type = fallbackType {
            return MacraAppVersionMediaItem(
                id: fallbackId, type: type, url: url,
                storagePath: nil, fileName: nil, mimeType: nil
            )
        }

        guard let rawValue = rawValue as? [String: Any] else { return nil }

        let resolvedType: MacraAppVersionMediaItem.MediaType?
        if let type = rawValue["type"] as? String {
            resolvedType = MacraAppVersionMediaItem.MediaType(rawValue: type)
        } else {
            resolvedType = fallbackType
        }

        guard let type = resolvedType, let url = rawValue["url"] as? String, !url.isEmpty else {
            return nil
        }

        return MacraAppVersionMediaItem(
            id: (rawValue["id"] as? String) ?? fallbackId,
            type: type,
            url: url,
            storagePath: rawValue["storagePath"] as? String,
            fileName: rawValue["fileName"] as? String,
            mimeType: rawValue["mimeType"] as? String
        )
    }

    private static func parseVersionParts(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            let numericCharacters = part.filter { $0.isNumber }
            return Int(numericCharacters) ?? 0
        }
    }
}

// MARK: - Modal View

struct MacraUpdateModalView: View {
    let release: MacraAppVersionPayload
    let onDismiss: (_ markSeen: Bool) -> Void

    private let appStoreURL = URL(string: "https://apps.apple.com/us/app/macra/id6747659393")!
    private let testFlightURL = URL(string: "itms-beta://")!

    @State private var selectedMediaIndex = 0
    @State private var videoPlayer: AVPlayer?

    var body: some View {
        ZStack {
            Color(hex: "#060608").ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header

                if !release.mediaItems.isEmpty {
                    mediaCarousel
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Why you're seeing this")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    Text(
                        release.isCriticalUpdate
                            ? "This build is now required to keep using Macra. If you are testing through TestFlight, opening update will take you there first."
                            : "A newer Macra build is live now. If you are testing through TestFlight, opening update will take you there first."
                    )
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("What's new")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(release.changeNotes.enumerated()), id: \.offset) { _, note in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(Color(hex: "#E0FE10"))

                                    Text(note)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white.opacity(0.92))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button(action: openUpdateDestination) {
                        HStack {
                            Spacer()
                            Text(release.isCriticalUpdate ? "Update to Continue" : "Open Update")
                                .font(.system(size: 18, weight: .bold))
                            Spacer()
                        }
                        .padding(.vertical, 16)
                        .foregroundColor(.black)
                        .background(Color(hex: "#E0FE10"))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    if !release.isCriticalUpdate {
                        Button {
                            stopPlayback()
                            onDismiss(true)
                        } label: {
                            HStack {
                                Spacer()
                                Text("Continue for now")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.76))
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(18)
        }
        .preferredColorScheme(.dark)
        .onAppear { configurePlayer() }
        .onChange(of: selectedMediaIndex) { _ in configurePlayer() }
        .onDisappear { stopPlayback() }
        .interactiveDismissDisabled(release.isCriticalUpdate)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#E0FE10"), Color(hex: "#C5EA17")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color(hex: "#E0FE10").opacity(0.4), radius: 18, x: 0, y: 6)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("New Macra update")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)

                    Text(releaseLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#E0FE10"))
                }
            }

            if release.isCriticalUpdate {
                Text("This release is marked as critical. Macra will stay locked on this screen until the newest build is installed.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
            }
        }
    }

    private var mediaCarousel: some View {
        VStack(spacing: 10) {
            TabView(selection: $selectedMediaIndex) {
                ForEach(Array(release.mediaItems.enumerated()), id: \.element.id) { index, media in
                    mediaView(for: media).tag(index)
                }
            }
            .frame(height: 220)
            .tabViewStyle(.page(indexDisplayMode: .never))

            if release.mediaItems.count > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(release.mediaItems.indices), id: \.self) { index in
                        Capsule()
                            .fill(index == selectedMediaIndex ? Color(hex: "#E0FE10") : Color.white.opacity(0.2))
                            .frame(width: index == selectedMediaIndex ? 22 : 8, height: 8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mediaView(for media: MacraAppVersionMediaItem) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))

            if media.type == .video {
                if let videoPlayer {
                    VideoPlayer(player: videoPlayer)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let url = URL(string: media.url) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholderMediaIcon
                    case .empty:
                        ProgressView().tint(.white)
                    @unknown default:
                        placeholderMediaIcon
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                placeholderMediaIcon
            }

            Text(media.type == .video ? "Video" : "Image")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var placeholderMediaIcon: some View {
        Color.white.opacity(0.06)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            )
    }

    private var releaseLabel: String {
        if let buildNumber = release.buildNumber, !buildNumber.isEmpty {
            return "Version \(release.version) • Build \(buildNumber)"
        }
        return "Version \(release.version)"
    }

    private func configurePlayer() {
        guard selectedMediaIndex < release.mediaItems.count else {
            stopPlayback()
            return
        }

        let selectedMedia = release.mediaItems[selectedMediaIndex]
        guard selectedMedia.type == .video, let url = URL(string: selectedMedia.url) else {
            stopPlayback()
            return
        }

        if let currentAsset = videoPlayer?.currentItem?.asset as? AVURLAsset,
           currentAsset.url == url {
            videoPlayer?.play()
            return
        }

        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        videoPlayer = player
        player.play()
    }

    private func stopPlayback() {
        videoPlayer?.pause()
        videoPlayer = nil
    }

    private func openUpdateDestination() {
        stopPlayback()
        UIApplication.shared.open(testFlightURL, options: [:]) { success in
            if !success {
                UIApplication.shared.open(self.appStoreURL)
            }
        }
    }
}
