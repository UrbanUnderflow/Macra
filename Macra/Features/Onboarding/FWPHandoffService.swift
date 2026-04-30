//
//  FWPHandoffService.swift
//  Macra
//
//  Reads Fit With Pulse macros + biometric fields from the shared
//  `users/{uid}` Firestore doc so Macra onboarding can offer a handoff
//  ("use your FWP macros, or reassess?") at the start of the flow.
//
//  All three Pulse apps (FWP/QuickLifts, Macra, PulseCheck) share the
//  same Firebase project + User document — fields here are a read-only
//  subset of what FWP writes.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct FWPHandoffProfile {
    /// Personal macros set by the user in FWP (`user.macros["personal"]`).
    var personalMacros: MacroRecommendations?
    var sex: BiologicalSex?
    var birthdate: Date?
    var heightCm: Double?
    var currentWeightKg: Double?
    var activityLevel: ActivityLevel?

    /// True when we found macros we can offer as a handoff.
    var hasFWPMacros: Bool { personalMacros != nil }
}

enum FWPHandoffService {
    /// Fetches the currently-authenticated user's FWP-side profile fields
    /// from the shared Firestore `users` doc. Returns a zero-filled profile
    /// when the user isn't authenticated or the doc is missing.
    static func fetchProfile(completion: @escaping (FWPHandoffProfile) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion(FWPHandoffProfile())
            return
        }

        Firestore.firestore().collection("users").document(uid).getDocument { snapshot, _ in
            guard let data = snapshot?.data() else {
                completion(FWPHandoffProfile())
                return
            }
            completion(profile(from: data))
        }
    }

    static func profile(from data: [String: Any]) -> FWPHandoffProfile {
        var profile = FWPHandoffProfile()

        // Macros dict is shaped [scopeKey: [field: Int]]
        if let macrosDict = data["macros"] as? [String: [String: Int]],
           let personal = macrosDict["personal"] {
            profile.personalMacros = MacroRecommendations(
                calories: personal["calories"] ?? 0,
                protein: personal["protein"] ?? 0,
                carbs: personal["carbs"] ?? 0,
                fat: personal["fat"] ?? 0
            )
        }

        if let genderRaw = data["gender"] as? String {
            switch genderRaw {
            case "man": profile.sex = .male
            case "woman": profile.sex = .female
            default: break
            }
        }

        if let ts = data["birthdate"] as? Double, ts > 0 {
            profile.birthdate = Date(timeIntervalSince1970: ts)
        }

        // FWP stores height as a "feet'inches" string, e.g. "5'8"
        if let heightString = data["height"] as? String {
            let parts = heightString.split(separator: "'")
            if parts.count == 2,
               let feet = Int(parts[0]),
               let inches = Int(parts[1]) {
                let totalInches = Double(feet * 12 + inches)
                profile.heightCm = totalInches * 2.54
            }
        }

        // bodyWeight is an array of {id, oldWeight, newWeight, ...}; pick the latest newWeight (lbs → kg).
        if let weights = data["bodyWeight"] as? [[String: Any]],
           let latest = weights.last,
           let newLbs = latest["newWeight"] as? Double,
           newLbs > 0 {
            profile.currentWeightKg = newLbs * 0.453592
        }

        if let activityRaw = data["activityLevel"] as? String {
            // FWP uses TDEECalculator.ActivityLevel rawValues: sedentary/light/moderate/active/veryActive
            // Macra's ActivityLevel uses: sedentary/light/moderate/veryActive/athlete
            switch activityRaw {
            case "sedentary":  profile.activityLevel = .sedentary
            case "light":      profile.activityLevel = .light
            case "moderate":   profile.activityLevel = .moderate
            case "active":     profile.activityLevel = .veryActive
            case "veryActive": profile.activityLevel = .athlete
            default: break
            }
        }

        return profile
    }

    /// Writes a `MacroRecommendations` back to the shared User doc under
    /// `user.macros["personal"]`, so FWP picks up targets that Macra computed.
    static func mirrorToFWPPersonal(_ macros: MacroRecommendations, completion: ((Error?) -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            completion?(nil)
            return
        }

        let personalDict: [String: Int] = [
            "calories": macros.calories,
            "protein": macros.protein,
            "carbs": macros.carbs,
            "fat": macros.fat
        ]

        // Dot-path merge so we don't clobber other scoped macro keys (e.g. "club_<id>").
        Firestore.firestore().collection("users").document(uid).updateData([
            "macros.personal": personalDict,
            "updatedAt": Date().timeIntervalSince1970
        ]) { error in
            completion?(error)
        }
    }
}
