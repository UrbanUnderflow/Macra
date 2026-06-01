import Foundation

struct MacraUserFacingError {
    static let genericMessage = "Something went wrong. Try again in a moment."

    static func message(
        for error: Error,
        fallbackCode: String,
        fallbackMessage: String = genericMessage
    ) -> String {
        let description = (error as NSError).localizedDescription

        if let payload = parseSafePayload(from: description) {
            return formattedMessage(
                message: payload.message ?? fallbackMessage,
                code: payload.code ?? fallbackCode,
                incidentId: payload.incidentId
            )
        }

        if isNetworkError(error) {
            return formattedMessage(
                message: "Check your connection and try again.",
                code: "NETWORK_UNAVAILABLE",
                incidentId: nil
            )
        }

        if looksLikeProviderOrBridgeDetail(description) {
            return formattedMessage(
                message: fallbackMessage,
                code: fallbackCode,
                incidentId: nil
            )
        }

        return formattedMessage(
            message: fallbackMessage,
            code: fallbackCode,
            incidentId: nil
        )
    }

    static func analyzer(_ error: Error) -> String {
        message(
            for: error,
            fallbackCode: "AI_ANALYZER_UNAVAILABLE",
            fallbackMessage: "We couldn't analyze that right now. Try again in a moment."
        )
    }

    static func mealPlan(_ error: Error) -> String {
        message(
            for: error,
            fallbackCode: "MACRA_MEAL_PLAN_GENERATION_FAILED",
            fallbackMessage: "We couldn't update that meal plan right now. Try again in a moment."
        )
    }

    static func nora(_ error: Error) -> String {
        message(
            for: error,
            fallbackCode: "NORA_REQUEST_FAILED",
            fallbackMessage: "Nora couldn't answer right now. Try again in a moment."
        )
    }

    static func sync(_ error: Error) -> String {
        message(
            for: error,
            fallbackCode: "SYNC_FAILED",
            fallbackMessage: "We couldn't sync that change right now. Try again in a moment."
        )
    }

    static func purchase(_ error: Error) -> String {
        message(
            for: error,
            fallbackCode: "PURCHASE_SYNC_FAILED",
            fallbackMessage: "We couldn't verify the purchase right now. Try again in a moment."
        )
    }

    static func upload(_ error: Error) -> String {
        message(
            for: error,
            fallbackCode: "UPLOAD_FAILED",
            fallbackMessage: "We couldn't upload that photo right now. Try again in a moment."
        )
    }

    static func auth(_ error: Error) -> String {
        message(
            for: error,
            fallbackCode: "AUTH_FAILED",
            fallbackMessage: "We couldn't complete that sign-in request. Check your info and try again."
        )
    }

    private struct SafePayload {
        let code: String?
        let message: String?
        let incidentId: String?
    }

    private static func formattedMessage(message: String, code: String, incidentId: String?) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleMessage = trimmedMessage.isEmpty ? genericMessage : trimmedMessage
        let visibleCode = (incidentId?.isEmpty == false ? incidentId : code)
        return "\(visibleMessage) Code: \(visibleCode ?? code)."
    }

    private static func parseSafePayload(from text: String) -> SafePayload? {
        guard let jsonText = extractJSONObject(from: text),
              let data = jsonText.data(using: .utf8) else {
            return nil
        }
        guard let decoded = try? JSONSerialization.jsonObject(with: data),
              let object = decoded as? [String: Any] else {
            return nil
        }

        var code = stringValue(object["errorCode"]) ?? stringValue(object["code"])
        var message = stringValue(object["message"])
        var incidentId = stringValue(object["incidentId"])

        if let errorObject = object["error"] as? [String: Any] {
            code = stringValue(errorObject["code"]) ?? code
            message = stringValue(errorObject["message"]) ?? message
            incidentId = stringValue(errorObject["incidentId"])
                ?? stringValue(errorObject["incident_id"])
                ?? incidentId
        } else if let errorString = stringValue(object["error"]) {
            if code == nil, looksLikeErrorCode(errorString) {
                code = errorString
            }
            if message == nil, !looksLikeProviderOrBridgeDetail(errorString) {
                message = errorString
            }
        }

        guard code != nil || message != nil || incidentId != nil else { return nil }
        return SafePayload(code: code, message: message, incidentId: incidentId)
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func looksLikeErrorCode(_ text: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return !text.isEmpty
            && text.rangeOfCharacter(from: allowed.inverted) == nil
            && text.contains("_")
    }

    private static func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return true }
        let message = nsError.localizedDescription.lowercased()
        return message.contains("internet")
            || message.contains("network")
            || message.contains("timed out")
            || message.contains("connection")
    }

    private static func looksLikeProviderOrBridgeDetail(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("analyzer bridge")
            || lower.contains("anthropic")
            || lower.contains("openai")
            || lower.contains("upstream")
            || lower.contains("api_key")
            || lower.contains("usage_exceeded")
            || lower.contains("usage exceeded")
            || lower.contains("firebase token")
            || lower.contains("\"error\"")
            || lower.contains("internal gateway")
            || lower.contains("forbidden model")
            || lower.contains("bad request")
    }
}
