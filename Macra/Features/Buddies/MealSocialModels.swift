import Foundation

/// Like on a buddy's logged meal. Stored at
/// `users/{ownerUid}/mealLogs/{mealId}/likes/{likerUid}` — doc id is the
/// liker's uid so a tap is idempotent (one like per user, toggle by
/// presence/absence). Owner's profile is implicit from the parent path.
struct MealLike: Identifiable, Hashable {
    /// Always equal to `likerUid`.
    let id: String
    let likerUid: String
    let likerEmail: String?
    /// FWP-authoritative handle, snapshotted at like time. Preferred over
    /// the email localpart in display strings.
    let likerUsername: String?
    let likerProfileImageURL: String?
    let createdAt: Date

    init(
        likerUid: String,
        likerEmail: String?,
        likerUsername: String? = nil,
        likerProfileImageURL: String?,
        createdAt: Date = Date()
    ) {
        self.id = likerUid
        self.likerUid = likerUid
        self.likerEmail = likerEmail
        self.likerUsername = likerUsername
        self.likerProfileImageURL = likerProfileImageURL
        self.createdAt = createdAt
    }

    init?(dictionary: [String: Any], id: String) {
        guard let likerUid = dictionary["likerUid"] as? String, !likerUid.isEmpty else {
            return nil
        }
        self.id = id
        self.likerUid = likerUid
        self.likerEmail = dictionary["likerEmail"] as? String
        let storedUsername = (dictionary["likerUsername"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.likerUsername = (storedUsername?.isEmpty == false) ? storedUsername : nil
        self.likerProfileImageURL = dictionary["likerProfileImageURL"] as? String
        if let ts = dictionary["createdAt"] as? Double {
            self.createdAt = Date(timeIntervalSince1970: ts)
        } else {
            self.createdAt = Date()
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "likerUid": likerUid,
            "createdAt": createdAt.timeIntervalSince1970
        ]
        if let likerEmail { dict["likerEmail"] = likerEmail }
        if let likerUsername, !likerUsername.isEmpty { dict["likerUsername"] = likerUsername }
        if let likerProfileImageURL { dict["likerProfileImageURL"] = likerProfileImageURL }
        return dict
    }

    var displayName: String {
        if let username = likerUsername, !username.isEmpty {
            return username
        }
        if let email = likerEmail, !email.isEmpty {
            return email.split(separator: "@").first.map(String.init) ?? email
        }
        return "Buddy"
    }
}

/// Comment thread entry on a buddy's meal. Stored at
/// `users/{ownerUid}/mealLogs/{mealId}/comments/{commentId}` with an
/// auto-generated doc id. Author profile is snapshotted at write time so
/// the row renders without a follow-up `users/{authorUid}` fetch.
struct MealComment: Identifiable, Hashable {
    let id: String
    let authorUid: String
    let authorEmail: String?
    /// FWP-authoritative handle, snapshotted at comment time.
    let authorUsername: String?
    let authorProfileImageURL: String?
    let text: String
    let createdAt: Date

    init(
        id: String,
        authorUid: String,
        authorEmail: String?,
        authorUsername: String? = nil,
        authorProfileImageURL: String?,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.authorUid = authorUid
        self.authorEmail = authorEmail
        self.authorUsername = authorUsername
        self.authorProfileImageURL = authorProfileImageURL
        self.text = text
        self.createdAt = createdAt
    }

    init?(dictionary: [String: Any], id: String) {
        guard let authorUid = dictionary["authorUid"] as? String, !authorUid.isEmpty,
              let text = dictionary["text"] as? String, !text.isEmpty else {
            return nil
        }
        self.id = id
        self.authorUid = authorUid
        self.authorEmail = dictionary["authorEmail"] as? String
        let storedUsername = (dictionary["authorUsername"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.authorUsername = (storedUsername?.isEmpty == false) ? storedUsername : nil
        self.authorProfileImageURL = dictionary["authorProfileImageURL"] as? String
        self.text = text
        if let ts = dictionary["createdAt"] as? Double {
            self.createdAt = Date(timeIntervalSince1970: ts)
        } else {
            self.createdAt = Date()
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "authorUid": authorUid,
            "text": text,
            "createdAt": createdAt.timeIntervalSince1970
        ]
        if let authorEmail { dict["authorEmail"] = authorEmail }
        if let authorUsername, !authorUsername.isEmpty { dict["authorUsername"] = authorUsername }
        if let authorProfileImageURL { dict["authorProfileImageURL"] = authorProfileImageURL }
        return dict
    }

    var displayName: String {
        if let username = authorUsername, !username.isEmpty {
            return username
        }
        if let email = authorEmail, !email.isEmpty {
            return email.split(separator: "@").first.map(String.init) ?? email
        }
        return "Buddy"
    }
}
