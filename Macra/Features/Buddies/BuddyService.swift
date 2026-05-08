import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Buddy-feature persistence layer. All Firestore reads/writes for the
/// follow graph + invite tokens funnel through here so the UI never
/// touches Firestore directly.
///
/// Data layout:
/// - `users/{followerUid}/buddies/{targetUid}` — one doc per follow.
/// - `macraBuddyInvites/{token}` — pending/used invite tokens (doc id
///   IS the token, so reading by id == "look up an invite by its
///   secret"). Existing Firestore rules' permissive fallback covers
///   reads; phase-3 will restrict to authed users.
final class BuddyService {
    static let sharedInstance = BuddyService()

    private let db = Firestore.firestore()

    private static let buddiesSubpath = "buddies"
    private static let invitesCollection = "macraBuddyInvites"

    private init() {}

    // MARK: - Invite preview

    /// Resolves a deep-link token into a presentation-ready invite preview
    /// without creating the follow relationship. This lets the receiver see
    /// who is sharing and a small taste of recent logging before accepting.
    func previewInvite(token: String, completion: @escaping (Result<BuddyInvitePreview, Error>) -> Void) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            completion(.failure(BuddyError.malformedURL))
            return
        }

        let inviteRef = db.collection(Self.invitesCollection).document(trimmedToken)
        inviteRef.getDocument { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            guard let data = snapshot?.data(),
                  let invite = BuddyInvite(dictionary: data, id: trimmedToken) else {
                completion(.failure(BuddyError.inviteNotFound))
                return
            }
            if invite.isExpired {
                completion(.failure(BuddyError.inviteExpired))
                return
            }

            let group = DispatchGroup()
            var profile: ProfileSnapshot?
            var recentMeals: [Meal] = []

            group.enter()
            self.fetchUserProfile(uid: invite.inviterUid) { result in
                profile = result
                group.leave()
            }

            group.enter()
            MealService.sharedInstance.getRecentMeals(userId: invite.inviterUid, limit: 6) { result in
                if case .success(let meals) = result {
                    recentMeals = meals
                }
                group.leave()
            }

            group.notify(queue: .main) {
                let preview = BuddyInvitePreview(
                    token: trimmedToken,
                    inviterUid: invite.inviterUid,
                    inviterEmail: profile?.email ?? invite.inviterEmail,
                    inviterUsername: profile?.username ?? invite.inviterUsername,
                    inviterProfileImageURL: profile?.profileImageURL ?? invite.inviterProfileImageURL,
                    recentMeals: recentMeals
                )
                completion(.success(preview))
            }
        }
    }

    // MARK: - Generate invite

    /// Creates a fresh invite token owned by the signed-in user. Snapshots
    /// the inviter's email + profile photo onto the invite doc so the
    /// recipient can see who invited them before accepting (phase-2).
    /// Returns the persisted `BuddyInvite` (or an error).
    func createInvite(completion: @escaping (Result<BuddyInvite, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion(.failure(BuddyError.notSignedIn))
            return
        }
        let inviterEmail = UserService.sharedInstance.user?.email ?? Auth.auth().currentUser?.email
        let inviterUsername = Self.resolveCurrentUsername(email: inviterEmail)
        let inviterProfileImageURL = UserService.sharedInstance.user?.profileImageURL

        let invite = BuddyInvite(
            inviterUid: uid,
            inviterEmail: inviterEmail,
            inviterUsername: inviterUsername,
            inviterProfileImageURL: inviterProfileImageURL
        )

        let ref = db.collection(Self.invitesCollection).document(invite.id)
        ref.setData(invite.toDictionary()) { error in
            if let error {
                print("[Macra][BuddyService.createInvite] ❌ \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            print("[Macra][BuddyService.createInvite] ✓ token=\(invite.id) for inviter=\(uid)")
            completion(.success(invite))
        }
    }

    // MARK: - Accept invite

    /// Looks up an invite by token, validates it (not expired, not the
    /// inviter themselves, not already following), and writes the
    /// follow record at `users/{follower}/buddies/{inviter}`. The
    /// invite's `usedCount` is bumped atomically.
    func acceptInvite(token: String, completion: @escaping (Result<BuddyConnection, Error>) -> Void) {
        guard let followerUid = Auth.auth().currentUser?.uid, !followerUid.isEmpty else {
            completion(.failure(BuddyError.notSignedIn))
            return
        }

        let inviteRef = db.collection(Self.invitesCollection).document(token)
        inviteRef.getDocument { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            guard let data = snapshot?.data(),
                  let invite = BuddyInvite(dictionary: data, id: token) else {
                completion(.failure(BuddyError.inviteNotFound))
                return
            }

            if invite.isExpired {
                completion(.failure(BuddyError.inviteExpired))
                return
            }
            if invite.inviterUid == followerUid {
                completion(.failure(BuddyError.selfInvite))
                return
            }

            // Resolve the target's freshest profile snapshot before
            // writing the buddy record. The invite has cached fields,
            // but the target's user doc is more authoritative.
            self.fetchUserProfile(uid: invite.inviterUid) { profile in
                let targetEmail = profile?.email ?? invite.inviterEmail
                let targetUsername = profile?.username ?? invite.inviterUsername
                let targetProfileImageURL = profile?.profileImageURL ?? invite.inviterProfileImageURL

                let connection = BuddyConnection(
                    targetUid: invite.inviterUid,
                    targetEmail: targetEmail,
                    targetUsername: targetUsername,
                    targetProfileImageURL: targetProfileImageURL
                )

                let buddyRef = self.db
                    .collection("users").document(followerUid)
                    .collection(Self.buddiesSubpath).document(invite.inviterUid)

                // Pre-check so we surface a friendlier "already following"
                // error instead of silently overwriting.
                buddyRef.getDocument { existing, _ in
                    if existing?.exists == true {
                        completion(.failure(BuddyError.alreadyFollowing))
                        return
                    }
                    buddyRef.setData(connection.toDictionary()) { error in
                        if let error {
                            print("[Macra][BuddyService.acceptInvite] ❌ write buddy: \(error.localizedDescription)")
                            completion(.failure(error))
                            return
                        }
                        // Bump the invite usage counter; this is best-effort —
                        // failure here doesn't unwind the buddy write.
                        inviteRef.updateData(["usedCount": FieldValue.increment(Int64(1))]) { _ in }
                        print("[Macra][BuddyService.acceptInvite] ✓ \(followerUid) now follows \(invite.inviterUid)")
                        completion(.success(connection))
                    }
                }
            }
        }
    }

    // MARK: - List buddies

    /// Snapshot listener so the buddies sheet updates in real time when
    /// the user accepts new invites or unfollows.
    func observeBuddies(handler: @escaping (Result<[BuddyConnection], Error>) -> Void) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            handler(.failure(BuddyError.notSignedIn))
            return nil
        }
        let ref = db.collection("users").document(uid).collection(Self.buddiesSubpath)
        return ref.addSnapshotListener { snapshot, error in
            if let error {
                handler(.failure(error))
                return
            }
            let buddies: [BuddyConnection] = (snapshot?.documents ?? [])
                .compactMap { BuddyConnection(dictionary: $0.data()) }
                .sorted { $0.createdAt > $1.createdAt }
            handler(.success(buddies))
        }
    }

    // MARK: - List followers

    /// Snapshot listener for *people who follow me*. The buddy graph is
    /// stored from the follower's side (`users/{follower}/buddies/{me}`),
    /// so we use a collection-group query on `buddies` with
    /// `targetUid == me` and lift each follower's uid from the parent
    /// path. Their profile (email + photo) is fetched per result from
    /// `users/{followerUid}`.
    ///
    /// **Firestore requirement:** this query needs a single-field index
    /// exemption with `COLLECTION_GROUP` scope on `buddies.targetUid`
    /// (added via `fieldOverrides` in `firestore.indexes.json`). Without
    /// it, the listener will fail with a "missing index" error and the
    /// console will surface a one-click create link.
    func observeFollowers(handler: @escaping (Result<[BuddyFollower], Error>) -> Void) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            handler(.failure(BuddyError.notSignedIn))
            return nil
        }
        let query = db.collectionGroup(Self.buddiesSubpath)
            .whereField("targetUid", isEqualTo: uid)

        return query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                print("[Macra][BuddyService.observeFollowers] ❌ \(error.localizedDescription)")
                handler(.failure(error))
                return
            }

            let docs = snapshot?.documents ?? []
            let entries: [(uid: String, createdAt: Date)] = docs.compactMap { doc in
                guard let followerUid = doc.reference.parent.parent?.documentID,
                      !followerUid.isEmpty,
                      followerUid != uid else { // exclude self-paranoia
                    return nil
                }
                let createdAt: Date = (doc.data()["createdAt"] as? Double)
                    .map { Date(timeIntervalSince1970: $0) } ?? Date()
                return (uid: followerUid, createdAt: createdAt)
            }

            guard !entries.isEmpty else {
                DispatchQueue.main.async { handler(.success([])) }
                return
            }

            // Resolve each follower's profile in parallel. With a small
            // follower count this is fine; if it grows large we can cache
            // by uid keyed off the listener instance.
            let group = DispatchGroup()
            var followers: [BuddyFollower] = []
            let lock = NSLock()

            for entry in entries {
                group.enter()
                self.fetchUserProfile(uid: entry.uid) { profile in
                    let follower = BuddyFollower(
                        followerUid: entry.uid,
                        followerEmail: profile?.email,
                        followerUsername: profile?.username,
                        followerProfileImageURL: profile?.profileImageURL,
                        createdAt: entry.createdAt
                    )
                    lock.lock()
                    followers.append(follower)
                    lock.unlock()
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                let sorted = followers.sorted { $0.createdAt > $1.createdAt }
                handler(.success(sorted))
            }
        }
    }

    private static let requestsSubpath = "buddyRequests"

    // MARK: - Share-back requests

    /// Sends a "share your meals with me" request to another user. Writes
    /// `users/{targetUid}/buddyRequests/{me}` — doc id is my uid so a
    /// repeat tap is idempotent (overwrites the same doc, recipient sees
    /// no spam). The recipient's incoming-requests listener picks it up
    /// and they choose to accept or decline.
    func requestShareBack(targetUid: String, completion: @escaping (Result<BuddyShareRequest, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion(.failure(BuddyError.notSignedIn))
            return
        }
        guard targetUid != uid else {
            completion(.failure(BuddyError.selfInvite))
            return
        }

        let myEmail = UserService.sharedInstance.user?.email ?? Auth.auth().currentUser?.email
        let myUsername = Self.resolveCurrentUsername(email: myEmail)
        let myProfileImageURL = UserService.sharedInstance.user?.profileImageURL

        let request = BuddyShareRequest(
            fromUid: uid,
            fromEmail: myEmail,
            fromUsername: myUsername,
            fromProfileImageURL: myProfileImageURL,
            toUid: targetUid
        )

        let ref = db.collection("users").document(targetUid)
            .collection(Self.requestsSubpath).document(uid)
        ref.setData(request.toDictionary()) { error in
            if let error {
                print("[Macra][BuddyService.requestShareBack] ❌ \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            print("[Macra][BuddyService.requestShareBack] ✓ \(uid) → \(targetUid)")
            completion(.success(request))
        }
    }

    /// Withdraws a pending outgoing request the user previously sent.
    /// Useful when the recipient hasn't responded and the sender changes
    /// their mind.
    func withdrawShareRequest(targetUid: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion(.failure(BuddyError.notSignedIn))
            return
        }
        let ref = db.collection("users").document(targetUid)
            .collection(Self.requestsSubpath).document(uid)
        ref.delete { error in
            if let error {
                completion(.failure(error))
                return
            }
            completion(.success(()))
        }
    }

    /// Listener for incoming requests — other people asking me to share
    /// my journal with them.
    func observeIncomingRequests(handler: @escaping (Result<[BuddyShareRequest], Error>) -> Void) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            handler(.failure(BuddyError.notSignedIn))
            return nil
        }
        let ref = db.collection("users").document(uid).collection(Self.requestsSubpath)
        return ref.addSnapshotListener { snapshot, error in
            if let error {
                handler(.failure(error))
                return
            }
            let requests: [BuddyShareRequest] = (snapshot?.documents ?? [])
                .compactMap { BuddyShareRequest(dictionary: $0.data(), id: $0.documentID) }
                .sorted { $0.createdAt > $1.createdAt }
            handler(.success(requests))
        }
    }

    /// Listener for *uids I've sent requests to* — drives the "Requested"
    /// pill on the followers list. Uses a collection-group query so we
    /// don't have to mirror the request on the sender side.
    ///
    /// **Firestore requirement:** needs a `COLLECTION_GROUP` field
    /// override on `buddyRequests.fromUid` (sibling of the existing
    /// `buddies.targetUid` override). Without it the listener errors on
    /// first run with a one-click "create index" link.
    func observeOutgoingRequests(handler: @escaping (Result<Set<String>, Error>) -> Void) -> ListenerRegistration? {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            handler(.failure(BuddyError.notSignedIn))
            return nil
        }
        let query = db.collectionGroup(Self.requestsSubpath)
            .whereField("fromUid", isEqualTo: uid)
        return query.addSnapshotListener { snapshot, error in
            if let error {
                print("[Macra][BuddyService.observeOutgoingRequests] ❌ \(error.localizedDescription)")
                handler(.failure(error))
                return
            }
            let recipientUids: Set<String> = Set(
                (snapshot?.documents ?? [])
                    .compactMap { $0.data()["toUid"] as? String }
            )
            handler(.success(recipientUids))
        }
    }

    /// Recipient-side accept. Atomically writes the buddy doc onto the
    /// requester's path (granting them visibility into my meals) and
    /// removes the now-resolved request from my inbox. The requester's
    /// `observeBuddies` listener picks up the new buddy on their device
    /// and the row flips to "Mutual".
    func acceptShareRequest(_ request: BuddyShareRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion(.failure(BuddyError.notSignedIn))
            return
        }
        guard uid == request.toUid else {
            // Defensive: only the request's recipient can accept it.
            completion(.failure(BuddyError.notSignedIn))
            return
        }

        let myEmail = UserService.sharedInstance.user?.email ?? Auth.auth().currentUser?.email
        let myUsername = Self.resolveCurrentUsername(email: myEmail)
        let myProfileImageURL = UserService.sharedInstance.user?.profileImageURL

        let connection = BuddyConnection(
            targetUid: uid,
            targetEmail: myEmail,
            targetUsername: myUsername,
            targetProfileImageURL: myProfileImageURL
        )

        let buddyRef = db.collection("users").document(request.fromUid)
            .collection(Self.buddiesSubpath).document(uid)
        let requestRef = db.collection("users").document(uid)
            .collection(Self.requestsSubpath).document(request.fromUid)

        let batch = db.batch()
        batch.setData(connection.toDictionary(), forDocument: buddyRef)
        batch.deleteDocument(requestRef)
        batch.commit { error in
            if let error {
                print("[Macra][BuddyService.acceptShareRequest] ❌ \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            print("[Macra][BuddyService.acceptShareRequest] ✓ \(uid) granted \(request.fromUid)")
            completion(.success(()))
        }
    }

    /// Recipient-side decline. Just deletes the request — no buddy doc
    /// is created. The sender's outgoing-requests listener re-emits and
    /// the "Requested" pill reverts to "Request to share back".
    func declineShareRequest(_ request: BuddyShareRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion(.failure(BuddyError.notSignedIn))
            return
        }
        guard uid == request.toUid else {
            completion(.failure(BuddyError.notSignedIn))
            return
        }
        let ref = db.collection("users").document(uid)
            .collection(Self.requestsSubpath).document(request.fromUid)
        ref.delete { error in
            if let error {
                completion(.failure(error))
                return
            }
            completion(.success(()))
        }
    }

    // MARK: - Unfollow

    /// Hard-deletes the `users/{me}/buddies/{target}` doc. The target
    /// isn't notified — they don't track who's following them.
    func unfollow(targetUid: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion(.failure(BuddyError.notSignedIn))
            return
        }
        let ref = db.collection("users").document(uid)
            .collection(Self.buddiesSubpath).document(targetUid)
        ref.delete { error in
            if let error {
                print("[Macra][BuddyService.unfollow] ❌ \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            print("[Macra][BuddyService.unfollow] ✓ \(uid) no longer follows \(targetUid)")
            completion(.success(()))
        }
    }

    // MARK: - Revoke share

    /// Stops sharing my journal with someone who's currently following me.
    /// Deletes `users/{follower}/buddies/{me}` — the doc lives at the
    /// follower's path, but it's keyed by *me* so I'm only ever revoking
    /// access to my own data. Their `observeBuddies` listener on their
    /// device will re-emit and the row vanishes from their list.
    func revokeShare(followerUid: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion(.failure(BuddyError.notSignedIn))
            return
        }
        let ref = db.collection("users").document(followerUid)
            .collection(Self.buddiesSubpath).document(uid)
        ref.delete { error in
            if let error {
                print("[Macra][BuddyService.revokeShare] ❌ \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            print("[Macra][BuddyService.revokeShare] ✓ \(uid) revoked \(followerUid)'s access")
            completion(.success(()))
        }
    }

    // MARK: - Helpers

    /// Best-effort current-user username for snapshotting onto outgoing
    /// buddy/invite/request docs. Prefers the live `User.username`
    /// (FWP-authoritative or backfilled by `UserService` on load), and
    /// falls back to the email localpart if the user object is somehow
    /// available without a persisted handle (shouldn't happen post-
    /// backfill but kept defensively).
    static func resolveCurrentUsername(email: String?) -> String? {
        if let live = UserService.sharedInstance.user?.username,
           !live.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return live
        }
        if let email, !email.isEmpty {
            return User.emailLocalpart(email)
        }
        return nil
    }

    private struct ProfileSnapshot {
        let email: String?
        let username: String?
        let profileImageURL: String?
    }

    /// Fetch a slim profile from `users/{uid}` for the buddy snapshot.
    /// Returns nil if the doc doesn't exist or is unreadable — we fall
    /// back to whatever the invite cached.
    private func fetchUserProfile(uid: String, completion: @escaping (ProfileSnapshot?) -> Void) {
        db.collection("users").document(uid).getDocument { snapshot, _ in
            guard let data = snapshot?.data() else {
                completion(nil)
                return
            }
            let email = data["email"] as? String
            // FWP-authoritative handle. Empty for Macra-only accounts
            // until UserService backfills it on next sign-in — callers
            // that need a display string should fall back to the email
            // localpart when this is missing.
            let username = (data["username"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // The User model normalizes profileImageURL across legacy
            // shapes (line 82–94 in User.swift) — replicate the most
            // common keys here without pulling that whole struct in.
            let profileImageURL = (data["profileImageURL"] as? String)
                ?? (data["photoURL"] as? String)
                ?? (data["avatarURL"] as? String)
            completion(ProfileSnapshot(
                email: email,
                username: (username?.isEmpty == false) ? username : nil,
                profileImageURL: profileImageURL
            ))
        }
    }
}
