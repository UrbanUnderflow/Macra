import Foundation
import SwiftUI

///Docs:
/////////////////////////////////////////////////////////////////////////////////////////////////////////
///Individual Corners:
///Top Leading (Top left for left-to-right layouts): .topLeading
///Top Trailing (Top right for left-to-right layouts): .topTrailing
///Bottom Leading (Bottom left for left-to-right layouts): .bottomLeading
///Bottom Trailing (Bottom right for left-to-right layouts): .bottomTrailing
///Combined Corners:
///
///Only Top Corners: .top (which is the same as .topLeading.union(.topTrailing))
///Only Bottom Corners: .bottom (which is the same as .bottomLeading.union(.bottomTrailing))
///All Corners: .all (which is the same as .top.union(.bottom) or .topLeading.union(.topTrailing).union(.bottomLeading).union(.bottomTrailing))
///Custom Combinations:
///You can also combine individual corners to get a custom set. Here are a few examples:
///
///Top Leading and Bottom Trailing: .topLeading.union(.bottomTrailing)
///Top Trailing and Bottom Leading: .topTrailing.union(.bottomLeading)
///... and any other combination you might need.
///
////Example:
///.cornerRadius(30, corners: .top)
///.cornerRadius(30, corners: .topLeading.union(.bottomTrailing))
///.cornerRadius(30, corners: [.top, .bottomLeading])
///
////////////////////////////////////////////////////////////////////////////////////////////////////////////

struct Corners: OptionSet {
    let rawValue: Int

    static let topLeading = Corners(rawValue: 1 << 0)
    static let topTrailing = Corners(rawValue: 1 << 1)
    static let bottomLeading = Corners(rawValue: 1 << 2)
    static let bottomTrailing = Corners(rawValue: 1 << 3)
    
    static let top: Corners = [.topLeading, .topTrailing]
    static let bottom: Corners = [.bottomLeading, .bottomTrailing]
    static let all: Corners = [.top, .bottom]
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: Corners) -> some View {
        clipShape(RoundedCorners(radius: radius, corners: corners))
    }
}

struct RoundedCorners: Shape {
    var radius: CGFloat = .infinity
    var corners: Corners = .all

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.size.width
        let h = rect.size.height

        // Check and possibly draw rounded corner for each corner
        if corners.contains(.topLeading) {
            path.move(to: CGPoint(x: 0, y: radius))
            path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint.zero)
        } else {
            path.move(to: CGPoint(x: 0, y: 0))
        }
        
        if corners.contains(.topTrailing) {
            path.addLine(to: CGPoint(x: w - radius, y: 0))
            path.addQuadCurve(to: CGPoint(x: w, y: radius), control: CGPoint(x: w, y: 0))
        } else {
            path.addLine(to: CGPoint(x: w, y: 0))
        }

        if corners.contains(.bottomTrailing) {
            path.addLine(to: CGPoint(x: w, y: h - radius))
            path.addQuadCurve(to: CGPoint(x: w - radius, y: h), control: CGPoint(x: w, y: h))
        } else {
            path.addLine(to: CGPoint(x: w, y: h))
        }

        if corners.contains(.bottomLeading) {
            path.addLine(to: CGPoint(x: radius, y: h))
            path.addQuadCurve(to: CGPoint(x: 0, y: h - radius), control: CGPoint(x: 0, y: h))
        } else {
            path.addLine(to: CGPoint(x: 0, y: h))
        }

        return path
    }
}
