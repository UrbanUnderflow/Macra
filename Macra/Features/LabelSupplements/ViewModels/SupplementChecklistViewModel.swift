import Foundation

final class SupplementChecklistViewModel: ObservableObject {
    @Published var savedSupplements: [LoggedSupplement] = []
    @Published var loggedSupplements: [LoggedSupplement] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var allSupplementsLoggedToday: Bool {
        guard !savedSupplements.isEmpty else { return false }
        return savedSupplements.allSatisfy { isSupplementLoggedToday($0) }
    }

    func load(date: Date = Date()) {
        isLoading = true
        errorMessage = nil

        let group = DispatchGroup()
        var loadedSaved: [LoggedSupplement] = []
        var loadedLogged: [LoggedSupplement] = []
        var loadError: Error?

        group.enter()
        SupplementLogService.shared.getSavedSupplements { result in
            defer { group.leave() }
            switch result {
            case .success(let supplements):
                loadedSaved = supplements
            case .failure(let error):
                loadError = error
            }
        }

        group.enter()
        SupplementLogService.shared.getLoggedSupplements(byDate: date) { result in
            defer { group.leave() }
            switch result {
            case .success(let supplements):
                loadedLogged = supplements
            case .failure(let error):
                loadError = error
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
            self?.savedSupplements = loadedSaved
            self?.loggedSupplements = loadedLogged
            self?.errorMessage = loadError?.localizedDescription
        }
    }

    func saveSupplementToLibrary(_ supplement: LoggedSupplement) {
        SupplementLogService.shared.saveSupplement(supplement) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    if let index = self?.savedSupplements.firstIndex(where: { $0.id == supplement.id }) {
                        self?.savedSupplements[index] = supplement
                    } else {
                        self?.savedSupplements.insert(supplement, at: 0)
                    }
                }
            }
        }
    }

    func deleteSavedSupplement(_ supplement: LoggedSupplement) {
        SupplementLogService.shared.deleteSavedSupplement(withId: supplement.id) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    self?.savedSupplements.removeAll { $0.id == supplement.id }
                }
            }
        }
    }

    func addSupplement(_ supplement: LoggedSupplement) {
        var supplement = supplement
        supplement.updatedAt = Date()
        supplement.inferMicronutrients()
        SupplementLogService.shared.addLoggedSupplement(supplement) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    self?.loggedSupplements.append(supplement)
                }
            }
        }
    }

    func deleteSupplement(_ supplement: LoggedSupplement) {
        SupplementLogService.shared.deleteLoggedSupplement(withId: supplement.id) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    self?.loggedSupplements.removeAll { $0.id == supplement.id }
                }
            }
        }
    }

    func toggleSupplementForToday(_ supplement: LoggedSupplement) {
        if let existing = loggedInstance(of: supplement) {
            deleteSupplement(existing)
        } else {
            addSupplement(supplement)
        }
    }

    func logAllSupplements() {
        let unlogged = savedSupplements.filter { !isSupplementLoggedToday($0) }
        unlogged.forEach { addSupplement($0) }
    }

    func isSupplementLoggedToday(_ supplement: LoggedSupplement) -> Bool {
        loggedInstance(of: supplement) != nil
    }

    func loggedInstance(of supplement: LoggedSupplement) -> LoggedSupplement? {
        loggedSupplements.first { $0.id == Date().dayMonthYearFormat + supplement.id || $0.name == supplement.name }
    }
}

