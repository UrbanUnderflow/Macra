import Foundation

/// Local on-device cache for per-day Ask Nora threads.
///
/// The primary source of truth for the UI — writes go here synchronously so
/// a message can never vanish on next launch because of a Firestore failure
/// (missing composite index, offline, rules, auth not yet hydrated, etc).
/// Firestore sync (`MacraNoraChatService`) runs in parallel and backfills
/// cross-device history when it completes.
///
/// Storage: `UserDefaults` under `com.macra.nora.thread.{uid}.{dayKey}`. If
/// the caller has not hydrated a user id yet, the cache falls back to the
/// current Firebase uid before using the anonymous bucket. Anonymous messages
/// are migrated into the signed-in bucket on the next load for that day.
enum MacraNoraThreadCache {
    private static let prefix = "com.macra.nora.thread"
    private static let anonymousUserId = "anon"
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func normalizedUserId(_ userId: String?) -> String {
        let resolved = NutritionCoreConfiguration.resolvedUserId(userId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolved, !resolved.isEmpty else { return anonymousUserId }
        return resolved
    }

    static func key(userId: String?, dayKey: String) -> String {
        let uid = normalizedUserId(userId)
        return "\(prefix).\(uid).\(dayKey)"
    }

    static func load(userId: String?, dayKey: String) -> [MacraNoraMessage] {
        let userDefaults = UserDefaults.standard
        let k = key(userId: userId, dayKey: dayKey)
        let messages = decodedMessages(forKey: k, userDefaults: userDefaults)
        print("[Macra][Nora][CACHE-LOAD-RAW] cacheKey=\(k) requestedDayKey=\(dayKey) count=\(messages.count) storedDayKeys=\(messages.map { $0.dayKey })")

        guard normalizedUserId(userId) != anonymousUserId else {
            return messages.sorted { $0.timestamp < $1.timestamp }
        }

        let anonKey = "\(prefix).\(anonymousUserId).\(dayKey)"
        guard anonKey != k else {
            return messages.sorted { $0.timestamp < $1.timestamp }
        }

        let anonymousMessages = decodedMessages(forKey: anonKey, userDefaults: userDefaults)
        guard !anonymousMessages.isEmpty else {
            return messages.sorted { $0.timestamp < $1.timestamp }
        }

        print("[Macra][Nora][CACHE-LOAD-ANON-MIGRATE] anonKey=\(anonKey) targetKey=\(k) anonCount=\(anonymousMessages.count)")
        let merged = merge(local: messages, incoming: anonymousMessages)
        save(merged, userId: userId, dayKey: dayKey)
        return merged
    }

    static func save(_ messages: [MacraNoraMessage], userId: String?, dayKey: String) {
        let k = key(userId: userId, dayKey: dayKey)
        let sorted = messages.sorted { $0.timestamp < $1.timestamp }
        if let data = try? encoder.encode(sorted) {
            UserDefaults.standard.set(data, forKey: k)
        }
    }

    static func append(_ message: MacraNoraMessage, userId: String?) {
        let bucketKey = key(userId: userId, dayKey: message.dayKey)
        print("[Macra][Nora][CACHE-APPEND] msgId=\(message.id) bucketKey=\(bucketKey) msgDayKey=\(message.dayKey) ts=\(message.timestamp)")
        var current = load(userId: userId, dayKey: message.dayKey)
        if let existing = current.firstIndex(where: { $0.id == message.id }) {
            current[existing] = message
        } else {
            current.append(message)
        }
        save(current, userId: userId, dayKey: message.dayKey)
    }

    /// Merges a Firestore-fetched snapshot into the local cache.
    ///
    /// Rule: Firestore wins on fields (assistant content may be rewritten by
    /// a retry, for example), but any locally-cached message missing from
    /// Firestore survives — covers the case where a save is still pending or
    /// failed silently. Returns the merged list for the caller to render.
    @discardableResult
    static func merge(remote: [MacraNoraMessage], userId: String?, dayKey: String) -> [MacraNoraMessage] {
        let local = load(userId: userId, dayKey: dayKey)
        let merged = merge(local: local, incoming: remote)
        save(merged, userId: userId, dayKey: dayKey)
        return merged
    }

    private static func decodedMessages(forKey key: String, userDefaults: UserDefaults) -> [MacraNoraMessage] {
        guard let data = userDefaults.data(forKey: key),
              let messages = try? decoder.decode([MacraNoraMessage].self, from: data) else {
            return []
        }
        return messages
    }

    private static func merge(local: [MacraNoraMessage], incoming: [MacraNoraMessage]) -> [MacraNoraMessage] {
        var byId: [String: MacraNoraMessage] = [:]
        for m in local { byId[m.id] = m }
        for m in incoming { byId[m.id] = m }
        return byId.values.sorted { $0.timestamp < $1.timestamp }
    }
}
