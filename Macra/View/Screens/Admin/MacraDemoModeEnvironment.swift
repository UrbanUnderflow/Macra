#if DEBUG
import SwiftUI

private struct IsMacraDemoModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isMacraDemoMode: Bool {
        get { self[IsMacraDemoModeKey.self] }
        set { self[IsMacraDemoModeKey.self] = newValue }
    }
}
#endif
