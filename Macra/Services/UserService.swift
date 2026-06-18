import Foundation
import FirebaseAuth
import FirebaseFirestore

enum UserServiceError: Error {
    case noValidRound
}

enum SubscriptionType: String {
    case free
    case beta
    case monthly
    case annual
    case lifetime

    static func fromSharedRootValue(_ rawValue: String?) -> SubscriptionType {
        let normalized = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "beta":
            return .beta
        case "monthly", "monthly subscriber":
            return .monthly
        case "annual", "annual subscriber", "subscriber":
            return .annual
        case "lifetime", "lifetime subscriber":
            return .lifetime
        default:
            return .free
        }
    }

    var grantsMacraAccess: Bool {
        switch self {
        case .free:
            return false
        case .beta, .monthly, .annual, .lifetime:
            return true
        }
    }
}

class UserService: ObservableObject {
    static let sharedInstance = UserService()
    private static let localBetaAccessKey = "macra.localBetaAccess"
    private static let pendingMacraFcmTokenKey = "macra.pendingFcmToken"
    private var db: Firestore!
    
    @Published var user: User? = nil
    @Published var settings = Settings()
    @Published var isBetaUser: Bool = false
    @Published var isSubscribed: Bool = false
    @Published var currentMacroTarget: MacroRecommendation?
        
    struct Settings {
        // UserDefaults property
        var hasIntroductionModalShown: Bool {
            get {
                return UserDefaults.standard.bool(forKey: "hasIntroductionModalShown")
            }
            set {
                UserDefaults.standard.set(newValue, forKey: "hasIntroductionModalShown")
            }
        }
    }
    
    private init() {
        FirebaseService.configureFirebaseAppIfNeeded()
        db = Firestore.firestore()
        loadSettings()
        isBetaUser = UserDefaults.standard.bool(forKey: Self.localBetaAccessKey)
    }
    
    private func loadSettings() {
        _ = settings.hasIntroductionModalShown
    }
    
    func getUser(completion: @escaping (User?, Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(nil, nil)
            return
        }
        
        let userRef = db.collection("users").document(userId)
        
        // Add snapshot listener for user document
        userRef.getDocument { (document, error) in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let document = document, document.exists else {
                completion(nil, nil)
                return
            }
            
            let userData = document.data() ?? [:]
            guard var user = User(id: document.documentID, dictionary: userData) else {
                completion(nil, nil)
                return
            }

            // Backfill username for Macra-only accounts. The user doc may
            // be co-owned with FWP, where `username` is the authoritative
            // handle. If FWP never set one (Macra-only signup), persist
            // the email localpart as the username so every surface that
            // renders this user (buddy rows, like avatars, comments) has
            // a stable, non-email-y string to display. FWP will overwrite
            // this if/when the user goes through FWP onboarding later.
            if user.username.isEmpty, let localpart = User.emailLocalpart(user.email) {
                user.username = localpart
                userRef.updateData(["username": localpart]) { backfillError in
                    if let backfillError {
                        print("[Macra][UserService.getUser] username backfill failed: \(backfillError.localizedDescription)")
                    } else {
                        print("[Macra][UserService.getUser] ✓ username backfilled to \(localpart)")
                    }
                }
            }

            DispatchQueue.main.async {
                self.user = user
                self.isBetaUser = user.subscriptionType == .beta || UserDefaults.standard.bool(forKey: Self.localBetaAccessKey)
                self.isSubscribed = user.subscriptionType.grantsMacraAccess || self.isBetaUser
                self.flushPendingMacraPushTokenIfAuthenticated()
                completion(user, nil)
            }
        }
    }

    /// Saves the FCM token minted by the Macra iOS app. This deliberately
    /// does not touch `users.fcmToken`, which is owned by Pulse.
    func saveMacraPushToken(_ token: String, completion: ((Error?) -> Void)? = nil) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            completion?(nil)
            return
        }

        UserDefaults.standard.set(normalized, forKey: Self.pendingMacraFcmTokenKey)

        guard Auth.auth().currentUser?.uid != nil else {
            completion?(nil)
            return
        }

        updateRootUserPatch([
            "macraFcmToken": normalized,
            "pushTokens.macra": normalized,
            "macraFcmTokenUpdatedAt": Date().timeIntervalSince1970,
            "pushTokenSources.macra": "macra-ios",
        ]) { error in
            if error == nil,
               UserDefaults.standard.string(forKey: Self.pendingMacraFcmTokenKey) == normalized {
                UserDefaults.standard.removeObject(forKey: Self.pendingMacraFcmTokenKey)
            }
            completion?(error)
        }
    }

    func flushPendingMacraPushTokenIfAuthenticated() {
        guard Auth.auth().currentUser?.uid != nil,
              let pending = UserDefaults.standard.string(forKey: Self.pendingMacraFcmTokenKey),
              !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        saveMacraPushToken(pending)
    }

    func saveMacraExperimentAssignment(
        _ assignment: MacraPaywallExperimentAssignment,
        salt: String,
        collectionName: String,
        documentId: String,
        completion: ((Error?) -> Void)? = nil
    ) {
        let assignedAt = Date().timeIntervalSince1970
        let basePath = "macraExperiments.\(assignment.experimentId)"
        let assignmentPayload: [String: Any] = [
            "variantId": assignment.variantId,
            "variantName": assignment.variantName,
            "assignmentSource": assignment.assignmentSource,
            "assignmentSalt": salt,
            "assignedAt": assignedAt,
            "parameters": assignment.parameters,
            "defaultPlan": assignment.defaultPlanSelection.rawValue,
            "layoutVariant": assignment.layoutVariant.rawValue,
            "onboardingVariant": assignment.onboardingVariant.rawValue,
            "collectionName": collectionName,
            "documentId": documentId
        ]

        updateRootUserPatch([
            "\(basePath).variantId": assignment.variantId,
            "\(basePath).variantName": assignment.variantName,
            "\(basePath).assignmentSource": assignment.assignmentSource,
            "\(basePath).assignmentSalt": salt,
            "\(basePath).assignedAt": assignedAt,
            "\(basePath).parameters": assignment.parameters,
            "\(basePath).collectionName": collectionName,
            "\(basePath).documentId": documentId,
            "experimentAssignments.\(assignment.experimentId).variantId": assignment.variantId,
            "experimentAssignments.\(assignment.experimentId).variantName": assignment.variantName,
            "experimentAssignments.\(assignment.experimentId).parameters": assignment.parameters,
            "macraExperimentAssignments.\(assignment.experimentId).variantId": assignment.variantId,
            "macraExperimentAssignments.\(assignment.experimentId).variantName": assignment.variantName,
            "macraExperimentAssignments.\(assignment.experimentId).parameters": assignment.parameters,
            "macraExperiment": assignmentPayload,
            "macraExperimentVariantId": assignment.variantId,
            "macraExperimentVariantName": assignment.variantName,
            "macraExperimentAssignedAt": assignedAt,
            "macraExperimentParameters": assignment.parameters,
            "macra_paywall_default_plan": assignment.defaultPlanSelection.rawValue,
            "macra_paywall_layout_variant": assignment.layoutVariant.rawValue,
            "onboarding_experience_variant": assignment.onboardingVariant.rawValue,
            "macraPaywallLayoutVariant": assignment.layoutVariant.rawValue,
            "macraOnboardingExperienceVariant": assignment.onboardingVariant.rawValue
        ], completion: completion)
    }
    
    func deleteAccount(email: String, password: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        // Re-authenticate the user using their username and password
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        
        Auth.auth().currentUser?.reauthenticate(with: credential) { [weak self] _, error in
            guard let self = self else { return }
            
            if let error = error {
                // Handle re-authentication error
                print("Error re-authenticating user: \(error)")
                return
            }
            
            guard let userId = Auth.auth().currentUser?.uid else {
                // Unable to retrieve user ID
                return
            }
            
            // Delete user's data
            let userRef = self.db.collection("users").document(userId)
            userRef.delete { error in
                if let error = error {
                    // Handle data deletion error
                    print("Error deleting user's data: \(error)")
                    return
                }
                
                // Delete user's authentication
                FirebaseService.sharedInstance.deleteAccount { result in
                    switch result {
                    case .success(_):
                        self.user = nil
                        completion(.success(true))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    func saveMacraProfile(answers: MacraOnboardingAnswers, completion: ((Error?) -> Void)? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion?(nil)
            return
        }

        db.collection("users").document(userId)
            .collection("macra").document("profile")
            .setData(answers.toDictionary(), merge: true) { error in
                if let error = error {
                    print("Error saving Macra profile: \(error.localizedDescription)")
                }
                completion?(error)
            }

        // Mirror athlete sport to the shared user doc so FWP / PulseCheck /
        // the Sports Intelligence Layer can read it without crossing into
        // Macra's nested profile collection.
        if answers.activityLevel == .athlete, let sport = answers.sport {
            var rootFields: [String: Any] = ["athleteSport": sport]
            if let name = answers.sportName { rootFields["athleteSportName"] = name }
            if let position = answers.sportPosition { rootFields["athleteSportPosition"] = position }
            updateRootUserPatch(rootFields)
        }
    }

    func hasSavedMacraProfile(completion: @escaping (Bool) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }

        db.collection("users").document(userId)
            .collection("macra").document("profile")
            .getDocument { document, error in
                if let error {
                    print("Error checking Macra profile: \(error.localizedDescription)")
                    completion(false)
                    return
                }

                completion(document?.exists == true)
            }
    }

    func markMacraOnboardingComplete(completion: ((Error?) -> Void)? = nil) {
        updateMacraOwnedFields([
            "hasCompletedMacraOnboarding": true,
            "macraOnboardingCompletedAt": Date().timeIntervalSince1970,
            // Finishing Macra onboarding IS completing registration for this
            // account. The platform-wide `registrationComplete` flag (read by
            // web AuthWrapper, admin, and segmentation) was never written by
            // iOS, so every Macra-origin user looked half-registered. Promote
            // it here so the shared User doc matches reality.
            "registrationComplete": true,
        ]) { [weak self] error in
            if var cached = self?.user, error == nil {
                cached.hasCompletedMacraOnboarding = true
                cached.updatedAt = Date()
                self?.publish(cached)
            }
            completion?(error)
        }
    }

    func updateProfileImageURL(_ urlString: String, completion: ((Error?) -> Void)? = nil) {
        let trimmed = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "firebasestorage.googleapis.com:443", with: "firebasestorage.googleapis.com")
        guard !trimmed.isEmpty else {
            completion?(nil)
            return
        }

        updateRootUserPatch([
            "profileImageURL": trimmed,
            "profileImage.profileImageURL": trimmed,
        ]) { [weak self] error in
            if var cached = self?.user, error == nil {
                cached.profileImageURL = trimmed
                cached.updatedAt = Date()
                self?.publish(cached)
            }
            completion?(error)
        }
    }

    func updateBirthdate(_ birthdate: Date, completion: ((Error?) -> Void)? = nil) {
        guard birthdate.timeIntervalSince1970 > 0 else {
            completion?(nil)
            return
        }

        updateRootUserPatch([
            "birthdate": birthdate.timeIntervalSince1970,
        ]) { [weak self] error in
            if var cached = self?.user, error == nil {
                cached.birthdate = birthdate
                cached.updatedAt = Date()
                self?.publish(cached)
            }
            completion?(error)
        }
    }

    func grantLocalMacraBetaAccess() {
        UserDefaults.standard.set(true, forKey: Self.localBetaAccessKey)
        isBetaUser = true
        isSubscribed = true

        if var cached = user {
            cached.subscriptionType = .beta
            publish(cached)
        }

        updateMacraOwnedFields([
            "macra.betaAccess": true,
            "macra.betaAccessGrantedAt": Date().timeIntervalSince1970,
        ]) { error in
            if let error {
                print("Error saving Macra beta access marker: \(error.localizedDescription)")
            }
        }
    }

    func revokeLocalMacraBetaAccess() {
        UserDefaults.standard.removeObject(forKey: Self.localBetaAccessKey)

        if var cached = user, cached.subscriptionType == .beta {
            cached.subscriptionType = .free
            publish(cached)
        } else {
            DispatchQueue.main.async {
                self.isBetaUser = false
                if let cached = self.user {
                    self.isSubscribed = cached.subscriptionType.grantsMacraAccess
                } else {
                    self.isSubscribed = false
                }
            }
        }

        updateMacraOwnedFields([
            "macra.betaAccess": false,
            "macra.betaAccessRevokedAt": Date().timeIntervalSince1970,
        ]) { error in
            if let error {
                print("Error clearing Macra beta access marker: \(error.localizedDescription)")
            }
        }
    }

    func updateMacraOwnedFields(_ fields: [String: Any], completion: ((Error?) -> Void)? = nil) {
        var updates = fields
        updates["updatedAt"] = Date().timeIntervalSince1970
        updateRootUserPatch(updates, completion: completion)
    }

    /// Persists the resolved coach-assigned meal plan reference on the
    /// User doc so Macra knows which Pulse plan it has already adopted.
    /// On next launch we compare the saved reference against the live
    /// `oneOnOneTrainings` doc — if `attachedAt` (or `trainingId`)
    /// differs, we re-adopt automatically. Read by
    /// `CoachMealPlanReference(dictionary:)`.
    func saveCoachMealPlanReference(_ reference: CoachMealPlanReference,
                                    completion: ((Error?) -> Void)? = nil) {
        updateMacraOwnedFields([
            "coachMealPlanReference": reference.toDictionary(),
        ], completion: completion)
    }

    /// Reads the saved coach-plan reference. Returns nil when none has
    /// been adopted yet (fresh install / never had a coach plan).
    func loadCoachMealPlanReference(completion: @escaping (CoachMealPlanReference?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(nil)
            return
        }
        db.collection("users").document(userId).getDocument { snapshot, _ in
            let data = snapshot?.data() ?? [:]
            let reference = (data["coachMealPlanReference"] as? [String: Any])
                .flatMap(CoachMealPlanReference.init(dictionary:))
            DispatchQueue.main.async { completion(reference) }
        }
    }

    /// Persists Macra push notification preferences to the root user document.
    /// Server-side scheduled functions (admin notification sequences) read
    /// `macraNotificationPreferences` to decide whether to include this user.
    func saveMacraNotificationPreferences(_ preferences: MacraNotificationPreferences,
                                          completion: ((Error?) -> Void)? = nil) {
        updateMacraOwnedFields([
            "macraNotificationPreferences": preferences.toDictionary(),
        ], completion: completion)
    }

    /// Fetches Macra push + email preferences from the user doc. Returns
    /// default values if missing so callers can drive UI immediately.
    func loadMacraPreferences(completion: @escaping (MacraNotificationPreferences, MacraEmailPreferences) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.default, .default)
            return
        }

        db.collection("users").document(userId).getDocument { snapshot, _ in
            let data = snapshot?.data() ?? [:]
            let push = MacraNotificationPreferences.fromDictionary(data["macraNotificationPreferences"] as? [String: Any])
            let email = MacraEmailPreferences.fromDictionary(data["macraEmailPreferences"] as? [String: Any])
            DispatchQueue.main.async {
                completion(push, email)
            }
        }
    }

    /// Persists Macra email preferences (tips series, inactivity winback) alongside the push prefs.
    func saveMacraEmailPreferences(_ preferences: MacraEmailPreferences,
                                   completion: ((Error?) -> Void)? = nil) {
        updateMacraOwnedFields([
            "macraEmailPreferences": preferences.toDictionary(),
        ], completion: completion)
    }

    /// Fires the Macra welcome email via the QuickLifts-Web netlify function.
    /// Server-side idempotency (`macraWelcomeEmailSentAt` on the user doc)
    /// guarantees we don't spam the user if this is called more than once.
    func sendMacraWelcomeEmail() {
        guard let user = Auth.auth().currentUser,
              let email = user.email, !email.isEmpty else { return }

        let userId = user.uid
        let firstName = user.displayName?
            .split(separator: " ")
            .first
            .map(String.init) ?? ""

        let base = ConfigManager.shared.getWebsiteBaseURL()
        guard let url = URL(string: "\(base)/.netlify/functions/send-macra-welcome-email") else { return }

        let body: [String: Any] = [
            "userId": userId,
            "toEmail": email,
            "firstName": firstName,
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                print("sendMacraWelcomeEmail error: \(error.localizedDescription)")
            }
        }.resume()
    }

    private func updateRootUserPatch(_ fields: [String: Any], completion: ((Error?) -> Void)? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion?(nil)
            return
        }

        let userRef = db.collection("users").document(userId)
        userRef.updateData(fields) { error in
            if let error = error {
                print("Error patching user document: \(error.localizedDescription)")
                completion?(error)
            } else {
                completion?(nil)
            }
        }
    }

    private func publish(_ updatedUser: User) {
        DispatchQueue.main.async {
            self.user = updatedUser
            self.isBetaUser = updatedUser.subscriptionType == .beta || UserDefaults.standard.bool(forKey: Self.localBetaAccessKey)
            self.isSubscribed = updatedUser.subscriptionType.grantsMacraAccess || self.isBetaUser
        }
    }
}
