import SwiftUI

struct NoraOrb: View {
    var size: CGFloat = 48
    var isActive: Bool = false

    @State private var glowScale: CGFloat = 0.94
    @State private var ringScale: CGFloat = 0.98

    var body: some View {
        let ambientSize = size * (80.0 / 48.0)

        ZStack {
            Circle()
                .fill(Color(hex: "E0FE10").opacity(isActive ? 0.32 : 0.22))
                .frame(width: size * 1.15, height: size * 1.15)
                .blur(radius: size * (isActive ? 0.36 : 0.28))
                .scaleEffect(glowScale)

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(hex: "F4FF7A"), location: 0.0),
                            .init(color: Color(hex: "D4EA04"), location: 0.55),
                            .init(color: Color(hex: "9AAF06"), location: 1.0)
                        ]),
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: size * 0.04,
                        endRadius: size * 0.52
                    )
                )
                .frame(width: size * 0.82, height: size * 0.82)
                .overlay(
                    Circle()
                        .strokeBorder(Color(hex: "F7FBC6").opacity(0.55), lineWidth: 1)
                        .scaleEffect(ringScale)
                )
                .shadow(color: Color(hex: "E0FE10").opacity(0.42), radius: size * 0.28, x: 0, y: 0)

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.16
                    )
                )
                .frame(width: size * 0.34, height: size * 0.34)
                .offset(x: -size * 0.12, y: -size * 0.14)
                .blendMode(.plusLighter)
        }
        .frame(width: ambientSize, height: ambientSize)
        .onAppear { startBreathing(active: isActive) }
        .onChange(of: isActive) { active in
            startBreathing(active: active)
        }
    }

    private func startBreathing(active: Bool) {
        if active {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                glowScale = 1.26
                ringScale = 1.14
            }
        } else {
            withAnimation(.easeOut(duration: 0.22)) {
                glowScale = 1.0
                ringScale = 1.0
            }
        }
    }
}

struct TalkingNoraOrb: View {
    var size: CGFloat = 72
    var isSpeaking: Bool = false
    var voiceLevel: Double = 0

    var body: some View {
        let ambientSize = size * 1.86
        let energy = speechEnergy

        ZStack {
            Circle()
                .strokeBorder(
                    Color(hex: "E0FE10").opacity(0.08 + energy * 0.22),
                    lineWidth: 1
                )
                .frame(width: size * 1.48, height: size * 1.48)
                .scaleEffect(0.98 + energy * 0.18)
                .opacity(energy > 0 ? 0.42 : 0.0)

            Circle()
                .fill(Color(hex: "E0FE10").opacity(0.06 + energy * 0.18))
                .frame(width: size * 1.34, height: size * 1.34)
                .blur(radius: size * 0.24)
                .scaleEffect(0.98 + energy * 0.28)
                .opacity(energy > 0 ? 1.0 : 0.0)

            NoraOrb(size: size, isActive: false)
                .scaleEffect(1.0 + energy * 0.12)
                .offset(y: -energy * size * 0.045)
                .rotationEffect(.degrees((energy - 0.5) * 2.2))
        }
        .frame(width: ambientSize, height: ambientSize)
        .animation(.easeOut(duration: 0.08), value: voiceLevel)
        .animation(.easeOut(duration: 0.18), value: isSpeaking)
    }

    private var speechEnergy: CGFloat {
        guard isSpeaking else { return 0 }
        let level = CGFloat(max(0, min(1, voiceLevel)))
        guard level > 0.035 else { return 0 }
        return min(1, 0.16 + level * 0.92)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 32) {
            NoraOrb(size: 38)
            NoraOrb(size: 48)
            NoraOrb(size: 72, isActive: true)
            TalkingNoraOrb(size: 84, isSpeaking: true, voiceLevel: 0.55)
        }
    }
}
