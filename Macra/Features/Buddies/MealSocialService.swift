import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Persistence layer for meal likes + comments. Both subcollections live
/// under the meal's own doc — `users/{ownerUid}/mealLogs/{mealId}/likes`
/// and `.../comments` — so reads scope to a single meal cleanly without
/// any composite indexes. Used from both the buddy day-view's tap-to-open
/// detail sheet and the owner's own meal-log detail view, so the same
/// likes/comments are visible no matter which side opens the meal.
final class MealSocialService {
    static let sharedInstance = MealSocialService()

    private let db = Firestore.firestore()

    private static let usersCollection = "users"
    private static let mealLogsCollection = "mealLogs"
    private static let likesSubpath = "likes"
    private static let commentsSubpath = "comments"

    private init() {}

    // MARK: - Likes

    /// Live snapshot of every like on a meal. Sorted newest-first so the
    /// "X others" heuristics in the UI read intuitively.
    func observeLikes(ownerUid: String, mealId: String, handler: @escaping (Result<[MealLike], Error>) -> Void) -> ListenerRegistration? {
        guard !ownerUid.isEmpty, !mealId.isEmpty else {
            handler(.success([]))
            return nil
        }
        let ref = mealRef(ownerUid: ownerUid, mealId: mealId)
            .collection(Self.likesSubpath)
        return ref.addSnapshotListener { snapshot, error in
            if let error {
                handler(.failure(error))
                return
            }
            let likes: [MealLike] = (snapshot?.documents ?? [])
                .compactMap { MealLike(dictionary: $0.data(), id: $0.documentID) }
                .sorted { $0.createdAt > $1.createdAt }
            handler(.success(likes))
        }
    }

    /// Toggles the current user's like on a meal. Doc id is the liker's
    /// uid so this is idempotent: a re-like on a stale UI is a no-op
    /// overwrite, an unlike on a no-longer-existing doc is a no-op delete.
    func toggleLike(ownerUid: String, mealId: String, currentlyLiked: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion(.failure(NSError(domain: "MealSocial", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sign in to like meals."])))
            return
        }

        let likeRef = mealRef(ownerUid: ownerUid, mealId: mealId)
            .collection(Self.likesSubpath).document(uid)

        let mealDoc = mealRef(ownerUid: ownerUid, mealId: mealId)

        if currentlyLiked {
            likeRef.delete { [weak self] error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.bumpAggregateCounter(mealDoc: mealDoc, field: "likeCount", by: -1)
                completion(.success(()))
            }
        } else {
            let myEmail = UserService.sharedInstance.user?.email ?? Auth.auth().currentUser?.email
            let myUsername = BuddyService.resolveCurrentUsername(email: myEmail)
            let myProfileImageURL = UserService.sharedInstance.user?.profileImageURL
            let like = MealLike(
                likerUid: uid,
                likerEmail: myEmail,
                likerUsername: myUsername,
                likerProfileImageURL: myProfileImageURL
            )
            likeRef.setData(like.toDictionary()) { [weak self] error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.bumpAggregateCounter(mealDoc: mealDoc, field: "likeCount", by: 1)
                completion(.success(()))
            }
        }
    }

    // MARK: - Comments

    /// Live snapshot of every comment on a meal. Sorted oldest-first so
    /// the thread reads as a conversation top-to-bottom.
    func observeComments(ownerUid: String, mealId: String, handler: @escaping (Result<[MealComment], Error>) -> Void) -> ListenerRegistration? {
        guard !ownerUid.isEmpty, !mealId.isEmpty else {
            handler(.success([]))
            return nil
        }
        let ref = mealRef(ownerUid: ownerUid, mealId: mealId)
            .collection(Self.commentsSubpath)
        return ref.addSnapshotListener { snapshot, error in
            if let error {
                handler(.failure(error))
                return
            }
            let comments: [MealComment] = (snapshot?.documents ?? [])
                .compactMap { MealComment(dictionary: $0.data(), id: $0.documentID) }
                .sorted { $0.createdAt < $1.createdAt }
            handler(.success(comments))
        }
    }

    /// Posts a comment on a meal. Author profile is snapshotted at write
    /// time so the row renders without a follow-up `users/{authorUid}` fetch.
    func addComment(ownerUid: String, mealId: String, text: String, completion: @escaping (Result<MealComment, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion(.failure(NSError(domain: "MealSocial", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sign in to comment."])))
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "MealSocial", code: 400, userInfo: [NSLocalizedDescriptionKey: "Comment can't be empty."])))
            return
        }

        let myEmail = UserService.sharedInstance.user?.email ?? Auth.auth().currentUser?.email
        let myUsername = BuddyService.resolveCurrentUsername(email: myEmail)
        let myProfileImageURL = UserService.sharedInstance.user?.profileImageURL
        let commentsRef = mealRef(ownerUid: ownerUid, mealId: mealId)
            .collection(Self.commentsSubpath)
        let docRef = commentsRef.document()

        let comment = MealComment(
            id: docRef.documentID,
            authorUid: uid,
            authorEmail: myEmail,
            authorUsername: myUsername,
            authorProfileImageURL: myProfileImageURL,
            text: trimmed
        )
        let mealDoc = mealRef(ownerUid: ownerUid, mealId: mealId)
        docRef.setData(comment.toDictionary()) { [weak self] error in
            if let error {
                completion(.failure(error))
                return
            }
            self?.bumpAggregateCounter(mealDoc: mealDoc, field: "commentCount", by: 1)
            completion(.success(comment))
        }
    }

    /// Deletes a comment. Caller is expected to have already verified
    /// authorship; the rules fallback permits arbitrary deletes today,
    /// so the UI is the only gate for now.
    func deleteComment(ownerUid: String, mealId: String, commentId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !commentId.isEmpty else {
            completion(.success(()))
            return
        }
        let ref = mealRef(ownerUid: ownerUid, mealId: mealId)
            .collection(Self.commentsSubpath).document(commentId)
        let mealDoc = mealRef(ownerUid: ownerUid, mealId: mealId)
        ref.delete { [weak self] error in
            if let error {
                completion(.failure(error))
                return
            }
            self?.bumpAggregateCounter(mealDoc: mealDoc, field: "commentCount", by: -1)
            completion(.success(()))
        }
    }

    // MARK: - Helpers

    private func mealRef(ownerUid: String, mealId: String) -> DocumentReference {
        db.collection(Self.usersCollection).document(ownerUid)
            .collection(Self.mealLogsCollection).document(mealId)
    }

    /// Best-effort denormalized counter update. Failure is logged but
    /// never bubbled to the caller — the source-of-truth subcollection
    /// has already been written, and the next backfill / re-render reads
    /// from the listener anyway. Keeping this fire-and-forget avoids
    /// blocking the UI for an aggregate that's purely cosmetic.
    private func bumpAggregateCounter(mealDoc: DocumentReference, field: String, by delta: Int) {
        mealDoc.updateData([field: FieldValue.increment(Int64(delta))]) { error in
            if let error {
                print("[Macra][MealSocialService] aggregate \(field) bump (\(delta)) failed: \(error.localizedDescription)")
            }
        }
    }

    /// Self-heals the denormalized `likeCount` / `commentCount` fields on
    /// a meal doc to match the actual subcollection size. Called from
    /// `MealSocialViewModel.start()` once per session — catches legacy
    /// likes/comments that were written before the counter bump existed,
    /// or any drift caused by a failed `FieldValue.increment` write. Uses
    /// `setData(merge:)` so the field is created if missing.
    func reconcileMealCount(ownerUid: String, mealId: String, field: String, count: Int) {
        guard !ownerUid.isEmpty, !mealId.isEmpty else { return }
        let ref = mealRef(ownerUid: ownerUid, mealId: mealId)
        ref.setData([field: count], merge: true) { error in
            if let error {
                print("[Macra][MealSocialService] reconcile \(field)=\(count) failed: \(error.localizedDescription)")
            }
        }
    }
}
