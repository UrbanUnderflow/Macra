import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Reusable likes + comments block. Drops into both the buddy meal
/// detail sheet (someone viewing a friend's meal) and the owner's own
/// meal-log detail view (so the owner sees who reacted to their food).
/// Owns its own listeners — caller passes `ownerUid` (the meal's
/// author) and `mealId`, the rest is internal.
struct MealSocialView: View {
    let ownerUid: String
    let mealId: String
    /// Optional accent color for the like heart + send button. Defaults
    /// to lime so it matches the buddy detail sheet's primary tint, but
    /// the owner's view can pass its own scheme.
    var accentColor: Color = Color(hex: "E0FE10")

    @StateObject private var viewModel: MealSocialViewModel
    @FocusState private var isComposerFocused: Bool

    init(ownerUid: String, mealId: String, accentColor: Color = Color(hex: "E0FE10")) {
        self.ownerUid = ownerUid
        self.mealId = mealId
        self.accentColor = accentColor
        _viewModel = StateObject(
            wrappedValue: MealSocialViewModel(ownerUid: ownerUid, mealId: mealId)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            likeRow
            Divider().background(Color.white.opacity(0.08))
            commentsHeader
            commentsList
            commentComposer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Like row

    private var likeRow: some View {
        HStack(spacing: 12) {
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                viewModel.toggleLike()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isLikedByMe ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(viewModel.isLikedByMe ? Color(hex: "FF4D6D") : .white.opacity(0.55))
                        .scaleEffect(viewModel.isLikedByMe ? 1.05 : 1.0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: viewModel.isLikedByMe)

                    Text(viewModel.likeCountLabel)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isTogglingLike)

            if !viewModel.likes.isEmpty {
                avatarStack
            }

            Spacer(minLength: 0)
        }
    }

    private var avatarStack: some View {
        HStack(spacing: -8) {
            ForEach(viewModel.likes.prefix(4)) { like in
                likeAvatar(for: like)
            }
        }
    }

    private func likeAvatar(for like: MealLike) -> some View {
        Group {
            if let urlString = like.likerProfileImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        likeAvatarFallback(initial: initial(for: like.displayName))
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(Circle())
            } else {
                likeAvatarFallback(initial: initial(for: like.displayName))
            }
        }
        .overlay(Circle().strokeBorder(Color(hex: "0A0B0F"), lineWidth: 1.5))
    }

    private func likeAvatarFallback(initial: String) -> some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Color(hex: "8B5CF6"), Color(hex: "3B82F6")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(initial)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 22, height: 22)
    }

    // MARK: - Comments

    private var commentsHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 10, weight: .bold))
            Text("COMMENTS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.2)
            Spacer()
            Text("\(viewModel.comments.count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundColor(.white.opacity(0.55))
    }

    @ViewBuilder
    private var commentsList: some View {
        if viewModel.comments.isEmpty {
            Text("Be the first to leave a comment.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.comments) { comment in
                    commentRow(comment)
                }
            }
        }
    }

    private func commentRow(_ comment: MealComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            commentAvatar(comment)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.displayName)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(relative(date: comment.createdAt))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.40))
                    Spacer(minLength: 0)
                }
                Text(comment.text)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contextMenu {
            if comment.authorUid == Auth.auth().currentUser?.uid {
                Button(role: .destructive) {
                    viewModel.deleteComment(comment)
                } label: {
                    Label("Delete comment", systemImage: "trash")
                }
            }
        }
    }

    private func commentAvatar(_ comment: MealComment) -> some View {
        Group {
            if let urlString = comment.authorProfileImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        commentAvatarFallback(initial: initial(for: comment.displayName))
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            } else {
                commentAvatarFallback(initial: initial(for: comment.displayName))
            }
        }
        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func commentAvatarFallback(initial: String) -> some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Color(hex: "8B5CF6"), Color(hex: "3B82F6")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(initial)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 30, height: 30)
    }

    // MARK: - Composer

    private var commentComposer: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                if viewModel.commentDraft.isEmpty {
                    Text("Add a comment…")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.32))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextField("", text: $viewModel.commentDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

            Button {
                isComposerFocused = false
                viewModel.postComment()
            } label: {
                Image(systemName: viewModel.isPostingComment ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(canSubmit ? accentColor : Color.white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }

    private var canSubmit: Bool {
        !viewModel.isPostingComment &&
            !viewModel.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Helpers

    private func initial(for name: String) -> String {
        (name.first.map { String($0) } ?? "?").uppercased()
    }

    private func relative(date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

@MainActor
final class MealSocialViewModel: ObservableObject {
    let ownerUid: String
    let mealId: String

    @Published var likes: [MealLike] = []
    @Published var comments: [MealComment] = []
    @Published var commentDraft: String = ""
    @Published var isPostingComment: Bool = false
    @Published var isTogglingLike: Bool = false
    @Published var errorMessage: String?

    private var likesListener: ListenerRegistration?
    private var commentsListener: ListenerRegistration?
    /// Once-per-session self-heal so we don't spam the meal doc with
    /// reconciliation writes on every snapshot. The first listener
    /// emission gives us the actual subcollection size; we set it back
    /// onto the meal doc to catch legacy data whose counter wasn't
    /// bumped (likes/comments created before this feature existed) or
    /// any drift from a failed FieldValue.increment.
    private var hasReconciledLikes: Bool = false
    private var hasReconciledComments: Bool = false

    init(ownerUid: String, mealId: String) {
        self.ownerUid = ownerUid
        self.mealId = mealId
    }

    var likeCount: Int { likes.count }

    var likeCountLabel: String {
        let n = likeCount
        if n == 0 { return "Be the first to like" }
        if n == 1 { return isLikedByMe ? "You liked this" : "1 like" }
        if isLikedByMe { return "You + \(n - 1)" }
        return "\(n) likes"
    }

    var isLikedByMe: Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return likes.contains { $0.likerUid == uid }
    }

    func start() {
        if likesListener == nil {
            likesListener = MealSocialService.sharedInstance.observeLikes(ownerUid: ownerUid, mealId: mealId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if case .success(let likes) = result {
                        self.likes = likes
                        if !self.hasReconciledLikes {
                            self.hasReconciledLikes = true
                            MealSocialService.sharedInstance.reconcileMealCount(
                                ownerUid: self.ownerUid,
                                mealId: self.mealId,
                                field: "likeCount",
                                count: likes.count
                            )
                        }
                    }
                }
            }
        }
        if commentsListener == nil {
            commentsListener = MealSocialService.sharedInstance.observeComments(ownerUid: ownerUid, mealId: mealId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if case .success(let comments) = result {
                        self.comments = comments
                        if !self.hasReconciledComments {
                            self.hasReconciledComments = true
                            MealSocialService.sharedInstance.reconcileMealCount(
                                ownerUid: self.ownerUid,
                                mealId: self.mealId,
                                field: "commentCount",
                                count: comments.count
                            )
                        }
                    }
                }
            }
        }
    }

    func stop() {
        likesListener?.remove()
        likesListener = nil
        commentsListener?.remove()
        commentsListener = nil
    }

    func toggleLike() {
        guard !isTogglingLike else { return }
        isTogglingLike = true
        let currentlyLiked = isLikedByMe
        MealSocialService.sharedInstance.toggleLike(
            ownerUid: ownerUid,
            mealId: mealId,
            currentlyLiked: currentlyLiked
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isTogglingLike = false
                if case .failure(let error) = result {
                    self.errorMessage = error.localizedDescription
                }
                // Listener re-emits on success — UI updates without
                // needing a manual mutation.
            }
        }
    }

    func postComment() {
        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isPostingComment else { return }
        isPostingComment = true
        MealSocialService.sharedInstance.addComment(
            ownerUid: ownerUid,
            mealId: mealId,
            text: text
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPostingComment = false
                switch result {
                case .success:
                    self.commentDraft = ""
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func deleteComment(_ comment: MealComment) {
        MealSocialService.sharedInstance.deleteComment(
            ownerUid: ownerUid,
            mealId: mealId,
            commentId: comment.id
        ) { _ in
            // Listener re-emits on success.
        }
    }
}
