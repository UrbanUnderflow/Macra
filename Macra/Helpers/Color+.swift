import Foundation
import SwiftUI

extension Color {
    static let primaryGreen = Color("primaryGreen")
    static let primaryPurple = Color("primaryPurple")
    static let primaryBlue = Color("primaryBlue")
    static let secondaryCharcoal = Color("secondaryCharcoal")
    static let blueGray = Color("blueGray")
    static let lightGray = Color("lightGray")
    static let lightBlue = Color("lightBlue")
    static let secondaryWhite = Color("secondaryWhite")
    static let wind = Color("wind")
    static let ash = Color("ash")
    static let secondaryPink = Color("secondaryPink")
    static let macraGreenLight = Color(hex: "C5F13D")
    static let macraGreenMid = Color(hex: "ACE73E")
    static let macraGreenDeep = Color(hex: "61CB42")
}

extension LinearGradient {
    static let macraGreen = LinearGradient(
        colors: [.macraGreenLight, .macraGreenMid, .macraGreenDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
