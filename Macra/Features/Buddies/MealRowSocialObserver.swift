import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Per-row live counts for the journal's meal cards. Listens directly to
/// the meal's `likes` and `comments` subcollections so the heart and
/// bubble indicators reflect the actual size in real time — no reliance
/// on the denormalized counter fields, no caching window, works on any
/// data (legacy or fresh). Owned by each `MacraFoodJournalMealRow` as a
/// `@StateObject`; `start(mealId:)` on appear, `stop()` on disappear.
@MainActor
final class MealRowSocialObserver: ObservableObject {
    @Published private(set) var likeCount: Int = 0
    @Published private(set) var commentCount: Int = 0

    private var likesListener: ListenerRegistration?
    private var commentsListener: ListenerRegistration?
    private var startedMealId: String?

    func start(mealId: String) {
        // Re-entrant safe: if the row re-appears with the same meal id,
        // keep the existing listeners. If the meal id changed (shouldn't
        // happen in practice — the row is keyed by id — but defensively),
        // tear down and rebuild.
        if startedMealId == mealId, likesListener != nil, commentsListener != nil {
            print("[Macra][MealRowSocialObserver] start skipped existing listeners mealId=\(mealId)")
            return
        }
        stop()
        likeCount = 0
        commentCount = 0
        guard let ownerUid = Auth.auth().currentUser?.uid, !ownerUid.isEmpty,
              !mealId.isEmpty else {
            print("[Macra][MealRowSocialObserver] start blocked uid=\(Auth.auth().currentUser?.uid ?? "nil") mealId=\(mealId)")
            return
        }
        startedMealId = mealId
        print("[Macra][MealRowSocialObserver] start uid=\(ownerUid) mealId=\(mealId)")

        let mealRef = Firestore.firestore()
            .collection("users").document(ownerUid)
            .collection("mealLogs").document(mealId)

        likesListener = mealRef.collection("likes")
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    print("[Macra][MealRowSocialObserver] likes error uid=\(ownerUid) mealId=\(mealId): \(error.localizedDescription)")
                }
                let count = snapshot?.documents.count ?? 0
                print("[Macra][MealRowSocialObserver] likes count uid=\(ownerUid) mealId=\(mealId) count=\(count)")
                Task { @MainActor in
                    guard self?.startedMealId == mealId else { return }
                    self?.likeCount = count
                }
            }

        commentsListener = mealRef.collection("comments")
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    print("[Macra][MealRowSocialObserver] comments error uid=\(ownerUid) mealId=\(mealId): \(error.localizedDescription)")
                }
                let count = snapshot?.documents.count ?? 0
                print("[Macra][MealRowSocialObserver] comments count uid=\(ownerUid) mealId=\(mealId) count=\(count)")
                Task { @MainActor in
                    guard self?.startedMealId == mealId else { return }
                    self?.commentCount = count
                }
            }
    }

    func stop() {
        likesListener?.remove()
        likesListener = nil
        commentsListener?.remove()
        commentsListener = nil
        startedMealId = nil
    }

    deinit {
        likesListener?.remove()
        commentsListener?.remove()
    }
}
