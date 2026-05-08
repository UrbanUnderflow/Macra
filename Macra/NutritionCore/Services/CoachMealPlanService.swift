//
//  CoachMealPlanService.swift
//  Macra
//
//  Cross-product reader for Pulse 1-on-1 meal plans. Pulse writes
//  every meal-plan attachment to `oneOnOneTrainings/{trainingId}.attachments[]`
//  with `kind == "mealPlan"` and an embedded `mealPlan` payload that
//  carries `meals[]` + `dailyCalorieTarget`. Macra reads those here so:
//
//   1. The Macra onboarding flow can show a coach-aware welcome
//      ("@trainer assigned a meal plan for you") instead of the
//      analyze/create wizard when a coach plan exists.
//   2. The active Macra plan (`MacroRecommendation` at
//      `macroProfiles/{userId}/macroRecommendations/...`) automatically
//      adopts the coach's daily macro totals — totals computed by
//      summing the per-meal calories/protein/carbs/fat on the
//      embedded payload.
//
//  Read-only by design — Macra never writes back to the Pulse training
//  doc. Per the shared-Firebase memory ("cross-product = Firestore
//  reads, no sync layer"), the bridge stays one-way.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Resolved coach meal plan ready for Macra's onboarding/UI surface.
/// Subset of Pulse's `OneOnOneMealPlanPreview` — we only carry what
/// the welcome screen + macro adoption need. Full mealing-by-meal
/// data lives in Pulse; Macra renders the summary.
struct CoachMealPlan: Hashable {
    let trainingId: String
    let hostId: String
    let hostUsername: String
    let planName: String
    let dailyCalorieTarget: Int
    let totals: MacroTotals
    let mealCount: Int
    /// When the plan attachment was added on the Pulse training doc.
    /// Used to compare against the saved `coachMealPlanReference` so
    /// Macra knows whether it's already adopted this version.
    let attachedAt: Date

    struct MacroTotals: Hashable {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
    }
}

/// Stored on the User doc so Macra knows it has already adopted a
/// given coach plan version. When the saved reference doesn't match
/// the current coach plan (different `attachedAt` or trainingId),
/// we auto-adopt the new one on next launch.
struct CoachMealPlanReference: Hashable {
    let trainingId: String
    let hostId: String
    let hostUsername: String
    let attachedAt: Date
    let syncedAt: Date

    func toDictionary() -> [String: Any] {
        [
            "trainingId": trainingId,
            "hostId": hostId,
            "hostUsername": hostUsername,
            "attachedAt": attachedAt.timeIntervalSince1970,
            "syncedAt": syncedAt.timeIntervalSince1970
        ]
    }

    init(trainingId: String,
         hostId: String,
         hostUsername: String,
         attachedAt: Date,
         syncedAt: Date = Date()) {
        self.trainingId = trainingId
        self.hostId = hostId
        self.hostUsername = hostUsername
        self.attachedAt = attachedAt
        self.syncedAt = syncedAt
    }

    init?(dictionary: [String: Any]) {
        guard let trainingId = dictionary["trainingId"] as? String, !trainingId.isEmpty,
              let hostId = dictionary["hostId"] as? String, !hostId.isEmpty else {
            return nil
        }
        self.trainingId = trainingId
        self.hostId = hostId
        self.hostUsername = dictionary["hostUsername"] as? String ?? ""
        self.attachedAt = Date(timeIntervalSince1970: dictionary["attachedAt"] as? Double ?? 0)
        self.syncedAt = Date(timeIntervalSince1970: dictionary["syncedAt"] as? Double ?? 0)
    }
}

final class CoachMealPlanService {
    static let shared = CoachMealPlanService()

    private let db: Firestore
    /// Live listener registrations keyed by trainingId. Each subscribes
    /// to a single OneOnOne training doc so coach edits push fresh
    /// macros into Macra in real time without an app relaunch.
    private var liveListeners: [String: ListenerRegistration] = [:]
    /// Snapshot of `attachedAt` of the last meal-plan we adopted per
    /// trainingId. Lets the listener short-circuit no-op snapshots
    /// (e.g. host renames a routine on the same training doc).
    private var lastAdoptedAttachedAt: [String: Date] = [:]

    private init() {
        self.db = Firestore.firestore()
    }

    // MARK: - Fetch

    /// One-shot fetch of the most recent coach-attached meal plan for
    /// the current user. Returns nil when:
    ///  - The user isn't signed in.
    ///  - The user has no active 1-on-1 trainings as the member side.
    ///  - None of those trainings have a meal-plan attachment.
    /// Errors bubble up via the Result so the caller can decide
    /// whether to show a transient-failure state or just no-op.
    func fetchLatestCoachPlan(completion: @escaping (Result<CoachMealPlan?, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid, !userId.isEmpty else {
            completion(.success(nil))
            return
        }

        // Active 1-on-1s where the user participates. We then filter
        // in-code to ones where the user is the *member* (host plans
        // are not "coach-assigned" — the host IS the coach).
        db.collection("oneOnOneTrainings")
            .whereField("participantIds", arrayContains: userId)
            .whereField("status", isEqualTo: "active")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let trainings = snapshot?.documents ?? []
                let memberTrainings = trainings.filter { ($0.data()["memberId"] as? String) == userId }

                // Pick the meal-plan attachment with the most recent
                // `attachedAt` across all active trainings. The
                // member should rarely have more than one active
                // trainer at once; when they do, freshness wins.
                var bestPlan: CoachMealPlan?
                for doc in memberTrainings {
                    let data = doc.data()
                    guard let plan = Self.extractLatestMealPlan(trainingId: doc.documentID,
                                                                trainingData: data) else { continue }
                    if bestPlan == nil || plan.attachedAt > bestPlan!.attachedAt {
                        bestPlan = plan
                    }
                }
                completion(.success(bestPlan))
            }
    }

    // MARK: - Silent auto-adopt (post-onboarding)

    /// Existing-user path: called on app launch to detect a newly-
    /// attached coach plan (or an updated one) and silently adopt it
    /// as the user's active Macra plan. Compares the live plan's
    /// `attachedAt` against the saved `coachMealPlanReference`; only
    /// re-adopts when the source has changed (or never adopted).
    /// Onboarding does its own adoption via the `.coachAssignedPlan`
    /// step; this is the keep-in-sync path for users who already
    /// finished onboarding before the trainer assigned a plan.
    func adoptIfNew(completion: ((Result<CoachMealPlan?, Error>) -> Void)? = nil) {
        fetchLatestCoachPlan { [weak self] result in
            switch result {
            case .failure(let error):
                completion?(.failure(error))
            case .success(let plan):
                guard let self = self, let plan = plan else {
                    completion?(.success(nil))
                    return
                }
                UserService.sharedInstance.loadCoachMealPlanReference { existing in
                    let needsAdopt: Bool = {
                        guard let existing = existing else { return true }
                        if existing.trainingId != plan.trainingId { return true }
                        if existing.attachedAt < plan.attachedAt { return true }
                        return false
                    }()
                    guard needsAdopt else {
                        completion?(.success(nil))
                        return
                    }
                    self.persistAdoption(of: plan) { error in
                        if let error = error {
                            completion?(.failure(error))
                        } else {
                            completion?(.success(plan))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Live in-session listener

    /// Start observing every active 1-on-1 training the user is the
    /// member of. Snapshot listeners on each training doc fire when
    /// the host edits the plan; we re-extract the latest meal-plan
    /// attachment and silently adopt it if its `attachedAt` is newer
    /// than what we last adopted. Idempotent — calling twice replaces
    /// the existing listeners.
    /// Lifecycle:
    ///   - Call from `AppCoordinator.handleLoginSuccess` (or whenever
    ///     the user becomes authenticated and onboarded)
    ///   - Call `stopLiveCoachPlanObserver()` on sign-out
    func startLiveCoachPlanObserver() {
        stopLiveCoachPlanObserver()

        guard let userId = Auth.auth().currentUser?.uid, !userId.isEmpty else { return }

        // Discover the active trainings first, then attach a per-doc
        // listener to each. We don't listen at the *collection* level
        // (where(...).addSnapshotListener) because most users have at
        // most 1 active training and per-doc listeners are cheaper +
        // give us a clean per-training cache key.
        db.collection("oneOnOneTrainings")
            .whereField("participantIds", arrayContains: userId)
            .whereField("status", isEqualTo: "active")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self, error == nil else { return }
                let trainings = snapshot?.documents ?? []
                let memberTrainings = trainings.filter { ($0.data()["memberId"] as? String) == userId }
                for doc in memberTrainings {
                    self.attachLiveListener(trainingId: doc.documentID)
                }
            }
    }

    /// Tear down all active per-training listeners. Called on sign-out
    /// so we don't leak a Firestore subscription on a stale auth user.
    func stopLiveCoachPlanObserver() {
        for (_, registration) in liveListeners {
            registration.remove()
        }
        liveListeners.removeAll()
        lastAdoptedAttachedAt.removeAll()
    }

    private func attachLiveListener(trainingId: String) {
        guard liveListeners[trainingId] == nil else { return }
        let registration = db.collection("oneOnOneTrainings").document(trainingId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      error == nil,
                      let snapshot = snapshot,
                      snapshot.exists,
                      let data = snapshot.data() else { return }
                guard let plan = Self.extractLatestMealPlan(trainingId: trainingId, trainingData: data) else { return }

                // Skip when this is the same `attachedAt` we just
                // adopted (snapshot fired for an unrelated doc edit).
                if let last = self.lastAdoptedAttachedAt[trainingId],
                   plan.attachedAt <= last {
                    return
                }

                // Cross-check the saved reference too — covers the
                // cold-start case where this is the first snapshot
                // after launch and our in-memory `last` cache is empty.
                UserService.sharedInstance.loadCoachMealPlanReference { existing in
                    let needsAdopt: Bool = {
                        guard let existing = existing else { return true }
                        if existing.trainingId != plan.trainingId { return true }
                        if existing.attachedAt < plan.attachedAt { return true }
                        return false
                    }()
                    guard needsAdopt else {
                        self.lastAdoptedAttachedAt[trainingId] = plan.attachedAt
                        return
                    }
                    self.persistAdoption(of: plan) { error in
                        if error == nil {
                            self.lastAdoptedAttachedAt[trainingId] = plan.attachedAt
                            print("[CoachPlan] Live update — adopted plan from @\(plan.hostUsername) (trainingId=\(plan.trainingId))")
                        }
                    }
                }
            }
        liveListeners[trainingId] = registration
    }

    /// Persist the macros + reference, identical write path used by
    /// `MacraOnboardingCoordinator.adoptCoachPlan` so onboarding and
    /// silent-adopt stay byte-for-byte equivalent.
    private func persistAdoption(of plan: CoachMealPlan, completion: @escaping (Error?) -> Void) {
        guard let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid,
              !userId.isEmpty else {
            completion(nil)
            return
        }

        let calories = plan.totals.calories > 0 ? plan.totals.calories : plan.dailyCalorieTarget
        let recommendation = MacroRecommendation(
            userId: userId,
            calories: calories,
            protein: plan.totals.protein,
            carbs: plan.totals.carbs,
            fat: plan.totals.fat
        )

        MacroRecommendationService.sharedInstance.saveMacroRecommendation(recommendation) { _ in
            let mirrored = MacroRecommendations(
                calories: recommendation.calories,
                protein: recommendation.protein,
                carbs: recommendation.carbs,
                fat: recommendation.fat
            )
            FWPHandoffService.mirrorToFWPPersonal(mirrored) { _ in
                let reference = CoachMealPlanReference(
                    trainingId: plan.trainingId,
                    hostId: plan.hostId,
                    hostUsername: plan.hostUsername,
                    attachedAt: plan.attachedAt
                )
                UserService.sharedInstance.saveCoachMealPlanReference(reference, completion: completion)
            }
        }
    }

    // MARK: - Helpers

    /// Pull the latest meal-plan attachment off a training doc,
    /// summing the embedded `mealPlan.meals` to compute daily totals.
    /// Returns nil when no meal-plan attachment exists or the payload
    /// is missing the required fields.
    private static func extractLatestMealPlan(trainingId: String,
                                              trainingData: [String: Any]) -> CoachMealPlan? {
        let hostId = (trainingData["hostId"] as? String) ?? ""
        let hostInfo = trainingData["hostInfo"] as? [String: Any] ?? [:]
        let hostUsername = (hostInfo["username"] as? String) ?? ""

        let attachments = trainingData["attachments"] as? [[String: Any]] ?? []
        let mealPlanAttachments = attachments.filter { ($0["kind"] as? String) == "mealPlan" }
        guard !mealPlanAttachments.isEmpty else { return nil }

        // Newest meal plan wins — host can attach multiple over time.
        let sorted = mealPlanAttachments.sorted { lhs, rhs in
            (lhs["attachedAt"] as? Double ?? 0) > (rhs["attachedAt"] as? Double ?? 0)
        }
        guard let attachment = sorted.first else { return nil }

        let attachedAt = Date(timeIntervalSince1970: attachment["attachedAt"] as? Double ?? 0)
        let title = (attachment["title"] as? String) ?? ""
        let mealPlan = attachment["mealPlan"] as? [String: Any] ?? [:]
        let planName = ((mealPlan["planName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = planName.isEmpty ? title : planName

        let meals = mealPlan["meals"] as? [[String: Any]] ?? []
        let totals = meals.reduce(CoachMealPlan.MacroTotals(calories: 0, protein: 0, carbs: 0, fat: 0)) { acc, meal in
            CoachMealPlan.MacroTotals(
                calories: acc.calories + ((meal["calories"] as? Int) ?? 0),
                protein: acc.protein + ((meal["protein"] as? Int) ?? 0),
                carbs: acc.carbs + ((meal["carbs"] as? Int) ?? 0),
                fat: acc.fat + ((meal["fat"] as? Int) ?? 0)
            )
        }

        // Prefer the persisted dailyCalorieTarget when it's set; fall
        // back to the live sum so an unsaved/legacy plan still works.
        let dailyCalorieTarget = (mealPlan["dailyCalorieTarget"] as? Int) ?? totals.calories

        // Skip empty plans — a `mealPlan` doc with no meals shouldn't
        // override a member's existing macro target.
        guard totals.calories > 0 || dailyCalorieTarget > 0 else { return nil }

        return CoachMealPlan(
            trainingId: trainingId,
            hostId: hostId,
            hostUsername: hostUsername,
            planName: resolvedName,
            dailyCalorieTarget: dailyCalorieTarget,
            totals: totals,
            mealCount: meals.count,
            attachedAt: attachedAt
        )
    }
}
