import Foundation
import Firebase
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
            guard let user = User(id: document.documentID, dictionary: userData) else {
                completion(nil, nil)
                return
            }

            DispatchQueue.main.async {
                self.user = user
                self.isBetaUser = user.subscriptionType == .beta || UserDefaults.standard.bool(forKey: Self.localBetaAccessKey)
                self.isSubscribed = user.subscriptionType.grantsMacraAccess || self.isBetaUser
                completion(user, nil)
            }
        }
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

    func updateMacraOwnedFields(_ fields: [String: Any], completion: ((Error?) -> Void)? = nil) {
        var updates = fields
        updates["updatedAt"] = Date().timeIntervalSince1970
        updateRootUserPatch(updates, completion: completion)
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
