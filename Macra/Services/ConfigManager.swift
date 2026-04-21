import Foundation

struct ConfigManager {
    static let shared = ConfigManager()

    private init() {}

    private func loadConfigValue(forKey key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject],
              let value = dict[key] as? String,
              !value.isEmpty else {
            return nil
        }

        return value
    }

    func getWebsiteBaseURL() -> String {
        if let baseURL = ProcessInfo.processInfo.environment["WEBSITE_BASE_URL"], !baseURL.isEmpty {
            return baseURL
        }

        if let baseURL = loadConfigValue(forKey: "WEBSITE_BASE_URL") {
            return baseURL
        }

        return "https://fitwithpulse.ai"
    }
}
