import Foundation
import SwiftUI
import UIKit

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

extension View {
    func dismissKeyboardOnTapOutside() -> some View {
        background(KeyboardDismissInstallingView())
    }
}

private struct KeyboardDismissInstallingView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = KeyboardDismissAttachmentView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.install(in: uiView.window)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        (uiView as? KeyboardDismissAttachmentView)?.onWindowChanged = nil
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private weak var tapGestureRecognizer: UITapGestureRecognizer?

        func install(in window: UIWindow?) {
            guard let window else { return }
            guard installedWindow !== window || tapGestureRecognizer == nil else { return }

            uninstall()

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self

            window.addGestureRecognizer(recognizer)
            installedWindow = window
            tapGestureRecognizer = recognizer
        }

        func uninstall() {
            if let tapGestureRecognizer {
                installedWindow?.removeGestureRecognizer(tapGestureRecognizer)
            }

            tapGestureRecognizer = nil
            installedWindow = nil
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            recognizer.view?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window = gestureRecognizer.view as? UIWindow ?? touch.view?.window else {
                return true
            }

            let touchPoint = touch.location(in: window)
            return !window.containsVisibleTextInput(at: touchPoint, in: window)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private final class KeyboardDismissAttachmentView: UIView {
    var onWindowChanged: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChanged?(window)
    }
}

private extension UIView {
    func containsVisibleTextInput(at point: CGPoint, in window: UIWindow) -> Bool {
        guard !isHidden, alpha > 0.01 else { return false }

        if isKeyboardEditableTextInput && isUserInteractionEnabled {
            let inputFrame = convert(bounds, to: window)
            if inputFrame.contains(point) {
                return true
            }
        }

        return subviews.contains { subview in
            subview.containsVisibleTextInput(at: point, in: window)
        }
    }

    var isKeyboardEditableTextInput: Bool {
        self is UITextField || self is UITextView || self is UISearchBar
    }
}
