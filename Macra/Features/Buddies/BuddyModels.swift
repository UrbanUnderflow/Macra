import Foundation

/// One-way follow relationship from the perspective of the *follower*.
/// Stored at `users/{followerUid}/buddies/{targetUid}`. The target's
/// profile fields are snapshotted at accept time so listing buddies is a
/// single subcollection read — we don't fan out to fetch every target's
/// `users/{uid}` doc just to render a row.
struct BuddyConnection: Identifiable, Hashable {
    /// Always equal to `targetUid` for ergonomic lookup. Firestore doc id.
    let id: String
    /// The user being followed.
    let targetUid: String
    /// Snapshot of target.email at accept time. Used as a fallback render
    /// string when no username is available.
    let targetEmail: String?
    /// FWP-authoritative handle for the target, snapshotted at accept
    /// time. `nil` for buddy docs written before the username field was
    /// plumbed through — those rows fall back to the email localpart.
    let targetUsername: String?
    /// Snapshot of target.profileImageURL at accept time. Stale if target
    /// updates their photo — acceptable for v1; refresh on re-add.
    let targetProfileImageURL: String?
    let createdAt: Date

    init(
        targetUid: String,
        targetEmail: String?,
        targetUsername: String? = nil,
        targetProfileImageURL: String?,
        createdAt: Date = Date()
    ) {
        self.id = targetUid
        self.targetUid = targetUid
        self.targetEmail = targetEmail
        self.targetUsername = targetUsername
        self.targetProfileImageURL = targetProfileImageURL
        self.createdAt = createdAt
    }

    init?(dictionary: [String: Any]) {
        guard let targetUid = dictionary["targetUid"] as? String, !targetUid.isEmpty else {
            return nil
        }
        self.id = targetUid
        self.targetUid = targetUid
        self.targetEmail = dictionary["targetEmail"] as? String
        let storedUsername = (dictionary["targetUsername"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetUsername = (storedUsername?.isEmpty == false) ? storedUsername : nil
        self.targetProfileImageURL = dictionary["targetProfileImageURL"] as? String
        if let ts = dictionary["createdAt"] as? Double {
            self.createdAt = Date(timeIntervalSince1970: ts)
        } else {
            self.createdAt = Date()
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "targetUid": targetUid,
            "createdAt": createdAt.timeIntervalSince1970
        ]
        if let targetEmail { dict["targetEmail"] = targetEmail }
        if let targetUsername, !targetUsername.isEmpty { dict["targetUsername"] = targetUsername }
        if let targetProfileImageURL { dict["targetProfileImageURL"] = targetProfileImageURL }
        return dict
    }

    /// Display priority: snapshotted username → email localpart →
    /// "Buddy". Once the buddy graph fully migrates, the email fallback
    /// can be removed.
    var displayName: String {
        if let username = targetUsername, !username.isEmpty {
            return username
        }
        if let email = targetEmail, !email.isEmpty {
            return email.split(separator: "@").first.map(String.init) ?? email
        }
        return "Buddy"
    }
}

/// A shareable invite token. Created when the inviter taps "Generate
/// link", consumed when a recipient opens/pastes the matching URL. Stored
/// at `macraBuddyInvites/{token}` (top-level) so any signed-in user can
/// look it up by id without leaking other users' invites — the doc id is
/// the unguessable secret.
struct BuddyInvite: Identifiable, Hashable {
    static let canonicalBuddyInviteHost = "https://fitwithpulse.ai"
    static let previewTitle = "Eat with me on Macra"
    static let previewDescription = "Follow my food journal and share daily eating habits with me on Macra."
    static let previewImageURL = "https://fitwithpulse.ai/preview/macra-buddy.png"

    /// Random URL-safe token; doubles as the Firestore doc id.
    let id: String
    let inviterUid: String
    /// Snapshotted at create time so the recipient sees who invited them
    /// before accepting (future v1.1: render an "Accept invite from X?"
    /// confirmation; v1 auto-accepts on the assumption the recipient
    /// trusts the link they pasted).
    let inviterEmail: String?
    /// FWP-authoritative handle for the inviter, snapshotted at link
    /// generation time. `nil` for older invite docs.
    let inviterUsername: String?
    let inviterProfileImageURL: String?
    let createdAt: Date
    /// `nil` = no expiration. Multi-use links don't auto-expire.
    let expiresAt: Date?
    /// Bumped on each successful accept. Useful for "this link has been
    /// accepted N times" UX and lightweight abuse signals.
    var usedCount: Int

    init(
        id: String = BuddyInvite.makeToken(),
        inviterUid: String,
        inviterEmail: String?,
        inviterUsername: String? = nil,
        inviterProfileImageURL: String?,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        usedCount: Int = 0
    ) {
        self.id = id
        self.inviterUid = inviterUid
        self.inviterEmail = inviterEmail
        self.inviterUsername = inviterUsername
        self.inviterProfileImageURL = inviterProfileImageURL
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.usedCount = usedCount
    }

    init?(dictionary: [String: Any], id: String) {
        guard let inviterUid = dictionary["inviterUid"] as? String, !inviterUid.isEmpty else {
            return nil
        }
        self.id = id
        self.inviterUid = inviterUid
        self.inviterEmail = dictionary["inviterEmail"] as? String
        let storedUsername = (dictionary["inviterUsername"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.inviterUsername = (storedUsername?.isEmpty == false) ? storedUsername : nil
        self.inviterProfileImageURL = dictionary["inviterProfileImageURL"] as? String
        if let ts = dictionary["createdAt"] as? Double {
            self.createdAt = Date(timeIntervalSince1970: ts)
        } else {
            self.createdAt = Date()
        }
        if let ts = dictionary["expiresAt"] as? Double {
            self.expiresAt = Date(timeIntervalSince1970: ts)
        } else {
            self.expiresAt = nil
        }
        self.usedCount = dictionary["usedCount"] as? Int ?? 0
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "inviterUid": inviterUid,
            "createdAt": createdAt.timeIntervalSince1970,
            "usedCount": usedCount
        ]
        if let inviterEmail { dict["inviterEmail"] = inviterEmail }
        if let inviterUsername, !inviterUsername.isEmpty { dict["inviterUsername"] = inviterUsername }
        if let inviterProfileImageURL { dict["inviterProfileImageURL"] = inviterProfileImageURL }
        if let expiresAt { dict["expiresAt"] = expiresAt.timeIntervalSince1970 }
        return dict
    }

    /// 16-char URL-safe random token. ~95 bits of entropy — enough that
    /// brute-force enumeration of `macraBuddyInvites/{token}` is
    /// infeasible against the Firestore quota.
    static func makeToken() -> String {
        let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
        return String((0..<16).map { _ in alphabet.randomElement()! })
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    /// Builds the shareable URL the inviter copies/messages. Uses the
    /// canonical fitwithpulse.ai universal-link path until AppsFlyer's
    /// OneLink AASA is associated with Macra, then can return the OneLink
    /// format when `useAppsFlyerOneLinkForBuddyInvites` is re-enabled.
    static func shareURL(forToken token: String) -> URL? {
        let canonicalURLString = "\(canonicalBuddyInviteHost)/macra/buddy/\(token)"
        guard MacraDeepLinkService.useAppsFlyerOneLinkForBuddyInvites else {
            return URL(string: canonicalURLString)
        }

        if let subdomain = MacraDeepLinkService.oneLinkSubdomain,
           let template = MacraDeepLinkService.oneLinkTemplateID,
           !subdomain.isEmpty, !template.isEmpty {
            // OneLink params: `deep_link_value` routes inside the app
            // (the DeepLinkDelegate keys on it), `buddy_token` carries
            // the payload, and `af_dp` provides a custom-scheme fallback
            // for users whose iOS build pre-dates the AASA association.
            var components = URLComponents()
            components.scheme = "https"
            components.host = subdomain
            components.path = "/\(template)"
            components.queryItems = [
                URLQueryItem(name: "deep_link_value", value: "buddy"),
                URLQueryItem(name: "buddy_token", value: token),
                URLQueryItem(name: "af_dp", value: "macra://buddy/\(token)"),
                URLQueryItem(name: "af_ios_url", value: MacraDeepLinkService.appStoreURL),
                URLQueryItem(name: "af_app_id", value: MacraDeepLinkService.appleAppID),
                URLQueryItem(name: "af_r", value: canonicalURLString),
                URLQueryItem(name: "af_og_title", value: previewTitle),
                URLQueryItem(name: "af_og_description", value: previewDescription),
                URLQueryItem(name: "af_og_image", value: previewImageURL)
            ]
            if let url = components.url {
                return url
            }
        }
        return URL(string: canonicalURLString)
    }
}

/// Inverse of `BuddyConnection` — represents *another user who follows me*.
/// We can't read this directly from `users/{me}/buddies` (which holds people
/// I follow); it's surfaced via a collection-group query on `buddies` with
/// `targetUid == me`, then we resolve each follower's profile separately.
/// The follower's profile fields are NOT snapshotted onto the Firestore doc
/// (the doc was written from the follower's perspective, with my snapshot
/// inside) so we fetch them on demand from `users/{followerUid}`.
struct BuddyFollower: Identifiable, Hashable {
    /// Always equal to `followerUid` for ergonomic lookup.
    let id: String
    /// The user who is following me.
    let followerUid: String
    /// Resolved at observe-time from the follower's user doc. May be nil
    /// if the doc is missing or unreadable — fall back to "Buddy".
    let followerEmail: String?
    /// FWP-authoritative handle. `nil` if the follower hasn't set one
    /// (Macra-only sign-up that hasn't been backfilled yet).
    let followerUsername: String?
    let followerProfileImageURL: String?
    /// When *they* started following me — read from the buddy doc's
    /// `createdAt` (set when they accepted my invite).
    let createdAt: Date

    init(
        followerUid: String,
        followerEmail: String?,
        followerUsername: String? = nil,
        followerProfileImageURL: String?,
        createdAt: Date
    ) {
        self.id = followerUid
        self.followerUid = followerUid
        self.followerEmail = followerEmail
        self.followerUsername = followerUsername
        self.followerProfileImageURL = followerProfileImageURL
        self.createdAt = createdAt
    }

    /// Display priority: live username → email localpart → "Buddy".
    var displayName: String {
        if let username = followerUsername, !username.isEmpty {
            return username
        }
        if let email = followerEmail, !email.isEmpty {
            return email.split(separator: "@").first.map(String.init) ?? email
        }
        return "Buddy"
    }
}

/// Stand-alone request from one user asking another to share their food
/// journal back. Lives at `users/{toUid}/buddyRequests/{fromUid}` — doc id
/// is the requester's uid so a duplicate tap idempotently overwrites the
/// same doc. When the recipient accepts, their app writes the buddy record
/// onto the requester's side and deletes the request atomically.
struct BuddyShareRequest: Identifiable, Hashable {
    /// Equal to `fromUid` for ergonomic lookup.
    let id: String
    /// The user who initiated the request.
    let fromUid: String
    let fromEmail: String?
    /// FWP-authoritative handle for the requester, snapshotted at write
    /// time. `nil` for requests written before this field was added.
    let fromUsername: String?
    let fromProfileImageURL: String?
    /// Snapshot at request time so the recipient can render the row even
    /// before resolving the requester's freshest profile.
    let toUid: String
    let createdAt: Date

    init(
        fromUid: String,
        fromEmail: String?,
        fromUsername: String? = nil,
        fromProfileImageURL: String?,
        toUid: String,
        createdAt: Date = Date()
    ) {
        self.id = fromUid
        self.fromUid = fromUid
        self.fromEmail = fromEmail
        self.fromUsername = fromUsername
        self.fromProfileImageURL = fromProfileImageURL
        self.toUid = toUid
        self.createdAt = createdAt
    }

    init?(dictionary: [String: Any], id: String) {
        guard let fromUid = dictionary["fromUid"] as? String, !fromUid.isEmpty,
              let toUid = dictionary["toUid"] as? String, !toUid.isEmpty else {
            return nil
        }
        self.id = id
        self.fromUid = fromUid
        self.fromEmail = dictionary["fromEmail"] as? String
        let storedUsername = (dictionary["fromUsername"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.fromUsername = (storedUsername?.isEmpty == false) ? storedUsername : nil
        self.fromProfileImageURL = dictionary["fromProfileImageURL"] as? String
        self.toUid = toUid
        if let ts = dictionary["createdAt"] as? Double {
            self.createdAt = Date(timeIntervalSince1970: ts)
        } else {
            self.createdAt = Date()
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "fromUid": fromUid,
            "toUid": toUid,
            "createdAt": createdAt.timeIntervalSince1970
        ]
        if let fromEmail { dict["fromEmail"] = fromEmail }
        if let fromUsername, !fromUsername.isEmpty { dict["fromUsername"] = fromUsername }
        if let fromProfileImageURL { dict["fromProfileImageURL"] = fromProfileImageURL }
        return dict
    }

    var displayName: String {
        if let username = fromUsername, !username.isEmpty {
            return username
        }
        if let email = fromEmail, !email.isEmpty {
            return email.split(separator: "@").first.map(String.init) ?? email
        }
        return "Buddy"
    }
}

struct BuddyInvitePreview: Identifiable, Hashable {
    let token: String
    let inviterUid: String
    let inviterEmail: String?
    let inviterUsername: String?
    let inviterProfileImageURL: String?
    let recentMeals: [Meal]

    var id: String { token }

    var displayName: String {
        if let username = inviterUsername, !username.isEmpty {
            return username
        }
        if let email = inviterEmail, !email.isEmpty {
            return email.split(separator: "@").first.map(String.init) ?? email
        }
        return "Your buddy"
    }

    var recentMealCount: Int { recentMeals.count }

    var recentCalories: Int {
        recentMeals.reduce(0) { $0 + $1.calories }
    }

    var recentProtein: Int {
        recentMeals.reduce(0) { $0 + $1.protein }
    }

    var recentMealNames: [String] {
        recentMeals
            .prefix(3)
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum BuddyError: LocalizedError, Equatable {
    case notSignedIn
    case inviteNotFound
    case inviteExpired
    case selfInvite
    case alreadyFollowing
    case malformedURL

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to use buddies."
        case .inviteNotFound: return "That invite link is invalid or has been revoked."
        case .inviteExpired: return "That invite has expired. Ask for a fresh link."
        case .selfInvite: return "You can't follow yourself."
        case .alreadyFollowing: return "You already follow this buddy."
        case .malformedURL: return "Couldn't read a buddy token from that link."
        }
    }
}

enum BuddyURLParser {
    private static let tokenPattern = "^[A-Za-z0-9_-]{12,}$"

    /// Extracts a buddy token from any of the supported URL formats:
    /// - `https://fitwithpulse.ai/macra/buddy/<token>` (canonical)
    /// - `macra://buddy/<token>` (custom scheme)
    /// - OneLink long URLs carrying `buddy_token` or `deep_link_sub1`
    /// - bare `<token>` paste, when the recipient stripped the URL.
    static func token(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Try parsing as a URL first — covers both http(s) and the
        // custom scheme. The buddy token is always the last path component.
        if let url = URL(string: trimmed) {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let token = tokenFromQueryItems(components.queryItems) {
                return token
            }

            if url.scheme?.lowercased() == "macra",
               url.host?.lowercased() == "buddy",
               let token = normalizedToken(url.pathComponents.last) {
                return token
            }

            if url.pathComponents.contains("buddy"),
               let token = normalizedToken(url.pathComponents.last) {
                return token
            }
        }

        // Bare-token paste — accept anything that looks like our format
        // (URL-safe alphanumeric, 12+ chars).
        return normalizedToken(trimmed)
    }

    private static func tokenFromQueryItems(_ queryItems: [URLQueryItem]?) -> String? {
        guard let queryItems else { return nil }
        for name in ["buddy_token", "deep_link_sub1"] {
            if let value = queryItems.first(where: { $0.name == name })?.value,
               let token = normalizedToken(value) {
                return token
            }
        }
        for name in ["af_dp", "af_r"] {
            if let value = queryItems.first(where: { $0.name == name })?.value,
               let token = token(from: value) {
                return token
            }
        }
        return nil
    }

    private static func normalizedToken(_ candidate: String?) -> String? {
        guard let token = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              token != "buddy",
              token.range(of: tokenPattern, options: .regularExpression) != nil else {
            return nil
        }
        return token
    }
}
