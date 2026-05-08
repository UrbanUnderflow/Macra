import Foundation

enum RegistrationEntryPoint: String {
    case macra = "macra"
    case fitWithPulse = "fit_with_pulse"
    case pulseCheck = "pulse_check"
}

struct User {
    var id: String
    var email: String
    /// FWP-authoritative display handle. May be empty for Macra-only
    /// accounts that never went through FWP onboarding — `UserService`
    /// backfills it to the email localpart on load so any surface that
    /// shows another user's name (buddy rows, like avatars, meal
    /// comments) has a stable, non-email-y string to render.
    var username: String
    var birthdate: Date
    var profileImageURL: String
    var subscriptionType: SubscriptionType
    var registrationEntryPoint: RegistrationEntryPoint?
    var hasCompletedMacraOnboarding: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Localpart of `email`, used as the fallback username for accounts
    /// that haven't set one. Static so callers (e.g. UserService backfill
    /// at load time) can compute it without instantiating a User.
    static func emailLocalpart(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let local = trimmed.split(separator: "@").first else { return nil }
        let candidate = String(local).trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    init(id: String,
         email: String,
         birthdate: Date,
         dogName: String,

         profileImageURL: String?,
         subscriptionType: SubscriptionType,
         registrationEntryPoint: RegistrationEntryPoint? = nil,
         hasCompletedMacraOnboarding: Bool = false,
         username: String = "",
         createdAt: Date,
         updatedAt: Date) {
        self.id = id
        self.email = email
        self.username = username
        self.birthdate = birthdate
        self.profileImageURL = profileImageURL ?? ""
        self.subscriptionType = subscriptionType
        self.registrationEntryPoint = registrationEntryPoint
        self.hasCompletedMacraOnboarding = hasCompletedMacraOnboarding
        self.createdAt = createdAt
        self.updatedAt = updatedAt

    }

    init?(id: String, dictionary: [String: Any]) {
        self.id = id
        self.email = dictionary["email"] as? String ?? ""
        self.username = (dictionary["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.birthdate = Self.date(from: dictionary, key: "birthdate")

        self.profileImageURL = Self.resolvedProfileImageURL(from: dictionary)

        self.subscriptionType = SubscriptionType.fromSharedRootValue(dictionary["subscriptionType"] as? String)
        self.registrationEntryPoint = RegistrationEntryPoint(rawValue: dictionary["registrationEntryPoint"] as? String ?? "")

        self.hasCompletedMacraOnboarding = dictionary["hasCompletedMacraOnboarding"] as? Bool ?? false

        self.createdAt = Self.date(from: dictionary, key: "createdAt")
        self.updatedAt = Self.date(from: dictionary, key: "updatedAt")

    }
    
    func updateUserObject() -> User {
        var newUser = self
        newUser.updatedAt = Date()
        UserService.sharedInstance.user = self

        return newUser
    }

    func toMacraOwnedPatch() -> [String: Any] {
        var userDict: [String: Any] = [
            "hasCompletedMacraOnboarding": hasCompletedMacraOnboarding,
            "updatedAt": updatedAt.timeIntervalSince1970 > 0 ? updatedAt.timeIntervalSince1970 : Date().timeIntervalSince1970
        ]

        if let registrationEntryPoint {
            userDict["registrationEntryPoint"] = registrationEntryPoint.rawValue
        }

        return userDict
    }

    private static func resolvedProfileImageURL(from dictionary: [String: Any]) -> String {
        let flatURL = dictionary["profileImageURL"] as? String
        let nestedProfileImage = dictionary["profileImage"] as? [String: Any]
        let nestedURL = nestedProfileImage?["profileImageURL"] as? String
        let authURL = dictionary["photoURL"] as? String ?? dictionary["photoUrl"] as? String
        let legacyURL = dictionary["imageURL"] as? String ?? dictionary["imageUrl"] as? String

        let resolved = [flatURL, nestedURL, authURL, legacyURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        return resolved.replacingOccurrences(of: "firebasestorage.googleapis.com:443", with: "firebasestorage.googleapis.com")
    }

    private static func date(from dictionary: [String: Any], key: String) -> Date {
        if let date = dictionary[key] as? Date {
            return date
        }

        if let number = dictionary[key] as? NSNumber {
            let value = number.doubleValue
            return value > 0 ? Date(timeIntervalSince1970: value) : .distantPast
        }

        return .distantPast
    }
}
