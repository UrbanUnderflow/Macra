import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class MacraDailyInsightService: ObservableObject {
    static let shared = MacraDailyInsightService()

    @Published private(set) var insight: MacraFoodJournalDailyInsight?
    @Published private(set) var isRegenerating: Bool = false
    @Published private(set) var lastError: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var listeningKey: String?
    private var listeningUid: String?

    private init() {}

    deinit {
        listener?.remove()
    }

    func subscribe(to date: Date) {
        guard let uid = Auth.auth().currentUser?.uid else {
            insight = nil
            stop()
            return
        }
        let dayKey = Self.dayKey(for: date)
        if listeningKey == dayKey, listeningUid == uid { return }

        listener?.remove()
        listeningKey = dayKey
        listeningUid = uid
        insight = nil

        listener = db.collection("users").document(uid)
            .collection("macraInsights").document(dayKey)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error = error {
                        self.lastError = error.localizedDescription
                        return
                    }
                    guard let data = snapshot?.data() else {
                        self.insight = nil
                        return
                    }
                    self.insight = Self.parse(data: data, dayKey: dayKey)
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        listeningKey = nil
        listeningUid = nil
        insight = nil
    }

    func regenerate(for date: Date) async {
        guard !isRegenerating else { return }
        guard let user = Auth.auth().currentUser else {
            lastError = "Sign in to regenerate."
            return
        }

        isRegenerating = true
        lastError = nil

        do {
            let token = try await user.getIDToken()
            let base = ConfigManager.shared.getWebsiteBaseURL()
            guard let url = URL(string: "\(base)/.netlify/functions/generate-macra-daily-insight") else {
                throw NSError(domain: "MacraDailyInsight", code: 0, userInfo: [NSLocalizedDescriptionKey: "Bad URL"])
            }

            let body: [String: Any] = [
                "date": Self.dayKey(for: date),
                "timezone": TimeZone.current.identifier,
                "persist": true,
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 60

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let bodyString = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "MacraDailyInsight", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Insight service returned \((response as? HTTPURLResponse)?.statusCode ?? -1): \(bodyString.prefix(200))"
                ])
            }
            // Firestore listener will update `insight` when the function persists.
        } catch {
            lastError = error.localizedDescription
        }

        isRegenerating = false
    }

    private static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func parse(data: [String: Any], dayKey: String) -> MacraFoodJournalDailyInsight? {
        let title = (data["title"] as? String) ?? "Today's read"
        let icon = (data["icon"] as? String) ?? "sparkles"
        let type = data["type"] as? String

        let rawPoints = data["points"] as? [String] ?? []
        let points = rawPoints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let action = (data["action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyResponse = (data["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Body for views that need a single string (older surfaces, share cards):
        // join the points + action with newlines, falling back to the legacy
        // response field if the doc was generated before the points/action
        // schema rolled out.
        let composedResponse: String
        if !points.isEmpty {
            var lines = points
            if let action = action, !action.isEmpty { lines.append("Try: \(action)") }
            composedResponse = lines.joined(separator: "\n")
        } else {
            composedResponse = legacyResponse
        }

        guard !composedResponse.isEmpty else { return nil }

        let timestamp: Date
        if let ts = data["generatedAtEpochMs"] as? Double {
            timestamp = Date(timeIntervalSince1970: ts / 1000)
        } else if let ts = data["generatedAtEpochMs"] as? Int64 {
            timestamp = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        } else if let ts = data["generatedAt"] as? Timestamp {
            timestamp = ts.dateValue()
        } else {
            timestamp = Date()
        }

        return MacraFoodJournalDailyInsight(
            id: dayKey,
            title: title,
            response: composedResponse,
            query: "",
            icon: icon,
            timestamp: timestamp,
            type: type,
            points: points.isEmpty ? nil : points,
            action: (action?.isEmpty == false) ? action : nil
        )
    }
}
