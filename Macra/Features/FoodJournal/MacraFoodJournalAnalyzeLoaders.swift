import SwiftUI
import UIKit

/// Full-screen overlay shown while the Scan-food flow is uploading the photo
/// and running it through GPT vision. Cycles through stepped messaging so the
/// user gets reassurance that something technical is happening rather than the
/// screen appearing frozen for several seconds.
struct MacraAnalyzingFoodOverlay: View {
    let isVisible: Bool
    let photo: UIImage?

    @State private var currentStep: Int = 0
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.55
    @State private var arcRotation: Double = 0
    @State private var scanOffset: CGFloat = -1
    @State private var stepTimer: Timer?

    private struct Step {
        let icon: String
        let label: String
    }

    private let steps: [Step] = [
        Step(icon: "viewfinder", label: "Detecting items in your photo"),
        Step(icon: "ruler", label: "Estimating portions & quantities"),
        Step(icon: "function", label: "Calculating macros & ingredients"),
        Step(icon: "checkmark.seal.fill", label: "Saving to your journal")
    ]

    private let purple = Color(hex: "A78BFA")
    private let lime = Color(hex: "E0FE10")
    private let blue = Color(hex: "3B82F6")

    var body: some View {
        ZStack {
            if isVisible {
                Color.black.opacity(0.94)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 26) {
                    Spacer(minLength: 0)
                    centerVisual
                    headline
                    stepList
                    reassurance
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.32), value: isVisible)
        .onChange(of: isVisible) { newValue in
            if newValue {
                startSequence()
            } else {
                stopSequence()
            }
        }
        .onAppear {
            if isVisible { startSequence() }
        }
        .onDisappear {
            stopSequence()
        }
    }

    private var centerVisual: some View {
        ZStack {
            // Outermost pulsing aura
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [purple.opacity(0.55), lime.opacity(0.45), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 240, height: 240)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            // Mid stable ring
            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: 200, height: 200)

            // Rotating gradient arc (the "scanner")
            Circle()
                .trim(from: 0, to: 0.32)
                .stroke(
                    AngularGradient(
                        colors: [lime, purple, blue, lime],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 196, height: 196)
                .rotationEffect(.degrees(arcRotation))
                .blur(radius: 0.4)

            // Inner photo disc with traversing scan line
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 140, height: 140)

                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                        .saturation(0.85)
                        .overlay(
                            Circle().fill(
                                LinearGradient(
                                    colors: [.clear, purple.opacity(0.20), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        )
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [lime, purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }

                // Scan line traversing the photo
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, lime.opacity(0.95), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 140, height: 2.5)
                    .blur(radius: 1.5)
                    .offset(y: scanOffset * 56)
                    .opacity(0.95)
            }
            .frame(width: 140, height: 140)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [lime, purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
            )
            .shadow(color: lime.opacity(0.18), radius: 18, x: 0, y: 0)
        }
        .frame(width: 240, height: 240)
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text("ANALYZING")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2.4)
                .foregroundColor(lime)
            Text("Reading your food")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .tracking(-0.4)
                .foregroundColor(.white)
        }
    }

    private var stepList: some View {
        VStack(spacing: 8) {
            ForEach(steps.indices, id: \.self) { i in
                stepRow(index: i)
            }
        }
    }

    @ViewBuilder
    private func stepRow(index: Int) -> some View {
        let isActive = index == currentStep
        let isDone = index < currentStep
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? lime.opacity(0.18) : (isDone ? lime.opacity(0.12) : Color.white.opacity(0.05)))
                    .frame(width: 30, height: 30)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(lime)
                } else {
                    Image(systemName: steps[index].icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isActive ? lime : .white.opacity(0.35))
                }
            }
            Text(steps[index].label)
                .font(.system(size: 14, weight: isActive ? .semibold : .regular, design: .rounded))
                .foregroundColor(isActive ? .white : (isDone ? .white.opacity(0.78) : .white.opacity(0.4)))
            Spacer()
            if isActive {
                ProgressView()
                    .tint(lime)
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? lime.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isActive ? lime.opacity(0.34) : Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    private var reassurance: some View {
        Text("This usually takes a few seconds.")
            .font(.system(size: 12, weight: .regular, design: .default))
            .foregroundColor(.white.opacity(0.5))
    }

    private func startSequence() {
        currentStep = 0
        // Continuous animations
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            ringScale = 1.18
            ringOpacity = 0.20
        }
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            arcRotation = 360
        }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            scanOffset = 1
        }
        stepTimer?.invalidate()
        stepTimer = Timer.scheduledTimer(withTimeInterval: 1.7, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.4)) {
                    if currentStep < steps.count - 1 {
                        currentStep += 1
                    }
                }
            }
        }
    }

    private func stopSequence() {
        stepTimer?.invalidate()
        stepTimer = nil
        ringScale = 1.0
        ringOpacity = 0.55
        arcRotation = 0
        scanOffset = -1
        currentStep = 0
    }
}

/// Lightweight overlay shown the moment the user taps a "take photo" button
/// in the Scan flows. The system camera takes a beat to spin up — without
/// this the screen appears frozen during that window.
struct MacraCameraOpeningOverlay: View {
    let isVisible: Bool
    var message: String = "Opening camera…"

    @State private var pulse: CGFloat = 0.85

    private let lime = Color(hex: "E0FE10")
    private let purple = Color(hex: "A78BFA")

    var body: some View {
        ZStack {
            if isVisible {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                LinearGradient(colors: [lime, purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2
                            )
                            .frame(width: 64, height: 64)
                            .scaleEffect(pulse)
                            .opacity(2 - pulse)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(lime)
                    }
                    Text(message)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isVisible)
        .onChange(of: isVisible) { newValue in
            if newValue {
                pulse = 0.9
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = 1.25
                }
            }
        }
    }
}
