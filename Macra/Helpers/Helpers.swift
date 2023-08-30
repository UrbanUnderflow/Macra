import Foundation
import SwiftUI

@discardableResult public func delay(_ delay: Double, closure: @escaping () -> Void) -> DispatchWorkItem {
    let task = DispatchWorkItem(block: closure)
    let deadline = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
    DispatchQueue.main.asyncAfter(
        deadline: deadline,
        execute: task)
    return task
}

@discardableResult public func main(closure: @escaping () -> Void) -> DispatchWorkItem {
    let task = DispatchWorkItem(block: closure)
    DispatchQueue.main.async(
        execute: task)
    return task
}

public func async(_ closure: @escaping () -> Void) {
    DispatchQueue.main.async {
        closure()
    }
}

public func formatDuration(startTime: Date?, currentTime: Date?) -> String? {
    guard let startTime = startTime, let currentTime = currentTime else {
        return nil
    }
    
    let elapsedTime = Int(currentTime.timeIntervalSince(startTime))
    let hours = elapsedTime / 3600
    let minutes = (elapsedTime % 3600) / 60
    let seconds = elapsedTime % 60
    
    var durationString = ""
    
    if hours > 0 {
        durationString += "\(hours) hour\(hours > 1 ? "s" : ""), "
    }
    
    if minutes > 0 {
        durationString += "\(minutes) min\(minutes > 1 ? "s" : ""), "
    }
    
    if seconds > 0 {
        durationString += "\(seconds) sec\(seconds > 1 ? "s" : "")"
    }
    
    // Remove trailing ", " if any
    if durationString.hasSuffix(", ") {
        durationString = String(durationString.dropLast(2))
    }
    
    return durationString
}

public func randomShadeColor() -> Color {
    let hue = Double.random(in: 0..<1) // Hue can be from 0 to 1
    let saturation: Double = 0.7  // Adjust as needed
    let brightness: Double = 0.9  // Adjust as needed based on the desired brightness
    return Color(hue: hue, saturation: saturation, brightness: brightness)
}
