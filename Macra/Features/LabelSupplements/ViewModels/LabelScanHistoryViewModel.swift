import Foundation

final class LabelScanHistoryViewModel: ObservableObject {
    @Published var scannedLabels: [ScannedLabel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadScannedLabels() {
        isLoading = true
        errorMessage = nil
        LabelScanService.shared.getScannedLabels { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let labels):
                    self?.scannedLabels = labels
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func deleteScan(_ scannedLabel: ScannedLabel) {
        LabelScanService.shared.deleteScannedLabel(scannedLabel) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    self?.scannedLabels.removeAll { $0.id == scannedLabel.id }
                }
            }
        }
    }
}

