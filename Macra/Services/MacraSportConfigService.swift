import Foundation
import FirebaseFirestore

struct MacraSportConfig: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let positions: [String]
    let sortOrder: Int
}

@MainActor
final class MacraSportConfigService: ObservableObject {
    static let shared = MacraSportConfigService()

    @Published private(set) var sports: [MacraSportConfig] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?

    private let db = Firestore.firestore()
    private var hasFetched = false

    func loadIfNeeded() {
        guard !hasFetched, !isLoading else { return }
        load()
    }

    func load() {
        isLoading = true
        loadError = nil

        db.collection("company-config").document("pulsecheck-sports").getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                self.hasFetched = true

                if let error = error {
                    self.loadError = error.localizedDescription
                    return
                }

                let raw = snapshot?.data()?["sports"] as? [[String: Any]] ?? []
                let parsed = raw.compactMap(MacraSportConfig.init(dict:))
                self.sports = parsed.sorted { $0.sortOrder < $1.sortOrder }
            }
        }
    }
}

private extension MacraSportConfig {
    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String, !id.isEmpty,
              let name = dict["name"] as? String, !name.isEmpty else { return nil }
        self.id = id
        self.name = name
        self.emoji = (dict["emoji"] as? String) ?? "🏅"
        self.positions = (dict["positions"] as? [String]) ?? []
        if let order = dict["sortOrder"] as? Int { self.sortOrder = order }
        else if let order = dict["sortOrder"] as? Double { self.sortOrder = Int(order) }
        else { self.sortOrder = 0 }
    }
}
