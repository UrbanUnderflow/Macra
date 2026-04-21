import SwiftUI

final class IntroViewViewModel: ObservableObject {
    var serviceManager: ServiceManager
    var appCoordinator: AppCoordinator
    @Published var loginPressed = false
    @Published var newUser = false

    init(serviceManager: ServiceManager, appCoordinator: AppCoordinator) {
        self.serviceManager = serviceManager
        self.appCoordinator = appCoordinator
    }

    func newUserButtonPressed() {
        loginPressed = true
        newUser = true
    }

    func existingUserButtonPressed() {
        loginPressed = true
        newUser = false
    }
}

struct IntroView: View {
    @ObservedObject var viewModel: IntroViewViewModel

    var body: some View {
        ZStack {
            if viewModel.loginPressed {
                LoginView(
                    viewModel: LoginViewModel(
                        appCoordinator: viewModel.appCoordinator,
                        isSignUp: viewModel.newUser
                    )
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                AnimatedGradientMesh()
                    .ignoresSafeArea()

                heroContent
                    .transition(.opacity)
            }
        }
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MACRA")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.8)
                .foregroundColor(Color.primaryGreen)
                .padding(.top, 20)

            Spacer(minLength: 40)

            VStack(alignment: .leading, spacing: 18) {
                Text("Eat with\nmore clarity.")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("A nutrition plan built for your body, your goals, and your schedule.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 40)

            VStack(spacing: 14) {
                Button(action: primaryPressed) {
                    HStack(spacing: 10) {
                        Text("Get started")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(Color.secondaryCharcoal)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(
                            colors: [Color.primaryGreen, Color(hex: "C5EA17")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.primaryGreen.opacity(0.32), radius: 22, x: 0, y: 12)
                    .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 18)
                }
                .buttonStyle(.plain)

                Text("Takes about 2 minutes.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                Button(action: secondaryPressed) {
                    Text("I already have an account")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
    }

    private func primaryPressed() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            viewModel.newUserButtonPressed()
        }
    }

    private func secondaryPressed() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            viewModel.existingUserButtonPressed()
        }
    }
}

struct AnimatedGradientMesh: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { geo in
                let t = context.date.timeIntervalSinceReferenceDate

                ZStack {
                    Color(hex: "060709")

                    meshOrb(
                        color: Color.primaryGreen,
                        diameter: geo.size.width * 1.2,
                        center: animatedPoint(t: t, phase: 0.0, amplitude: 0.34, size: geo.size),
                        opacity: 0.55
                    )

                    meshOrb(
                        color: Color.primaryBlue,
                        diameter: geo.size.width * 1.05,
                        center: animatedPoint(t: t, phase: 2.1, amplitude: 0.32, size: geo.size),
                        opacity: 0.48
                    )

                    meshOrb(
                        color: Color.primaryPurple,
                        diameter: geo.size.width * 1.1,
                        center: animatedPoint(t: t, phase: 4.3, amplitude: 0.30, size: geo.size),
                        opacity: 0.42
                    )

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.35),
                                    Color.clear,
                                    Color.black.opacity(0.55)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
    }

    private func meshOrb(color: Color, diameter: CGFloat, center: CGPoint, opacity: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter * 0.28)
            .position(center)
            .allowsHitTesting(false)
    }

    private func animatedPoint(t: TimeInterval, phase: Double, amplitude: Double, size: CGSize) -> CGPoint {
        let period: Double = 22
        let omega = 2 * .pi / period
        let theta = omega * t + phase
        let dx = sin(theta) * amplitude * size.width
        let dy = cos(theta * 0.72) * amplitude * size.height
        return CGPoint(
            x: size.width / 2 + dx,
            y: size.height / 2 + dy
        )
    }
}

struct IntroScreen_Previews: PreviewProvider {
    static var previews: some View {
        IntroView(
            viewModel: IntroViewViewModel(
                serviceManager: ServiceManager(),
                appCoordinator: AppCoordinator(serviceManager: ServiceManager())
            )
        )
    }
}
