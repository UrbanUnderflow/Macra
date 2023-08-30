//
//  IconImage.swift
//  QuickLifts
//
//  Created by Tremaine Grant on 6/27/23.
//

import Foundation
import SwiftUI

struct IconImage: View {
    let icon: Icon
    let width: CGFloat?
    let height: CGFloat?

    init(_ icon: Icon, width: CGFloat? = 20, height: CGFloat? = 20) {
        self.icon = icon
        self.width = width
        self.height = height
    }

    var body: some View {
        Group {
            switch icon {
            case .sfSymbol(let sfSymbol, let color):
                Image(systemName: sfSymbol.rawValue)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
                    .foregroundColor(color)
                
            case .custom(let customIconName):
                Image(customIconName.rawValue)
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}
