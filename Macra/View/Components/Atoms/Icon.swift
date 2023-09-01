//
//  Icon.swift
//  QuickLifts
//
//  Created by Tremaine Grant on 7/4/23.
//

import Foundation
import SwiftUI

enum Icon: Equatable {
    case sfSymbol(_ icon:SFSymbols, color: Color?)
    case custom(CustomImages)

}

enum SFSymbols: String {
    case message = "message"
    case pencil = "pencil"
    case person = "person"
    case gear = "gear"
    case check = "checkmark.circle.fill"
    case close = "xmark.circle.fill"
    case chevRight = "chevron.right"
    case chevLeft = "chevron.left"
    case downArrow = "arrow.down"
    case upArrow = "arrow.up"
    case clock = "clock.fill"
    case upload = "square.and.arrow.up"
    case loading = "arrow.clockwise"
    case swap = "rectangle.2.swap"
    case heart = "heart"
    case heartFull = "heart.fill"
    case plus = "plus"
    case percentage = "percent"
    case intensity = "figure.highintensity.intervaltraining"
    case squareDownChev = "chevron.down.square.fill"
    case bookmark = "bookmark"
    case bookmarkFill = "bookmark.fill"
    case stretch = "figure.flexibility"
    case heartRate = "waveform.path.ecg"
    case training = "figure.strengthtraining.traditional"
    case bar = "chart.bar.fill"
    case pawPrint = "pawprint"
    case lock = "lock"
    case camera = "camera"
    case settings = "gearshape.fill"
    case minusCalendar = "calendar.badge.minus"
    case reload = "arrow.counterclockwise"
    case privacy = "lock.shield.fill"
    case doc = "doc"
}

enum CustomImages: String {
    case background = "macraBackground"
}
