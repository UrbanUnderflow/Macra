import Foundation

func generateUniqueID(prefix: String = "") -> String {
    let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    if prefix.isEmpty {
        return suffix
    }
    return "\(prefix)-\(suffix)"
}

