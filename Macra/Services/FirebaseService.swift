import Firebase
import FirebaseFirestore
import FirebaseStorage
import AuthenticationServices
import UIKit

enum FirebaseError: Error {
    case invalidCredentials
    case emailAlreadyInUse
    case unknownError
}

class FirebaseService: NSObject  {
    static let sharedInstance = FirebaseService()
    private var db: Firestore!
    var currentAuthorizationController: ASAuthorizationController?

    private enum SharedPulseFirebaseConfig {
        static let googleAppID = "1:691046627244:ios:821c53e53f20c736a9ec09"
        static let gcmSenderID = "691046627244"
        static let apiKey = "AIzaSyCBNr8WylRpi7IZ5M_COy1E3LaStQgLMvk"
        static let projectID = "quicklifts-dd3f1"
        static let storageBucket = "quicklifts-dd3f1.appspot.com"
        static let clientID = "691046627244-mhqr0bau64lqouvp5ralgv0ehubsno3d.apps.googleusercontent.com"
    }

    private override init() {
        super.init()
        Self.configureFirebaseAppIfNeeded()
        db = Firestore.firestore()

        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        db.settings = settings
    }

    static func configureFirebaseAppIfNeeded() {
        guard FirebaseApp.app() == nil else { return }

        let options = FirebaseOptions(
            googleAppID: SharedPulseFirebaseConfig.googleAppID,
            gcmSenderID: SharedPulseFirebaseConfig.gcmSenderID
        )
        options.apiKey = SharedPulseFirebaseConfig.apiKey
        options.projectID = SharedPulseFirebaseConfig.projectID
        options.storageBucket = SharedPulseFirebaseConfig.storageBucket
        options.clientID = SharedPulseFirebaseConfig.clientID
        options.bundleID = Bundle.main.bundleIdentifier ?? "Tremaine.Macra"

        FirebaseApp.configure(options: options)
        print("[Firebase] Configured shared Pulse project \(SharedPulseFirebaseConfig.projectID) for bundle \(options.bundleID)")
    }
    
    var isAuthenticated: Bool {
        guard (Auth.auth().currentUser?.uid) != nil else {
            return false
        }
        
        return true
    }
    
    func signInAnonymously(completion: @escaping (AuthDataResult?, Error?) -> Void) {
        Auth.auth().signInAnonymously(completion: completion)
    }
    
    func signInWithEmailAndPassword(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { (authResult, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let authResult = authResult else {
                completion(.failure(FirebaseError.unknownError))
                return
            }
            
            let uid = authResult.user.uid
            
            self.db.collection("users").document(uid).getDocument { (snapshot, error) in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = snapshot?.data(),
                      let user = User(id: snapshot?.documentID ?? "", dictionary: data) else {
                          completion(.failure(FirebaseError.unknownError))
                          return
                }
                
                completion(.success(user))
            }
        }
    }
    
    func signUpWithEmailAndPassword(email: String, password: String, completion: @escaping (Result<AuthDataResult, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { (authResult, error) in
            if let error = error {
                completion(.failure(error))
            } else if let authResult = authResult {
                self.createUserObject(registrationEntryPoint: .macra)
                completion(.success(authResult))
            } else {
                // This case should never occur, but handle it anyway
                completion(.failure(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"])))
            }
        }
    }
    
    func signInWithApple(idTokenString: String, completion: @escaping (Result<AuthDataResult, Error>) -> Void) {
        let credential = OAuthProvider.credential(withProviderID: "apple.com", idToken: idTokenString, rawNonce: nil)
        Auth.auth().signIn(with: credential) { (authResult, error) in
            if let error = error {
                completion(.failure(error))
            } else if let authResult = authResult {
                if authResult.additionalUserInfo?.isNewUser == true {
                    self.createUserObject(registrationEntryPoint: .macra)
                }
                completion(.success(authResult))
            } else {
                completion(.failure(NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"])))
            }
        }
    }

    func deleteAccount(completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(.failure(FirebaseError.unknownError))
            return
        }
        
        // Delete user's authentication
        user.delete { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(true))
            }
        }
    }
    
    func uploadImage(_ image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard let data = image.jpegData(compressionQuality: 0.6),
              let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data or user id"])))
            return
        }

        let storageRef = Storage.storage().reference().child(userId).child("profile_images").child("images").child("\(userId).jpg")
        storageRef.putData(data, metadata: nil) { (_, error) in
            if let error = error {
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { (url, error) in
                if let error = error {
                    completion(.failure(error))
                } else if let url = url {
                    completion(.success(url.absoluteString))
                }
            }
        }
    }

    func uploadMealImage(_ image: UIImage, mealId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let data = image.jpegData(compressionQuality: 0.6),
              let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data or user id"])))
            return
        }

        let fileName = mealId.isEmpty ? UUID().uuidString : mealId
        let storageRef = Storage.storage().reference()
            .child("meal_images")
            .child(userId)
            .child("\(fileName)-\(Int(Date().timeIntervalSince1970)).jpg")

        storageRef.putData(data, metadata: nil) { _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                } else if let url = url {
                    completion(.success(url.absoluteString))
                } else {
                    completion(.failure(NSError(domain: "FirebaseService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing download URL"])))
                }
            }
        }
    }
    
    let imageCache = NSCache<NSURL, UIImage>()

    func image(from url: URL, completion: @escaping (UIImage?) -> Void) {
        if let cachedImage = imageCache.object(forKey: url as NSURL) {
            completion(cachedImage)
        } else {
            URLSession.shared.dataTask(with: url) { [weak self] (data, response, error) in
                if let error = error {
                    print("Failed to load image with error: \(error.localizedDescription)")
                    completion(nil)
                } else if let data = data, let image = UIImage(data: data) {
                    self?.imageCache.setObject(image, forKey: url as NSURL)
                    completion(image)
                }
            }.resume()
        }
    }

    func fetchImage(with url: String, completion: @escaping (Result<UIImage, Error>) -> Void) {
        let url = URL(string: url)
        URLSession.shared.dataTask(with: url!) { (data, response, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let data = data {
                if let image = UIImage(data: data) {
                    completion(.success(image))
                } else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert data to image"])))
                }
            }
        }.resume()
    }
    
    func createUserObject(registrationEntryPoint: RegistrationEntryPoint = .macra) {
        // Create a user object when a person first opens the app.
        guard let userId = Auth.auth().currentUser?.uid else {
            return
        }
        
        guard let email = Auth.auth().currentUser?.email else {
            return
        }
        
        let userRef = db.collection("users").document(userId)
        
        // Check if user document already exists
        userRef.getDocument { (document, error) in
            if let error = error {
                print("Error getting user document: \(error.localizedDescription)")
                return
            }
            
            guard let document = document, !document.exists else {
                if let existingData = document?.data(),
                   let existingUser = User(id: document?.documentID ?? userId, dictionary: existingData) {
                    DispatchQueue.main.async {
                        UserService.sharedInstance.user = existingUser
                        UserService.sharedInstance.isBetaUser = existingUser.subscriptionType == .beta || UserService.sharedInstance.isBetaUser
                        UserService.sharedInstance.isSubscribed = existingUser.subscriptionType.grantsMacraAccess || UserService.sharedInstance.isBetaUser
                    }
                }
                print("User document already exists; Macra loaded existing shared profile without writing a partial user document")
                return
            }
            
            let seedData: [String: Any] = [
                "id": userId,
                "email": email,
                "registrationEntryPoint": registrationEntryPoint.rawValue,
                "createdAt": Date().timeIntervalSince1970,
                "updatedAt": Date().timeIntervalSince1970,
            ]

            // Create-only user seed. Existing shared profiles must never be overwritten by Macra.
            self.db.runTransaction({ transaction, errorPointer -> Any? in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                guard !snapshot.exists else {
                    errorPointer?.pointee = NSError(
                        domain: "Macra.FirebaseService",
                        code: 409,
                        userInfo: [NSLocalizedDescriptionKey: "User document already exists"]
                    )
                    return nil
                }

                transaction.setData(seedData, forDocument: userRef)
                return nil
            }) { _, error in
                if let error = error {
                    print("Error creating user document: \(error.localizedDescription)")
                } else {
                    print("User document created successfully")
                }
            }
        }
    }

    func changePassword(oldPassword: String, newPassword: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let currentUser = Auth.auth().currentUser, let email = currentUser.email else {
            completion(.failure(FirebaseError.unknownError))
            return
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: oldPassword)
        
        currentUser.reauthenticate(with: credential) { (_, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            currentUser.updatePassword(to: newPassword) { (error) in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                completion(.success(true))
            }
        }
    }

   func signOut() throws {
       try Auth.auth().signOut()
   }
    
}
