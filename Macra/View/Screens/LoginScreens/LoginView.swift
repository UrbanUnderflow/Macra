import SwiftUI
import FirebaseAuth
import AuthenticationServices

final class LoginViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var isSignUp = false
    @Published var showPassword = false
    @Published var errorMessage: String?
    @Published var isWorking = false

    init(appCoordinator: AppCoordinator, isSignUp: Bool) {
        self.appCoordinator = appCoordinator
        self.isSignUp = isSignUp
    }

    var submitTitle: String {
        isSignUp ? "Create my account" : "Log in"
    }

    var headerTitle: String {
        isSignUp ? "Let’s get you started" : "Welcome back"
    }

    var headerBody: String {
        isSignUp
            ? "Create your account and start tracking meals, macros, and progress in just a minute."
            : "Log in to see today’s meals, your macro progress, and what’s next."
    }

    var passwordRequirements: [MacraAuthRequirement] {
        [
            MacraAuthRequirement(
                title: "8+ characters",
                isMet: password.count >= 8
            ),
            MacraAuthRequirement(
                title: "Uppercase letter",
                isMet: password.contains(where: \.isUppercase)
            ),
            MacraAuthRequirement(
                title: "Number",
                isMet: password.contains(where: \.isNumber)
            )
        ]
    }

    func submit() {
        errorMessage = nil

        guard isValidEmail(email) else {
            errorMessage = "Enter a valid email address."
            return
        }

        guard !password.isEmpty else {
            errorMessage = "Enter your password."
            return
        }

        if isSignUp {
            guard passwordRequirements.allSatisfy(\.isMet) else {
                errorMessage = "Your password needs at least 8 characters, one uppercase letter, and one number."
                return
            }

            guard password == confirmPassword else {
                errorMessage = "Your passwords do not match."
                return
            }

            signUp(email: email, password: password)
        } else {
            signIn(email: email, password: password)
        }
    }

    func forgotPasswordTapped() {
        errorMessage = nil

        guard isValidEmail(email) else {
            errorMessage = "Enter the email you used for your account first."
            return
        }

        isWorking = true
        Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines)) { [weak self] error in
            DispatchQueue.main.async {
                self?.isWorking = false
                if let error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.errorMessage = "Password reset email sent. Check your inbox and spam folder."
                }
            }
        }
    }

    func switchMode(isSignUp: Bool) {
        self.isSignUp = isSignUp
        self.errorMessage = nil
        self.password = ""
        self.confirmPassword = ""
        self.showPassword = false
    }

    private func signUp(email: String, password: String) {
        isWorking = true
        appCoordinator.signUpUser(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isWorking = false
                switch result {
                case .success:
                    self?.appCoordinator.handleLogin()
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func signIn(email: String, password: String) {
        isWorking = true
        appCoordinator.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isWorking = false
                switch result {
                case .success:
                    self?.appCoordinator.handleLogin()
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func signInWithApple() {
        errorMessage = nil
        isWorking = true
        appCoordinator.signInWithApple { [weak self] result in
            DispatchQueue.main.async {
                self?.isWorking = false
                switch result {
                case .success:
                    self?.appCoordinator.handleLogin()
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == ASAuthorizationError.errorDomain,
                       nsError.code == ASAuthorizationError.canceled.rawValue {
                        return
                    }
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: trimmed)
    }
}

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
        case confirmPassword
    }

    var body: some View {
        ZStack {
            MacraLoginAtmosphere()
                .ignoresSafeArea()

            MacraMealFeedBackdrop()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            MacraLoginVignette()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    MacraLoginHero(
                        isSignUp: viewModel.isSignUp
                    )
                    .padding(.top, 8)

                    authCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onTapGesture {
            focusedField = nil
        }
    }

    private var authCard: some View {
        MacraAuthSheet {
            VStack(alignment: .leading, spacing: 20) {
                MacraAuthTabSwitch(
                    isSignUp: viewModel.isSignUp,
                    onSelect: { mode in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            viewModel.switchMode(isSignUp: mode)
                        }
                    }
                )

                VStack(spacing: 12) {
                    MacraMinimalInputField(
                        title: "Email",
                        text: $viewModel.email,
                        prompt: "you@example.com",
                        textContentType: .emailAddress,
                        keyboardType: .emailAddress,
                        isSecure: false,
                        isFocused: focusedField == .email
                    )
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .password
                    }

                    MacraMinimalInputField(
                        title: "Password",
                        text: $viewModel.password,
                        prompt: "Enter your password",
                        textContentType: .password,
                        keyboardType: .default,
                        isSecure: !viewModel.showPassword,
                        isFocused: focusedField == .password,
                        trailingSystemImage: viewModel.showPassword ? "eye.slash" : "eye",
                        trailingAction: { viewModel.showPassword.toggle() }
                    )
                    .focused($focusedField, equals: .password)
                    .submitLabel(viewModel.isSignUp ? .next : .go)
                    .onSubmit {
                        focusedField = viewModel.isSignUp ? .confirmPassword : nil
                        if !viewModel.isSignUp {
                            viewModel.submit()
                        }
                    }

                    if viewModel.isSignUp {
                        MacraMinimalInputField(
                            title: "Confirm password",
                            text: $viewModel.confirmPassword,
                            prompt: "Re-enter your password",
                            textContentType: .password,
                            keyboardType: .default,
                            isSecure: !viewModel.showPassword,
                            isFocused: focusedField == .confirmPassword
                        )
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.go)
                        .onSubmit {
                            focusedField = nil
                            viewModel.submit()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                if viewModel.isSignUp {
                    HStack(spacing: 6) {
                        ForEach(viewModel.passwordRequirements) { requirement in
                            MacraRequirementTick(requirement: requirement)
                        }
                    }
                    .transition(.opacity)
                }

                if !viewModel.isSignUp {
                    Button(action: viewModel.forgotPasswordTapped) {
                        Text("Forgot password?")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, -4)
                }

                if let errorMessage = viewModel.errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(errorMessage.contains("sent") ? Color.primaryGreen : Color(hex: "FF8A80"))
                            .frame(width: 2)
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 2)
                }

                MacraPrimaryButton(
                    title: viewModel.submitTitle,
                    accent: Color.primaryGreen,
                    isLoading: viewModel.isWorking,
                    action: {
                        focusedField = nil
                        viewModel.submit()
                    }
                )

                MacraAuthDivider()

                MacraAppleAuthButton(
                    isSignUp: viewModel.isSignUp,
                    isWorking: viewModel.isWorking
                ) {
                    focusedField = nil
                    viewModel.signInWithApple()
                }
            }
        }
    }
}

// MARK: - Apple auth button + divider

struct MacraAuthDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
            Text("OR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(Color.white.opacity(0.35))
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
        }
    }
}

struct MacraAppleAuthButton: View {
    let isSignUp: Bool
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "applelogo")
                    .font(.system(size: 18, weight: .bold))
                Text(isSignUp ? "Sign up with Apple" : "Sign in with Apple")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .opacity(isWorking ? 0.6 : 1)
    }
}

// MARK: - Hero

struct MacraLoginHero: View {
    let isSignUp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                MacraBrandMark()
                Text("MACRA")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .tracking(2.6)
                    .foregroundColor(.white)
                Spacer()
                Text("EST. 2024")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundColor(.white.opacity(0.42))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(kicker)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(Color.primaryGreen)

                Text(headlineLine1)
                    .font(.system(size: 52, weight: .black, design: .serif))
                    .italic()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color.white.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.55), radius: 16, x: 0, y: 10)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(headlineLine2)
                        .font(.system(size: 52, weight: .black, design: .serif))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.primaryGreen, Color(hex: "F6FF6A")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color.primaryGreen.opacity(0.55), radius: 22, x: 0, y: 8)

                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Color.primaryGreen.opacity(0.7))
                        .padding(.bottom, 8)
                }
                .fixedSize(horizontal: false, vertical: true)

                Text(subcopy)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.68))
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var kicker: String {
        isSignUp ? "START HERE" : "WELCOME BACK"
    }

    private var headlineLine1: String {
        isSignUp ? "Eat with" : "Pick up"
    }

    private var headlineLine2: String {
        isSignUp ? "intention." : "the fork."
    }

    private var subcopy: String {
        isSignUp
            ? "Log a meal, learn your macros, and build the day your body actually wants."
            : "Your meals, your macros, your momentum — waiting right where you left them."
    }
}

struct MacraBrandMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.primaryGreen, Color(hex: "F6FF6A")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 22, height: 22)
                .shadow(color: Color.primaryGreen.opacity(0.55), radius: 10, x: 0, y: 2)

            Circle()
                .fill(Color.secondaryCharcoal)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Atmosphere (warm dark background)

struct MacraLoginAtmosphere: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            GeometryReader { geo in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    Color(hex: "0B0C0E")

                    radialBlob(
                        color: Color.primaryGreen,
                        diameter: geo.size.width * 1.1,
                        center: driftingPoint(t: t, phase: 0, size: geo.size, originX: 0.05, originY: -0.05, amplitude: 0.10),
                        opacity: 0.22
                    )

                    radialBlob(
                        color: Color(hex: "E8A33D"),
                        diameter: geo.size.width * 1.3,
                        center: driftingPoint(t: t, phase: 2.2, size: geo.size, originX: 1.05, originY: 0.0, amplitude: 0.08),
                        opacity: 0.18
                    )

                    radialBlob(
                        color: Color(hex: "E05F4A"),
                        diameter: geo.size.width * 1.0,
                        center: driftingPoint(t: t, phase: 4.1, size: geo.size, originX: 0.85, originY: 0.55, amplitude: 0.08),
                        opacity: 0.14
                    )

                    radialBlob(
                        color: Color.primaryPurple,
                        diameter: geo.size.width * 1.2,
                        center: driftingPoint(t: t, phase: 5.7, size: geo.size, originX: -0.1, originY: 1.05, amplitude: 0.08),
                        opacity: 0.22
                    )
                }
            }
        }
    }

    private func radialBlob(color: Color, diameter: CGFloat, center: CGPoint, opacity: Double) -> some View {
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
            .blur(radius: diameter * 0.25)
            .position(center)
    }

    private func driftingPoint(t: TimeInterval, phase: Double, size: CGSize, originX: CGFloat, originY: CGFloat, amplitude: Double) -> CGPoint {
        let period: Double = 28
        let omega = 2 * .pi / period
        let theta = omega * t + phase
        let dx = sin(theta) * amplitude * Double(size.width)
        let dy = cos(theta * 0.78) * amplitude * Double(size.height)
        return CGPoint(
            x: size.width * originX + CGFloat(dx),
            y: size.height * originY + CGFloat(dy)
        )
    }
}

// MARK: - Vignette

struct MacraLoginVignette: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.55),
                Color.clear,
                Color.black.opacity(0.35),
                Color.black.opacity(0.75)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Drifting meal-log feed

struct MacraMealFeedBackdrop: View {
    private static let entries: [MacraMealCardEntry] = [
        .init(emoji: "🥗", name: "Thai chicken salad", macros: "38P · 22C · 20F", kcal: 450, when: "2 min ago"),
        .init(emoji: "🍣", name: "Tuna sashimi", macros: "28P · 4C · 6F", kcal: 190, when: "6 min ago"),
        .init(emoji: "🥣", name: "Overnight oats", macros: "14P · 56C · 10F", kcal: 380, when: "11 min ago"),
        .init(emoji: "🫐", name: "Greek yogurt parfait", macros: "18P · 28C · 6F", kcal: 240, when: "19 min ago"),
        .init(emoji: "🍵", name: "Matcha latte", macros: "8P · 14C · 4F", kcal: 120, when: "24 min ago"),
        .init(emoji: "🐟", name: "Blackened salmon bowl", macros: "48P · 12C · 22F", kcal: 490, when: "31 min ago"),
        .init(emoji: "🥑", name: "Avocado toast", macros: "12P · 32C · 18F", kcal: 340, when: "42 min ago"),
        .init(emoji: "🥤", name: "Protein smoothie", macros: "32P · 24C · 4F", kcal: 280, when: "1 h ago"),
        .init(emoji: "🍝", name: "Chicken pesto pasta", macros: "44P · 52C · 16F", kcal: 560, when: "1 h ago"),
        .init(emoji: "🍳", name: "Spinach feta omelet", macros: "26P · 6C · 18F", kcal: 310, when: "1 h ago"),
        .init(emoji: "🌯", name: "Carnitas burrito bowl", macros: "42P · 48C · 18F", kcal: 620, when: "2 h ago"),
        .init(emoji: "🍎", name: "Apple + almond butter", macros: "4P · 28C · 14F", kcal: 240, when: "2 h ago")
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            GeometryReader { geo in
                let t = context.date.timeIntervalSinceReferenceDate

                ZStack {
                    column(entries: Self.entries, speed: 22, seed: 0, size: geo.size, t: t)
                        .frame(width: geo.size.width * 0.5 - 6, alignment: .leading)
                        .position(x: geo.size.width * 0.25, y: geo.size.height / 2)
                        .opacity(0.55)
                        .blur(radius: 0.3)

                    column(entries: Array(Self.entries.reversed()), speed: 30, seed: 1, size: geo.size, t: t)
                        .frame(width: geo.size.width * 0.5 - 6, alignment: .leading)
                        .position(x: geo.size.width * 0.75, y: geo.size.height / 2)
                        .opacity(0.45)
                        .blur(radius: 0.3)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black.opacity(0.7), location: 0.18),
                            .init(color: .black.opacity(0.75), location: 0.48),
                            .init(color: .clear, location: 0.62),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    private func column(entries: [MacraMealCardEntry], speed: Double, seed: Int, size: CGSize, t: TimeInterval) -> some View {
        let cardSpacing: CGFloat = 12
        let cardHeight: CGFloat = 64
        let stride: CGFloat = cardHeight + cardSpacing
        let totalHeight = stride * CGFloat(entries.count)
        let offsetRaw = CGFloat(t).truncatingRemainder(dividingBy: CGFloat(totalHeight / speed)) * CGFloat(speed)
        let baseOffset = -offsetRaw + CGFloat(seed) * 140

        let looped = entries + entries
        return VStack(spacing: cardSpacing) {
            ForEach(Array(looped.enumerated()), id: \.offset) { _, entry in
                MacraMealFeedCard(entry: entry)
                    .frame(height: cardHeight)
            }
        }
        .offset(y: baseOffset)
    }
}

struct MacraMealCardEntry: Hashable {
    let emoji: String
    let name: String
    let macros: String
    let kcal: Int
    let when: String
}

struct MacraMealFeedCard: View {
    let entry: MacraMealCardEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                Text(entry.emoji)
                    .font(.system(size: 22))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(entry.kcal) cal")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.primaryGreen.opacity(0.9))
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                    Text(entry.macros)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(entry.when)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        )
    }
}

// MARK: - Auth sheet (deep black, editorial)

struct MacraAuthSheet<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 22)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(hex: "0A0B0D"))

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.035),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.clear, Color.primaryGreen.opacity(0.9), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 60)
            .padding(.top, 0.5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 40, x: 0, y: 24)
    }
}

// MARK: - Tab switch (text tabs, no redundant pills)

struct MacraAuthTabSwitch: View {
    let isSignUp: Bool
    let onSelect: (Bool) -> Void

    var body: some View {
        HStack(spacing: 24) {
            tab(title: "Sign in", selected: !isSignUp) { onSelect(false) }
            tab(title: "Create account", selected: isSignUp) { onSelect(true) }
            Spacer()
        }
    }

    private func tab(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(selected ? .white : Color.white.opacity(0.38))

                Rectangle()
                    .fill(selected ? Color.primaryGreen : Color.clear)
                    .frame(height: 2)
                    .shadow(color: selected ? Color.primaryGreen.opacity(0.6) : .clear, radius: 6, x: 0, y: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Minimal input field (clean dark well with focus accent)

struct MacraMinimalInputField: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let textContentType: UITextContentType?
    let keyboardType: UIKeyboardType
    let isSecure: Bool
    let isFocused: Bool
    var trailingSystemImage: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(isFocused ? Color.primaryGreen : Color.white.opacity(0.38))

            HStack(spacing: 12) {
                Group {
                    if isSecure {
                        SecureField("", text: $text, prompt: Text(prompt).foregroundColor(Color.white.opacity(0.25)))
                    } else {
                        TextField("", text: $text, prompt: Text(prompt).foregroundColor(Color.white.opacity(0.25)))
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)

                if let trailingSystemImage {
                    Button(action: { trailingAction?() }) {
                        Image(systemName: trailingSystemImage)
                            .font(.system(size: 15))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "14161A"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.primaryGreen.opacity(0.7) : Color.white.opacity(0.06),
                        lineWidth: isFocused ? 1.2 : 1
                    )
            )
            .shadow(color: isFocused ? Color.primaryGreen.opacity(0.25) : .clear, radius: 10, x: 0, y: 0)
        }
    }
}

// MARK: - Requirement tick (compact)

struct MacraRequirementTick: View {
    let requirement: MacraAuthRequirement

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: requirement.isMet ? "checkmark" : "circle.dotted")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(requirement.isMet ? Color.primaryGreen : Color.white.opacity(0.35))
            Text(requirement.title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(requirement.isMet ? Color.white.opacity(0.9) : Color.white.opacity(0.45))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(requirement.isMet ? Color.primaryGreen.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    requirement.isMet ? Color.primaryGreen.opacity(0.4) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
    }
}

struct MacraAuthRequirement: Identifiable {
    let title: String
    let isMet: Bool

    var id: String { title }
}

struct MacraChromaticBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "050608"),
                    Color(hex: "0A0A0B"),
                    Color(hex: "101218")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            MacraOrb(color: Color.primaryGreen, size: 260, x: -120, y: -280)
            MacraOrb(color: Color.primaryBlue, size: 240, x: 150, y: -60)
            MacraOrb(color: Color.primaryPurple, size: 220, x: 100, y: 300)
            MacraOrb(color: Color(hex: "EF4444"), size: 170, x: -130, y: 420)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.clear,
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)
                .blur(radius: 1)
                .offset(x: -90)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)
                .blur(radius: 1)
                .offset(x: 100)
        }
    }
}

struct MacraOrb: View {
    let color: Color
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat

    var body: some View {
        Circle()
            .fill(color.opacity(0.18))
            .frame(width: size, height: size)
            .blur(radius: size * 0.35)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }
}

struct MacraGlassCard<Content: View>: View {
    let accent: Color
    let tint: Color
    let tintOpacity: Double
    let content: Content

    init(
        accent: Color,
        tint: Color,
        tintOpacity: Double,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.tint = tint
        self.tintOpacity = tintOpacity
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(tint.opacity(tintOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.clear,
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.55),
                                    accent.opacity(0.18),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: accent.opacity(0.2), radius: 24, x: 0, y: 12)
                .shadow(color: Color.black.opacity(0.32), radius: 30, x: 0, y: 18)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, accent.opacity(0.8), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
        }
    }
}

struct MacraAuthChipRow: View {
    let labels: [String]
    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
        }
    }
}

struct MacraAuthModeSwitch: View {
    let isSignUp: Bool
    let onSelect: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            modeButton(title: "Log in", selected: !isSignUp) {
                onSelect(false)
            }
            modeButton(title: "Sign up", selected: isSignUp) {
                onSelect(true)
            }
        }
    }

    private func modeButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(selected ? Color.secondaryCharcoal : Color.white.opacity(0.82))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(selected ? Color.primaryGreen : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(selected ? 0 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct MacraGlassInputField: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let textContentType: UITextContentType?
    let keyboardType: UIKeyboardType
    let isSecure: Bool
    var trailingSystemImage: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundColor(Color.white.opacity(0.45))

            HStack(spacing: 12) {
                Group {
                    if isSecure {
                        SecureField("", text: $text, prompt: Text(prompt).foregroundColor(Color.white.opacity(0.35)))
                    } else {
                        TextField("", text: $text, prompt: Text(prompt).foregroundColor(Color.white.opacity(0.35)))
                    }
                }
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)

                if let trailingSystemImage {
                    Button(action: { trailingAction?() }) {
                        Image(systemName: trailingSystemImage)
                            .foregroundColor(Color.white.opacity(0.55))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

struct MacraRequirementPill: View {
    let requirement: MacraAuthRequirement

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: requirement.isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(requirement.isMet ? Color.primaryGreen : Color.white.opacity(0.3))
            Text(requirement.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.white.opacity(0.82))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(requirement.isMet ? Color.primaryGreen.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MacraPrimaryButton: View {
    let title: String
    let accent: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(Color.secondaryCharcoal)
                }
                Text(isLoading ? "Working..." : title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundColor(Color.secondaryCharcoal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [accent, Color(hex: "C5EA17")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: accent.opacity(0.32), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.9 : 1)
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(
            viewModel: LoginViewModel(
                appCoordinator: AppCoordinator(serviceManager: ServiceManager()),
                isSignUp: false
            )
        )
    }
}
