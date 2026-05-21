import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

final class MacraPurchaseLogService {
    static let shared = MacraPurchaseLogService()

    private let collectionName = "Macra-purchase-logs"

    private init() {}

    @discardableResult
    func recordAttempt(
        plan: SubscriptionPlanOption?,
        source: String,
        metadata: [String: Any] = [:]
    ) -> String? {
        guard FirebaseApp.app() != nil else {
            print("[Macra][PurchaseLogs] Firebase is not configured; skipping purchase attempt log")
            return nil
        }

        let document = Firestore.firestore().collection(collectionName).document()
        var payload = basePayload(plan: plan, source: source, metadata: metadata)
        payload["status"] = "attempted"
        payload["createdAt"] = FieldValue.serverTimestamp()
        payload["updatedAt"] = FieldValue.serverTimestamp()

        write(documentID: document.documentID, payload: payload, merge: false, action: "created")
        return document.documentID
    }

    func markSuccess(
        logID: String?,
        plan: SubscriptionPlanOption?,
        source: String,
        metadata: [String: Any] = [:]
    ) {
        writeStatus(
            logID: logID,
            status: "success",
            plan: plan,
            source: source,
            metadata: metadata
        )
    }

    func markCanceled(
        logID: String?,
        plan: SubscriptionPlanOption?,
        source: String,
        error: Error? = nil,
        failureReason: String? = nil,
        cancelReasonCode: String? = nil,
        cancelReasonLabel: String? = nil,
        metadata: [String: Any] = [:]
    ) {
        var fields = errorPayload(error: error, failureReason: failureReason)
        if let cancelReasonCode {
            fields["cancelReasonCode"] = cancelReasonCode
        }
        if let cancelReasonLabel {
            fields["cancelReasonLabel"] = cancelReasonLabel
        }

        writeStatus(
            logID: logID,
            status: "canceled",
            plan: plan,
            source: source,
            metadata: metadata,
            extraFields: fields
        )
    }

    func markFailed(
        logID: String?,
        plan: SubscriptionPlanOption?,
        source: String,
        error: Error? = nil,
        failureReason: String? = nil,
        metadata: [String: Any] = [:]
    ) {
        writeStatus(
            logID: logID,
            status: "failed",
            plan: plan,
            source: source,
            metadata: metadata,
            extraFields: errorPayload(error: error, failureReason: failureReason)
        )
    }

    func attachCancelReason(
        logID: String?,
        reasonCode: String,
        reasonLabel: String,
        trigger: String,
        metadata: [String: Any] = [:]
    ) {
        guard let logID, !logID.isEmpty else { return }
        guard FirebaseApp.app() != nil else { return }

        var payload: [String: Any] = [
            "status": "canceled",
            "cancelReasonCode": reasonCode,
            "cancelReasonLabel": reasonLabel,
            "cancelFeedbackTrigger": trigger,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if !metadata.isEmpty {
            payload["cancelFeedbackMetadata"] = sanitize(metadata)
        }

        write(documentID: logID, payload: payload, merge: true, action: "updated cancel reason")
    }

    private func writeStatus(
        logID: String?,
        status: String,
        plan: SubscriptionPlanOption?,
        source: String,
        metadata: [String: Any],
        extraFields: [String: Any] = [:]
    ) {
        guard FirebaseApp.app() != nil else {
            print("[Macra][PurchaseLogs] Firebase is not configured; skipping \(status) log")
            return
        }

        let documentID = validDocumentID(logID) ?? Firestore.firestore().collection(collectionName).document().documentID
        var payload = basePayload(plan: plan, source: source, metadata: metadata)
        payload["status"] = status
        payload["updatedAt"] = FieldValue.serverTimestamp()
        if validDocumentID(logID) == nil {
            payload["createdAt"] = FieldValue.serverTimestamp()
        }
        extraFields.forEach { payload[$0.key] = $0.value }

        write(documentID: documentID, payload: payload, merge: true, action: "updated \(status)")
    }

    private func basePayload(
        plan: SubscriptionPlanOption?,
        source: String,
        metadata: [String: Any]
    ) -> [String: Any] {
        let firebaseUser = Auth.auth().currentUser
        let appUser = UserService.sharedInstance.user
        let userId = firebaseUser?.uid ?? appUser?.id ?? ""
        let email = firebaseUser?.email ?? appUser?.email ?? ""

        return [
            "userId": userId,
            "email": email,
            "plan": planPayload(plan),
            "source": source,
            "errorDomain": "",
            "errorCode": "",
            "readableErrorCode": "",
            "errorDescription": "",
            "failureReason": "",
            "metadata": sanitize(metadata),
            "app": "macra",
            "platform": "ios"
        ]
    }

    private func planPayload(_ plan: SubscriptionPlanOption?) -> [String: Any] {
        guard let plan else {
            return [
                "id": "none",
                "title": "Unknown",
                "period": "unknown",
                "price": "",
                "priceLabel": ""
            ]
        }

        return [
            "id": plan.analyticsProductId,
            "packageId": plan.id,
            "title": plan.displayTitle,
            "period": periodName(plan.periodKind),
            "price": NSDecimalNumber(decimal: plan.price).doubleValue,
            "priceLabel": plan.priceLabel,
            "trialDays": plan.trialDays ?? 0
        ]
    }

    private func errorPayload(error: Error?, failureReason: String?) -> [String: Any] {
        var payload: [String: Any] = [:]

        if let error {
            let nsError = error as NSError
            payload["errorDomain"] = nsError.domain
            payload["errorCode"] = nsError.code
            payload["errorDescription"] = nsError.localizedDescription
            if let readableCode = nsError.userInfo["readable_error_code"] as? String {
                payload["readableErrorCode"] = readableCode
            }
        }

        if let failureReason, !failureReason.isEmpty {
            payload["failureReason"] = failureReason
        }

        return payload
    }

    private func periodName(_ period: SubscriptionPlanPeriodKind) -> String {
        switch period {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        case .unknown: return "unknown"
        }
    }

    private func validDocumentID(_ logID: String?) -> String? {
        guard let logID = logID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !logID.isEmpty else { return nil }
        return logID
    }

    private func write(documentID: String, payload: [String: Any], merge: Bool, action: String) {
        Firestore.firestore()
            .collection(collectionName)
            .document(documentID)
            .setData(payload, merge: merge) { error in
                if let error {
                    print("[Macra][PurchaseLogs] Firestore \(action) failed: \(error.localizedDescription)")
                } else {
                    print("[Macra][PurchaseLogs] Firestore \(action) collection=Macra-purchase-logs id=\(documentID)")
                }
            }
    }

    private func sanitize(_ value: Any) -> Any {
        switch value {
        case let value as String:
            return value
        case let value as Bool:
            return value
        case let value as Int:
            return value
        case let value as Int64:
            return value
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        case let value as Decimal:
            return NSDecimalNumber(decimal: value).doubleValue
        case let value as Date:
            return Timestamp(date: value)
        case let value as Timestamp:
            return value
        case let value as [String: Any]:
            return value.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = sanitize(pair.value)
            }
        case let value as [Any]:
            return value.map { sanitize($0) }
        default:
            return String(describing: value)
        }
    }
}
