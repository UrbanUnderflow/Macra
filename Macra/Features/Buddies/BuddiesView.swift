import SwiftUI
import FirebaseFirestore

/// Single sheet that lists the user's buddies, generates a new invite
/// link, accepts invites, and lets the user open a buddy's day-by-day
/// food journal from the list.
struct BuddiesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BuddiesViewModel()

    @State private var generatedInvite: BuddyInvite?
    @State private var pasteText: String = ""
    @State private var pasteErrorMessage: String?
    @State private var pendingInviteBanner: PendingInviteBannerState?

    private let accent = Color(hex: "8B5CF6")
    private let macraYellow = Color(hex: "E0FE10")

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "0A0B0F"), Color(hex: "111318")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ambientOrbs

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if let pendingInviteBanner {
                            pendingInviteCard(pendingInviteBanner)
                        }
                        hero
                        trustChipRow
                        generateLinkSection
                        addByLinkSection
                        incomingRequestsSection
                        buddiesSection
                        followersSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            viewModel.start()
            consumePendingInviteIfAny()
        }
        .onDisappear {
            viewModel.stop()
        }
        .onReceive(MacraDeepLinkService.sharedInstance.pendingInvitePublisher) { _ in
            consumePendingInviteIfAny()
        }
        .sheet(item: $generatedInvite) { invite in
            ShareInviteSheet(invite: invite)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var ambientOrbs: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [macraYellow.opacity(0.20), macraYellow.opacity(0.0)],
                    center: .center,
                    startRadius: 12,
                    endRadius: 170
                )
                .frame(width: 340, height: 340)
                    .offset(x: -90, y: -110)
                RadialGradient(
                    colors: [accent.opacity(0.24), accent.opacity(0.0)],
                    center: .center,
                    startRadius: 10,
                    endRadius: 155
                )
                .frame(width: 310, height: 310)
                .offset(x: geo.size.width - 130, y: 45)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            BuddyNetworkVisual()
                .frame(height: 132)
                .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("BUDDIES")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.4)
            }
            .foregroundColor(accent)

            heroHeadline

            Text(viewModel.buddies.isEmpty
                 ? "Send a friend your link. They'll see your daily meals — you stay in the driver's seat. They share theirs back if they want."
                 : "Generate a link, send one back, or tap a buddy to view their meals by day.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var heroHeadline: some View {
        if viewModel.buddies.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Eat together,")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("accountable together.")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [macraYellow, accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Your buddy hub.")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var trustChipRow: some View {
        HStack(spacing: 8) {
            trustChip(icon: "lock.fill", label: "Private")
            trustChip(icon: "paperplane.fill", label: "Tap to share")
            trustChip(icon: "hand.raised.fill", label: "Stop anytime")
        }
    }

    private func trustChip(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white.opacity(0.78))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var generateLinkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SHARE YOUR JOURNAL", tint: macraYellow)

            ShimmerCTA(
                title: viewModel.isGeneratingInvite ? "Generating…" : "Generate buddy link",
                icon: viewModel.isGeneratingInvite ? "hourglass" : "link.circle.fill",
                isWorking: viewModel.isGeneratingInvite
            ) {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                viewModel.generateInvite { result in
                    if case .success(let invite) = result {
                        let success = UINotificationFeedbackGenerator()
                        success.notificationOccurred(.success)
                        generatedInvite = invite
                    }
                }
            }
            .disabled(viewModel.isGeneratingInvite)

            if let errorMessage = viewModel.generateErrorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "FF6B6B"))
            }
        }
    }

    private var addByLinkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("FOLLOW SOMEONE", tint: accent)

            ZStack(alignment: .topLeading) {
                if pasteText.isEmpty {
                    Text("Paste a buddy link here…")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.32))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextField("", text: $pasteText, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

            HStack(spacing: 8) {
                if let pasteErrorMessage, !pasteErrorMessage.isEmpty {
                    Text(pasteErrorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "FF6B6B"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                Button {
                    submitPasteToken()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isAcceptingInvite ? "hourglass" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(viewModel.isAcceptingInvite ? "Adding…" : "Follow")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isAcceptingInvite || pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity((viewModel.isAcceptingInvite || pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1)
            }
        }
    }

    private var buddiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 10, weight: .bold))
                    sectionHeader("SHARING WITH YOU", tint: .white.opacity(0.55))
                }
                Spacer()
                Text("\(viewModel.buddies.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }

            if viewModel.isLoading && viewModel.buddies.isEmpty {
                ProgressView().tint(accent).frame(maxWidth: .infinity).padding(20)
            } else if viewModel.buddies.isEmpty {
                EmptyBuddiesCard()
            } else {
                ForEach(viewModel.buddies) { buddy in
                    NavigationLink {
                        BuddyDayView(buddy: buddy)
                    } label: {
                        BuddyCardView(
                            buddy: buddy,
                            isUnfollowing: viewModel.unfollowingIds.contains(buddy.id)
                        ) {
                            viewModel.unfollow(buddy: buddy)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var incomingRequestsSection: some View {
        if !viewModel.incomingRequests.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 10, weight: .bold))
                        sectionHeader("ASKING TO SEE YOUR MEALS", tint: macraYellow)
                    }
                    Spacer()
                    Text("\(viewModel.incomingRequests.count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(macraYellow.opacity(0.85))
                }

                ForEach(viewModel.incomingRequests) { request in
                    IncomingRequestCardView(
                        request: request,
                        isResponding: viewModel.respondingToRequestUids.contains(request.fromUid),
                        onAccept: {
                            let haptic = UINotificationFeedbackGenerator()
                            haptic.notificationOccurred(.success)
                            viewModel.acceptIncomingRequest(request)
                        },
                        onDecline: {
                            viewModel.declineIncomingRequest(request)
                        }
                    )
                }
            }
        }
    }

    private var followersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 10, weight: .bold))
                    sectionHeader("WHO YOU'RE SHARING WITH", tint: .white.opacity(0.55))
                }
                Spacer()
                Text("\(viewModel.followers.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }

            if viewModel.isLoadingFollowers && viewModel.followers.isEmpty {
                ProgressView()
                    .tint(accent)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else if viewModel.followers.isEmpty {
                Text("No one yet. Once a friend accepts your link, they'll show up here — tap Share back to swap and see their journal too.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.50))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            } else {
                ForEach(viewModel.followers) { follower in
                    FollowerCardView(
                        follower: follower,
                        isMutual: viewModel.followingUids.contains(follower.followerUid),
                        hasPendingRequest: viewModel.outgoingRequestUids.contains(follower.followerUid),
                        isRequestInProgress: viewModel.requestingShareBackUids.contains(follower.followerUid),
                        isRevoking: viewModel.revokingShareIds.contains(follower.followerUid),
                        onRequestShareBack: {
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                            viewModel.requestShareBack(follower: follower)
                        },
                        onWithdrawRequest: {
                            viewModel.withdrawShareRequest(targetUid: follower.followerUid)
                        },
                        onRevoke: {
                            viewModel.revokeShare(follower: follower)
                        }
                    )
                }
            }
        }
    }

    private func sectionHeader(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundColor(tint)
    }

    private func submitPasteToken() {
        pasteErrorMessage = nil
        guard let token = BuddyURLParser.token(from: pasteText) else {
            pasteErrorMessage = BuddyError.malformedURL.errorDescription
            return
        }
        viewModel.acceptInvite(token: token) { result in
            switch result {
            case .success:
                pasteText = ""
            case .failure(let error):
                pasteErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Pending invite (deep-link arrival)

    /// Drains `MacraDeepLinkService.pendingInviteToken` and turns it into
    /// an in-sheet banner the user explicitly accepts. We never auto-add
    /// the buddy on token arrival — the user might have tapped a stale
    /// link, or might want to confirm before following.
    private func consumePendingInviteIfAny() {
        guard let token = MacraDeepLinkService.sharedInstance.pendingInviteToken,
              !token.isEmpty else { return }
        // Avoid showing the banner twice for the same token if `onReceive`
        // fires while we already have it staged.
        if pendingInviteBanner?.token == token { return }
        pendingInviteBanner = PendingInviteBannerState(token: token, status: .ready)
    }

    private func pendingInviteCard(_ state: PendingInviteBannerState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("INVITE READY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.4)
            }
            .foregroundColor(macraYellow)

            Text(message(for: state.status))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            let isReady: Bool = { if case .ready = state.status { return true } else { return false } }()
            let isFailed: Bool = { if case .failed = state.status { return true } else { return false } }()
            let isAccepted: Bool = { if case .accepted = state.status { return true } else { return false } }()

            HStack(spacing: 10) {
                if isReady || isFailed {
                    Button {
                        acceptPendingInvite(token: state.token)
                    } label: {
                        Text(isFailed ? "Try again" : "Accept invite")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(macraYellow))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    pendingInviteBanner = nil
                    MacraDeepLinkService.sharedInstance.clearPendingInvite()
                } label: {
                    Text(isAccepted ? "Dismiss" : "Ignore")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(macraYellow.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(macraYellow.opacity(0.32), lineWidth: 1))
    }

    private func message(for status: PendingInviteBannerState.Status) -> String {
        switch status {
        case .ready:
            return "Someone shared a buddy link with you. Accept to follow their meal log."
        case .accepting:
            return "Accepting invite…"
        case .accepted:
            return "You're now following them. Their journal is in the list below."
        case .failed(let detail):
            return detail
        }
    }

    private func acceptPendingInvite(token: String) {
        pendingInviteBanner = PendingInviteBannerState(token: token, status: .accepting)
        viewModel.acceptInvite(token: token) { result in
            switch result {
            case .success:
                pendingInviteBanner = PendingInviteBannerState(token: token, status: .accepted)
                MacraDeepLinkService.sharedInstance.clearPendingInvite()
            case .failure(let error):
                pendingInviteBanner = PendingInviteBannerState(
                    token: token,
                    status: .failed(error.localizedDescription)
                )
            }
        }
    }
}

/// View-local state for the deep-link banner. Tracks the token so we can
/// retry the same invite, plus a status enum so the banner can swap
/// label/buttons without juggling multiple `@State` flags.
private struct PendingInviteBannerState: Equatable {
    enum Status: Equatable {
        case ready
        case accepting
        case accepted
        case failed(String)
    }
    let token: String
    var status: Status
}

// MARK: - Network hero

/// Two avatar bubbles connected by a dotted curve, with meal markers moving
/// along the path. The motion is isolated in a low-fps `Canvas`, which keeps
/// the rest of the sheet from redrawing while the hero animates.
private struct BuddyNetworkVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lime = Color(hex: "E0FE10")
    private let purple = Color(hex: "8B5CF6")
    private let blue = Color(hex: "3B82F6")
    private let mealEmojis = ["🥗", "🍳", "🍣"]

    var body: some View {
        Group {
            if reduceMotion {
                heroCanvas(date: nil)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                    heroCanvas(date: timeline.date)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You sharing meals with a buddy")
    }

    private func heroCanvas(date: Date?) -> some View {
        Canvas { context, size in
            let t = CGFloat(date?.timeIntervalSinceReferenceDate ?? 0)
            let isAnimated = date != nil
            let w = size.width
            let h = size.height
            let leftCenter = CGPoint(x: w * 0.26, y: h * 0.55)
            let rightCenter = CGPoint(x: w * 0.74, y: h * 0.55)
            let control = CGPoint(
                x: w * 0.5,
                y: h * 0.19 + (isAnimated ? CGFloat(sin(t)) * 5 : 0)
            )

            var curve = Path()
            curve.move(to: leftCenter)
            curve.addQuadCurve(to: rightCenter, control: control)
            context.stroke(
                curve,
                with: .linearGradient(
                    Gradient(colors: [lime.opacity(0.58), purple.opacity(0.62)]),
                    startPoint: leftCenter,
                    endPoint: rightCenter
                ),
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    dash: [3, 7],
                    dashPhase: isAnimated ? -t * 18 : 0
                )
            )

            for i in mealEmojis.indices {
                let base = CGFloat(i) / CGFloat(mealEmojis.count)
                let progress = isAnimated
                    ? (t * 0.16 + base).truncatingRemainder(dividingBy: 1.0)
                    : [CGFloat(0.30), CGFloat(0.50), CGFloat(0.68)][i]
                let pt = quadPoint(t: progress, p0: leftCenter, p1: control, p2: rightCenter)
                var emojiContext = context
                emojiContext.opacity = isAnimated ? emojiOpacity(progress) : 1
                emojiContext.draw(
                    Text(mealEmojis[i]).font(.system(size: 22)),
                    at: pt
                )
            }

            var drawingContext = context
            let leftBob = isAnimated ? CGFloat(sin(t * 1.3)) * 3 : 0
            let rightBob = isAnimated ? CGFloat(cos(t * 1.3)) * 3 : 0
            drawAvatar(
                in: &drawingContext,
                center: CGPoint(x: leftCenter.x, y: leftCenter.y + leftBob),
                label: "YOU",
                colors: [lime, Color(hex: "C8E60D")],
                textColor: .black,
                glow: lime
            )
            drawAvatar(
                in: &drawingContext,
                center: CGPoint(x: rightCenter.x, y: rightCenter.y + rightBob),
                label: "+1",
                colors: [purple, blue],
                textColor: .white,
                glow: purple
            )
        }
        .allowsHitTesting(false)
    }

    private func emojiOpacity(_ p: CGFloat) -> Double {
        if p < 0.12 { return Double(p / 0.12) }
        if p > 0.88 { return Double((1.0 - p) / 0.12) }
        return 1.0
    }

    private func quadPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
            y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
        )
    }

    private func drawAvatar(
        in context: inout GraphicsContext,
        center: CGPoint,
        label: String,
        colors: [Color],
        textColor: Color,
        glow: Color
    ) {
        let diameter: CGFloat = 58
        let rect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let avatarPath = Path(ellipseIn: rect)

        var shadowContext = context
        shadowContext.addFilter(.shadow(color: glow.opacity(0.24), radius: 9, x: 0, y: 5))
        shadowContext.fill(
            avatarPath,
            with: .linearGradient(
                Gradient(colors: colors),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        )

        context.stroke(avatarPath, with: .color(.white.opacity(0.18)), lineWidth: 1)
        context.draw(
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(textColor),
            at: center
        )
    }
}

// MARK: - Shimmer CTA

/// The primary "Generate buddy link" pill. The lime gradient base and label
/// are static SwiftUI; the moving highlight is rendered in an isolated Canvas
/// overlay so the surrounding view tree doesn't recompose each frame (that
/// was the source of the earlier scroll-glitching).
private struct ShimmerCTA: View {
    let title: String
    let icon: String
    let isWorking: Bool
    let action: () -> Void

    private let lime = Color(hex: "E0FE10")
    private let limeDeep = Color(hex: "C8E60D")

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [lime, limeDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if !isWorking {
                    ShimmerOverlay()
                        .allowsHitTesting(false)
                }

                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                    Text(title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .clipShape(Capsule())
            .shadow(color: lime.opacity(0.32), radius: 14, x: 0, y: 7)
        }
        .buttonStyle(.plain)
    }
}

/// Diagonal white shimmer band that sweeps left → right across the parent
/// every 2.4s. Drawn in a Canvas at 30fps so the only thing redrawing is a
/// single rasterized layer — no SwiftUI tree diffing per frame, no
/// blend-mode contention with shadows in the parent.
private struct ShimmerOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let cycle: Double = 2.4

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let raw = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: cycle)
                    let progress = CGFloat(raw / cycle)
                    let bandWidth = size.width * 0.32
                    let travel = size.width + bandWidth
                    let x = -bandWidth + travel * progress

                    let bandRect = CGRect(x: x, y: 0, width: bandWidth, height: size.height)
                    context.fill(
                        Path(bandRect),
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: .white.opacity(0), location: 0),
                                .init(color: .white.opacity(0.55), location: 0.5),
                                .init(color: .white.opacity(0), location: 1)
                            ]),
                            startPoint: CGPoint(x: bandRect.minX, y: 0),
                            endPoint: CGPoint(x: bandRect.maxX, y: 0)
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Empty buddies card

/// Empty state for the "Who you're following" list. Three softly pulsing
/// ghost avatar slots, all rendered in one Canvas driven by a single
/// timeline — earlier we had a TimelineView per avatar, which compounded
/// SwiftUI redraws and caused scroll glitching.
private struct EmptyBuddiesCard: View {
    var body: some View {
        VStack(spacing: 14) {
            GhostAvatarRow()
                .frame(height: 46)

            VStack(spacing: 4) {
                Text("Your accountability circle, empty for now.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Tap Generate buddy link to invite your first friend.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct GhostAvatarRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Ghost {
        let letter: String
        let colors: [Color]
        let phase: CGFloat
    }

    private let ghosts: [Ghost] = [
        Ghost(letter: "S", colors: [Color(hex: "8B5CF6"), Color(hex: "3B82F6")], phase: 0.0),
        Ghost(letter: "M", colors: [Color(hex: "3B82F6"), Color(hex: "06B6D4")], phase: 0.9),
        Ghost(letter: "A", colors: [Color(hex: "E0FE10"), Color(hex: "C8E60D")], phase: 1.8)
    ]

    var body: some View {
        Group {
            if reduceMotion {
                ghostsCanvas(date: nil)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
                    ghostsCanvas(date: timeline.date)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func ghostsCanvas(date: Date?) -> some View {
        Canvas { context, size in
            let t = CGFloat(date?.timeIntervalSinceReferenceDate ?? 0)
            let isAnimated = date != nil
            let diameter: CGFloat = 46
            let overlap: CGFloat = 10
            let totalWidth = diameter * 3 - overlap * 2
            let firstCx = (size.width - totalWidth) / 2 + diameter / 2
            let cy = size.height / 2

            for (i, ghost) in ghosts.enumerated() {
                let cx = firstCx + CGFloat(i) * (diameter - overlap)
                let pulse: CGFloat = isAnimated
                    ? 0.55 + 0.15 * (CGFloat(sin(t * 1.2 + ghost.phase)) + 1) / 2
                    : 0.70 - CGFloat(i) * 0.08

                let rect = CGRect(
                    x: cx - diameter / 2,
                    y: cy - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                let path = Path(ellipseIn: rect)

                context.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: ghost.colors.map { $0.opacity(Double(pulse)) }),
                        startPoint: CGPoint(x: rect.minX, y: rect.minY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                    )
                )
                context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 2)
                context.draw(
                    Text(ghost.letter)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.85)),
                    at: CGPoint(x: cx, y: cy)
                )
            }
        }
    }
}

// MARK: - Buddy card

private struct BuddyCardView: View {
    let buddy: BuddyConnection
    let isUnfollowing: Bool
    let onUnfollow: () -> Void

    @State private var confirmingUnfollow: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(buddy.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let email = buddy.targetEmail, email != buddy.displayName {
                    Text(email)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                confirmingUnfollow = true
            } label: {
                Text(isUnfollowing ? "Removing…" : "Unfollow")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "FF6B6B"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color(hex: "FF6B6B").opacity(0.10)))
                    .overlay(Capsule().strokeBorder(Color(hex: "FF6B6B").opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isUnfollowing)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .opacity(isUnfollowing ? 0.55 : 1)
        .confirmationDialog("Stop seeing \(buddy.displayName)'s meals?", isPresented: $confirmingUnfollow, titleVisibility: .visible) {
            Button("Stop seeing", role: .destructive) { onUnfollow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their journal will leave your buddy hub. You can re-add them anytime with their link.")
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = buddy.targetProfileImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    fallbackAvatar
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        let initial = (buddy.displayName.first.map { String($0) } ?? "?").uppercased()
        return ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Color(hex: "8B5CF6"), Color(hex: "3B82F6")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(initial)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
}

// MARK: - Follower card

/// Row representing someone the user shares their journal with. A single
/// inline button reflects the row's current state: tap "Share back" on
/// a one-way follower to instantly become mutual (writes a buddy doc on
/// our side using the cached profile snapshot — no token round-trip).
/// Mutual rows expose a "Stop sharing" button that revokes their access
/// to our meals via a destructive confirmation. Long-press surfaces the
/// same revoke action for consistency on one-way rows.
private struct FollowerCardView: View {
    let follower: BuddyFollower
    let isMutual: Bool
    let hasPendingRequest: Bool
    let isRequestInProgress: Bool
    let isRevoking: Bool
    let onRequestShareBack: () -> Void
    let onWithdrawRequest: () -> Void
    let onRevoke: () -> Void

    @State private var confirmingRevoke: Bool = false

    private let accent = Color(hex: "8B5CF6")
    private let macraYellow = Color(hex: "E0FE10")
    private let blue = Color(hex: "3B82F6")
    private let coral = Color(hex: "FF6B6B")

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(follower.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if isMutual {
                        mutualBadge
                    }
                }
                if let email = follower.followerEmail, email != follower.displayName {
                    Text(email)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer()
            actionButton
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isMutual ? macraYellow.opacity(0.20) : Color.white.opacity(0.10),
                    lineWidth: 1
                )
        )
        .opacity(isRevoking ? 0.55 : 1)
        .contextMenu {
            Button(role: .destructive) {
                confirmingRevoke = true
            } label: {
                Label("Stop sharing with \(follower.displayName)", systemImage: "person.fill.xmark")
            }
        }
        .confirmationDialog(
            "Stop sharing with \(follower.displayName)?",
            isPresented: $confirmingRevoke,
            titleVisibility: .visible
        ) {
            Button("Stop sharing", role: .destructive) { onRevoke() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll stop seeing your meals. You can re-share anytime by sending them a fresh link.")
        }
    }

    private var mutualBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 8, weight: .bold))
            Text("MUTUAL")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.0)
        }
        .foregroundColor(macraYellow)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(macraYellow.opacity(0.12)))
        .overlay(Capsule().strokeBorder(macraYellow.opacity(0.32), lineWidth: 1))
    }

    @ViewBuilder
    private var actionButton: some View {
        if isMutual {
            // Already mutual — primary affordance is revoking access.
            Button {
                confirmingRevoke = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isRevoking ? "hourglass" : "person.fill.xmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(isRevoking ? "Removing…" : "Stop sharing")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(coral)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(coral.opacity(0.10)))
                .overlay(Capsule().strokeBorder(coral.opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isRevoking)
        } else if hasPendingRequest {
            // Outgoing request awaiting their response. Tapping again
            // withdraws the request.
            Button(action: onWithdrawRequest) {
                HStack(spacing: 4) {
                    Image(systemName: isRequestInProgress ? "hourglass" : "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(isRequestInProgress ? "Cancelling…" : "Requested")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(macraYellow)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(macraYellow.opacity(0.10)))
                .overlay(Capsule().strokeBorder(macraYellow.opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isRequestInProgress)
        } else {
            // One-way follower with no outgoing request — primary
            // affordance is asking them to share their journal too.
            Button(action: onRequestShareBack) {
                HStack(spacing: 4) {
                    Image(systemName: isRequestInProgress ? "hourglass" : "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(isRequestInProgress ? "Sending…" : "Request to share back")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [accent.opacity(0.30), blue.opacity(0.18)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [accent.opacity(0.55), blue.opacity(0.35)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(isRequestInProgress)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = follower.followerProfileImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    fallbackAvatar
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        let initial = (follower.displayName.first.map { String($0) } ?? "?").uppercased()
        return ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [accent, blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(initial)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
}

// MARK: - Incoming request card

/// Row representing someone who's asked me to share my journal back.
/// Two inline actions: accept (lime gradient → grants them a buddy doc
/// on my behalf and clears the request) or decline (subtle white outline
/// → just deletes the request, no buddy created).
private struct IncomingRequestCardView: View {
    let request: BuddyShareRequest
    let isResponding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    private let accent = Color(hex: "8B5CF6")
    private let macraYellow = Color(hex: "E0FE10")
    private let blue = Color(hex: "3B82F6")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let email = request.fromEmail, email != request.displayName {
                        Text(email)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                    Text("Requesting you share your eating habits with them")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button(action: onAccept) {
                    HStack(spacing: 6) {
                        Image(systemName: isResponding ? "hourglass" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(isResponding ? "Sharing…" : "Share with them")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [macraYellow, Color(hex: "C8E60D")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isResponding)

                Button(action: onDecline) {
                    Text("Decline")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isResponding)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(macraYellow.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [macraYellow.opacity(0.50), accent.opacity(0.30)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .opacity(isResponding ? 0.55 : 1)
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = request.fromProfileImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    fallbackAvatar
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(macraYellow.opacity(0.45), lineWidth: 2))
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        let initial = (request.displayName.first.map { String($0) } ?? "?").uppercased()
        return ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [accent, blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(initial)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().strokeBorder(macraYellow.opacity(0.45), lineWidth: 2))
    }
}

// MARK: - Share invite sheet

/// Reveals the freshly-created invite URL with copy + share controls.
/// Built as a child sheet so the parent BuddiesView stays a clean
/// dashboard — generating a new link doesn't push the user out of the
/// list view.
struct ShareInviteSheet: View {
    let invite: BuddyInvite
    @Environment(\.dismiss) private var dismiss

    @State private var didCopy = false
    /// Resolved share URL — starts as the long-form fallback so the UI
    /// has something the moment the sheet mounts, then upgrades to the
    /// short OneLink once `MacraDeepLinkService.shareURL` returns.
    @State private var resolvedShareURL: URL?
    @State private var isResolving: Bool = true

    private let accent = Color(hex: "E0FE10")

    private var shareURLString: String {
        resolvedShareURL?.absoluteString ?? "Generating link…"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "0A0B0F"), Color(hex: "111318")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    Text("YOUR BUDDY LINK")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(accent)

                    Text("Send this to anyone you want following your meals. Whoever opens it joins as a buddy — they see your journal.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Text(shareURLString)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(isResolving ? .white.opacity(0.55) : .white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        if isResolving {
                            ProgressView()
                                .tint(accent)
                                .scaleEffect(0.7)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

                    HStack(spacing: 10) {
                        Button {
                            guard let url = resolvedShareURL else { return }
                            UIPasteboard.general.string = url.absoluteString
                            didCopy = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: didCopy ? "checkmark" : "doc.on.doc.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(didCopy ? "Copied" : "Copy link")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(resolvedShareURL == nil)
                        .opacity(resolvedShareURL == nil ? 0.5 : 1)

                        // ShareLink expects a non-optional URL; while the
                        // shortener is running we show a disabled visual
                        // and only become tappable once we have a URL.
                        ShareLink(item: resolvedShareURL ?? URL(string: "https://fitwithpulse.ai/macra")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Share")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(accent))
                        }
                        .buttonStyle(.plain)
                        .disabled(resolvedShareURL == nil)
                        .opacity(resolvedShareURL == nil ? 0.5 : 1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear { resolveShareURL() }
    }

    /// Asks `MacraDeepLinkService` for the short OneLink (or long-form
    /// fallback) the moment the sheet mounts. Resolution is async because
    /// AppsFlyer's shortener round-trips through their CDN; the spinner
    /// next to the URL pill keeps the user oriented while it lands.
    private func resolveShareURL() {
        isResolving = true
        MacraDeepLinkService.sharedInstance.shareURL(forToken: invite.id) { url in
            self.resolvedShareURL = url
            self.isResolving = false
        }
    }
}

// MARK: - View model

/// Lightweight observable just for the home-screen buddies-icon badge.
/// Owns its own incoming-requests listener so HomeView can render the
/// count without spinning up the full BuddiesViewModel until the sheet
/// is actually opened. Call `start()` on appear, `stop()` on disappear.
@MainActor
final class BuddyRequestsBadgeState: ObservableObject {
    @Published var pendingCount: Int = 0

    private var listener: ListenerRegistration?

    func start() {
        guard listener == nil else { return }
        listener = BuddyService.sharedInstance.observeIncomingRequests { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let requests) = result {
                    self.pendingCount = requests.count
                }
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }
}

@MainActor
final class BuddiesViewModel: ObservableObject {
    @Published var buddies: [BuddyConnection] = []
    @Published var followers: [BuddyFollower] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingFollowers: Bool = false
    @Published var isGeneratingInvite: Bool = false
    @Published var isAcceptingInvite: Bool = false
    @Published var generateErrorMessage: String?
    @Published var unfollowingIds: Set<String> = []
    @Published var revokingShareIds: Set<String> = []
    @Published var incomingRequests: [BuddyShareRequest] = []
    @Published var outgoingRequestUids: Set<String> = []
    @Published var requestingShareBackUids: Set<String> = []
    @Published var respondingToRequestUids: Set<String> = []

    /// Set of uids the user already follows back. Computed from `buddies`
    /// so the followers list can flag mutual relationships.
    var followingUids: Set<String> {
        Set(buddies.map { $0.targetUid })
    }

    private var listener: ListenerRegistration?
    private var followersListener: ListenerRegistration?
    private var incomingRequestsListener: ListenerRegistration?
    private var outgoingRequestsListener: ListenerRegistration?

    func start() {
        guard listener == nil else { return }
        isLoading = true
        listener = BuddyService.sharedInstance.observeBuddies { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let buddies):
                    self.buddies = buddies
                case .failure(let error):
                    self.generateErrorMessage = error.localizedDescription
                }
            }
        }

        if followersListener == nil {
            isLoadingFollowers = true
            followersListener = BuddyService.sharedInstance.observeFollowers { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isLoadingFollowers = false
                    if case .success(let followers) = result {
                        self.followers = followers
                    }
                    // Errors here are silent — the followers list is
                    // discovery, not critical path. The listener will
                    // retry on next start().
                }
            }
        }

        if incomingRequestsListener == nil {
            incomingRequestsListener = BuddyService.sharedInstance.observeIncomingRequests { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if case .success(let requests) = result {
                        self.incomingRequests = requests
                    }
                }
            }
        }

        if outgoingRequestsListener == nil {
            outgoingRequestsListener = BuddyService.sharedInstance.observeOutgoingRequests { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if case .success(let uids) = result {
                        self.outgoingRequestUids = uids
                    }
                }
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        followersListener?.remove()
        followersListener = nil
        incomingRequestsListener?.remove()
        incomingRequestsListener = nil
        outgoingRequestsListener?.remove()
        outgoingRequestsListener = nil
    }

    func generateInvite(completion: @escaping (Result<BuddyInvite, Error>) -> Void) {
        isGeneratingInvite = true
        generateErrorMessage = nil
        BuddyService.sharedInstance.createInvite { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isGeneratingInvite = false
                if case .failure(let error) = result {
                    self.generateErrorMessage = error.localizedDescription
                }
                completion(result)
            }
        }
    }

    func acceptInvite(token: String, completion: @escaping (Result<BuddyConnection, Error>) -> Void) {
        isAcceptingInvite = true
        BuddyService.sharedInstance.acceptInvite(token: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAcceptingInvite = false
                completion(result)
            }
        }
    }

    func unfollow(buddy: BuddyConnection) {
        let id = buddy.id
        unfollowingIds.insert(id)
        BuddyService.sharedInstance.unfollow(targetUid: buddy.targetUid) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.unfollowingIds.remove(id)
                if case .failure(let error) = result {
                    self.generateErrorMessage = error.localizedDescription
                }
                // No manual list mutation — the Firestore listener
                // re-emits the buddies array on delete.
            }
        }
    }

    /// Sends a "share your meals with me" request to someone who's
    /// already in my followers list. Only the recipient's accept turns
    /// the row mutual — we don't write a buddy doc unilaterally.
    func requestShareBack(follower: BuddyFollower) {
        let id = follower.followerUid
        guard !requestingShareBackUids.contains(id) else { return }
        requestingShareBackUids.insert(id)
        BuddyService.sharedInstance.requestShareBack(targetUid: follower.followerUid) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingShareBackUids.remove(id)
                if case .failure(let error) = result {
                    self.generateErrorMessage = error.localizedDescription
                }
                // outgoingRequestsListener picks up the new request and
                // flips the row's button to "Requested" automatically.
            }
        }
    }

    /// Cancels a previously-sent request that the recipient hasn't
    /// responded to. The recipient's incoming-requests listener removes
    /// the row on their end.
    func withdrawShareRequest(targetUid: String) {
        let id = targetUid
        guard !requestingShareBackUids.contains(id) else { return }
        requestingShareBackUids.insert(id)
        BuddyService.sharedInstance.withdrawShareRequest(targetUid: targetUid) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingShareBackUids.remove(id)
                if case .failure(let error) = result {
                    self.generateErrorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Recipient-side accept of an incoming request. Atomically grants
    /// the requester a buddy doc on my behalf and clears the request.
    func acceptIncomingRequest(_ request: BuddyShareRequest) {
        let id = request.fromUid
        guard !respondingToRequestUids.contains(id) else { return }
        respondingToRequestUids.insert(id)
        BuddyService.sharedInstance.acceptShareRequest(request) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.respondingToRequestUids.remove(id)
                if case .failure(let error) = result {
                    self.generateErrorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Recipient-side decline. Just deletes the request.
    func declineIncomingRequest(_ request: BuddyShareRequest) {
        let id = request.fromUid
        guard !respondingToRequestUids.contains(id) else { return }
        respondingToRequestUids.insert(id)
        BuddyService.sharedInstance.declineShareRequest(request) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.respondingToRequestUids.remove(id)
                if case .failure(let error) = result {
                    self.generateErrorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Stops sharing my journal with someone who's currently following me.
    /// The `observeFollowers` listener re-emits and their row vanishes.
    func revokeShare(follower: BuddyFollower) {
        let id = follower.followerUid
        guard !revokingShareIds.contains(id) else { return }
        revokingShareIds.insert(id)
        BuddyService.sharedInstance.revokeShare(followerUid: follower.followerUid) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.revokingShareIds.remove(id)
                if case .failure(let error) = result {
                    self.generateErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Avatar gradient ring

/// Slowly-rotating angular gradient ring used as the buddy invite hero.
/// The ring is rendered once via `.drawingGroup()` (Equatable returns true,
/// so SwiftUI never rebuilds the body) and then `.rotationEffect()` updates
/// only a CALayer transform per frame — same pattern as the other animations
/// in this file, so the receiver sheet stays glitch-free.
private struct AvatarGradientRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                ring.rotationEffect(.degrees(0))
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate * 22
                    ring.rotationEffect(.degrees(angle))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var ring: some View {
        StaticGradientRing()
            .equatable()
            .drawingGroup()
    }
}

private struct StaticGradientRing: View, Equatable {
    var body: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [
                        Color(hex: "E0FE10"),
                        Color(hex: "F59E0B"),
                        Color(hex: "EC4899"),
                        Color(hex: "8B5CF6"),
                        Color(hex: "3B82F6"),
                        Color(hex: "E0FE10")
                    ],
                    center: .center
                ),
                lineWidth: 3
            )
    }

    static func == (lhs: StaticGradientRing, rhs: StaticGradientRing) -> Bool { true }
}

// MARK: - Deep-link receiver sheet

struct BuddyInviteReceiverSheet: View {
    let preview: BuddyInvitePreview
    let onFinished: () -> Void
    let onOpenBuddies: () -> Void

    @State private var actionState: ActionState = .ready
    @State private var shareBackInvite: BuddyInvite?

    private let accent = Color(hex: "8B5CF6")
    private let macraYellow = Color(hex: "E0FE10")
    private let amber = Color(hex: "F59E0B")
    private let amberDeep = Color(hex: "DC2626")
    private let pink = Color(hex: "EC4899")
    private let blue = Color(hex: "3B82F6")
    private let emerald = Color(hex: "10B981")

    private enum ActionState: Equatable {
        case ready
        case accepting
        case generatingShareBack
        case accepted
        case failed(String)
    }

    private var isWorking: Bool {
        actionState == .accepting || actionState == .generatingShareBack
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "080A0F"), Color(hex: "111318")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ambientOrbs
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        recentInsightCard

                        if case .failed(let message) = actionState {
                            errorCard(message)
                        }

                        actionButtons
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onFinished() }
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(item: $shareBackInvite) { invite in
            ShareInviteSheet(invite: invite)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var ambientOrbs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(macraYellow.opacity(0.20))
                    .frame(width: 280, height: 280)
                    .blur(radius: 100)
                    .offset(x: -100, y: -120)
                Circle()
                    .fill(accent.opacity(0.22))
                    .frame(width: 240, height: 240)
                    .blur(radius: 100)
                    .offset(x: geo.size.width - 120, y: 80)
                Circle()
                    .fill(amber.opacity(0.16))
                    .frame(width: 220, height: 220)
                    .blur(radius: 100)
                    .offset(x: geo.size.width / 2 - 110, y: geo.size.height - 240)
            }
        }
        .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(spacing: 18) {
            avatarHero
                .padding(.top, 8)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                    Text("BUDDY INVITE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.6)
                }
                .foregroundColor(macraYellow)

                Text(preview.displayName)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text("is sharing eating with you")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [macraYellow, pink, accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Follow their Macra journal to see today, yesterday, and older logged meals from your buddy hub.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var avatarHero: some View {
        ZStack {
            // Soft multi-color halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [macraYellow.opacity(0.45), accent.opacity(0.28), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                )
                .frame(width: 200, height: 200)
                .blur(radius: 28)

            // Slowly rotating gradient ring
            AvatarGradientRing()
                .frame(width: 108, height: 108)

            // Inner avatar
            avatarImage
                .frame(width: 92, height: 92)
                .clipShape(Circle())
        }
        .frame(width: 108, height: 108)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let urlString = preview.inviterProfileImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallbackAvatarInner
                }
            }
        } else {
            fallbackAvatarInner
        }
    }

    private var fallbackAvatarInner: some View {
        let initial = (preview.displayName.first.map { String($0) } ?? "?").uppercased()
        return ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [accent, blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(initial)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var recentInsightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("RECENT PREVIEW")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                }
                .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("\(preview.recentMealCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }

            if preview.recentMeals.isEmpty {
                Text("\(preview.displayName) has not shared recent logs yet. Once you follow, their buddy journal will appear here when meals are logged.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    metricTile(
                        label: "Calories",
                        value: "\(preview.recentCalories)",
                        icon: "flame.fill",
                        accentTop: amber,
                        accentBottom: amberDeep
                    )
                    metricTile(
                        label: "Protein",
                        value: "\(preview.recentProtein)g",
                        icon: "bolt.fill",
                        accentTop: accent,
                        accentBottom: blue
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(preview.recentMeals.prefix(3).enumerated()), id: \.offset) { index, meal in
                        BuddyInviteMealPreviewRow(
                            meal: meal,
                            accentColor: mealRowAccent(for: index)
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func mealRowAccent(for index: Int) -> Color {
        let palette: [Color] = [macraYellow, amber, accent]
        return palette[index % palette.count]
    }

    private func metricTile(
        label: String,
        value: String,
        icon: String,
        accentTop: Color,
        accentBottom: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accentTop)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(accentTop.opacity(0.92))
            }
            Text(value)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentTop.opacity(0.20), accentBottom.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accentTop.opacity(0.50), accentBottom.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if actionState == .accepted {
                acceptedActions
            } else {
                ShimmerCTA(
                    title: actionState == .accepting
                        ? "Following…"
                        : "Follow \(preview.displayName)",
                    icon: actionState == .accepting ? "hourglass" : "checkmark.circle.fill",
                    isWorking: actionState == .accepting
                ) {
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                    acceptInvite(shareBack: false)
                }
                .disabled(isWorking)
                .opacity(isWorking ? 0.85 : 1)

                Button {
                    acceptInvite(shareBack: true)
                } label: {
                    purpleOutlineButton(
                        title: actionState == .generatingShareBack
                            ? "Making your return link…"
                            : "Follow and share back",
                        systemImage: actionState == .generatingShareBack ? "hourglass" : "arrow.left.arrow.right.circle.fill"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isWorking)

                Button {
                    onFinished()
                } label: {
                    Text("Not now")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
    }

    private var acceptedActions: some View {
        VStack(spacing: 14) {
            // Celebratory badge with multi-color glow
            ZStack {
                Circle()
                    .fill(emerald.opacity(0.45))
                    .frame(width: 90, height: 90)
                    .blur(radius: 22)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [macraYellow, emerald],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: macraYellow.opacity(0.55), radius: 18, x: 0, y: 6)

                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text("You're following")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                Text(preview.displayName)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [macraYellow, accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            ShimmerCTA(
                title: "Open buddy hub",
                icon: "person.2.fill",
                isWorking: false
            ) {
                onOpenBuddies()
            }

            Button {
                onFinished()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Back to journal")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                }
                .foregroundColor(.white.opacity(0.78))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func purpleOutlineButton(title: String, systemImage: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [accent.opacity(0.22), blue.opacity(0.14)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        )
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [accent.opacity(0.55), blue.opacity(0.40)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 1
            )
        )
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "FF6B6B"))
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "FF6B6B").opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: "FF6B6B").opacity(0.28), lineWidth: 1))
    }

    private func acceptInvite(shareBack: Bool) {
        actionState = shareBack ? .generatingShareBack : .accepting

        BuddyService.sharedInstance.acceptInvite(token: preview.token) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    finishAccepting(shareBack: shareBack)
                case .failure(let error):
                    if let buddyError = error as? BuddyError, buddyError == .alreadyFollowing {
                        finishAccepting(shareBack: shareBack)
                    } else {
                        actionState = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func finishAccepting(shareBack: Bool) {
        MacraDeepLinkService.sharedInstance.clearPendingInvite()

        guard shareBack else {
            actionState = .accepted
            return
        }

        BuddyService.sharedInstance.createInvite { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let invite):
                    actionState = .accepted
                    shareBackInvite = invite
                case .failure(let error):
                    actionState = .failed(error.localizedDescription)
                }
            }
        }
    }
}

private struct BuddyInviteMealPreviewRow: View {
    let meal: Meal
    var accentColor: Color = Color(hex: "E0FE10")

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: meal.createdAt)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Color stripe — quick palette read at a glance
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [accentColor, accentColor.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 38)

            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name.isEmpty ? "Meal" : meal.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(timeLabel) · \(meal.calories) cal · \(meal.protein)g protein")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.52))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        if !meal.image.isEmpty, let url = URL(string: meal.image) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallback
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.07))
            Image(systemName: "fork.knife")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "E0FE10").opacity(0.86))
        }
        .frame(width: 42, height: 42)
    }
}
