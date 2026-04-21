import SwiftUI
import FirebaseAuth

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
            MacraChromaticBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("PULSE NUTRITION".uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundColor(Color.primaryGreen)

                        Text(viewModel.headerTitle)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text(viewModel.headerBody)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.72))

                        MacraAuthChipRow(labels: [
                            "Easy meal logging",
                            "Macro tracking",
                            "Daily momentum"
                        ])
                    }
                    .padding(.top, 36)

                    MacraGlassCard(accent: Color.primaryGreen, tint: Color.primaryGreen, tintOpacity: 0.08) {
                        VStack(alignment: .leading, spacing: 20) {
                            MacraAuthModeSwitch(
                                isSignUp: viewModel.isSignUp,
                                onSelect: { mode in
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        viewModel.switchMode(isSignUp: mode)
                                    }
                                }
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                Text(viewModel.isSignUp ? "Create your account" : "Log in to continue")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Text(viewModel.isSignUp ? "A few details now, and you’ll be ready to start logging meals right away." : "Pick up where you left off and get back to today’s nutrition.")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color.white.opacity(0.65))
                            }

                            VStack(spacing: 14) {
                                MacraGlassInputField(
                                    title: "Email",
                                    text: $viewModel.email,
                                    prompt: "you@example.com",
                                    textContentType: .emailAddress,
                                    keyboardType: .emailAddress,
                                    isSecure: false
                                )
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .password
                                }

                                MacraGlassInputField(
                                    title: "Password",
                                    text: $viewModel.password,
                                    prompt: "Enter your password",
                                    textContentType: .password,
                                    keyboardType: .default,
                                    isSecure: !viewModel.showPassword,
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
                                    MacraGlassInputField(
                                        title: "Confirm password",
                                        text: $viewModel.confirmPassword,
                                        prompt: "Re-enter your password",
                                        textContentType: .password,
                                        keyboardType: .default,
                                        isSecure: !viewModel.showPassword
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
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Choose a strong password")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .tracking(1.1)
                                        .foregroundColor(Color.white.opacity(0.5))

                                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                                        ForEach(viewModel.passwordRequirements) { requirement in
                                            MacraRequirementPill(requirement: requirement)
                                        }
                                    }
                                }
                                .transition(.opacity)
                            }

                            if !viewModel.isSignUp {
                                Button(action: viewModel.forgotPasswordTapped) {
                                    Text("Forgot password?")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Color.white.opacity(0.78))
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }

                            if let errorMessage = viewModel.errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(errorMessage.contains("sent") ? Color.primaryGreen : Color(hex: "FF8A80"))
                                    .fixedSize(horizontal: false, vertical: true)
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

                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    viewModel.switchMode(isSignUp: !viewModel.isSignUp)
                                }
                            }) {
                                Text(viewModel.isSignUp ? "Already have an account? Log in" : "New here? Create an account")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.72))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onTapGesture {
            focusedField = nil
        }
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
