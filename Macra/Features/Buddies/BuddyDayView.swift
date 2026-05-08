import SwiftUI
import FirebaseFirestore

/// Read-only mirror of the user's own journal day, scoped to a buddy's
/// `mealLogs`. Same date chevron pattern as `HomeView`, but no edit/log
/// affordances — this surface is strictly for following along. Phase-3
/// will add the AASA-backed deep link so taps from outside the app land
/// directly here.
struct BuddyDayView: View {
    let buddy: BuddyConnection

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var meals: [Meal] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var selectedMeal: Meal?

    private let accent = Color(hex: "8B5CF6")
    private let macraYellow = Color(hex: "E0FE10")
    private let amber = Color(hex: "F59E0B")
    private let pink = Color(hex: "EC4899")
    private let blue = Color(hex: "3B82F6")

    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: selectedDate)
    }

    private var canNavigateNext: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return selectedDate < today
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0A0B0F"), Color(hex: "111318")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ambientOrbs

            ScrollView {
                VStack(spacing: 20) {
                    header
                    dayNavigator
                    if isLoading {
                        ProgressView().tint(accent).padding(40)
                    } else if let loadError {
                        errorCard(loadError)
                    } else if meals.isEmpty {
                        emptyState
                    } else {
                        macroSummary
                        mealList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(buddy.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .onAppear { reloadMeals() }
        .onChange(of: selectedDate) { _ in reloadMeals() }
        .sheet(item: $selectedMeal) { meal in
            BuddyMealDetailView(
                meal: meal,
                ownerUid: buddy.targetUid,
                ownerDisplayName: buddy.displayName
            )
        }
    }

    private var ambientOrbs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(macraYellow.opacity(0.16))
                    .frame(width: 260, height: 260)
                    .blur(radius: 100)
                    .offset(x: -90, y: -120)
                Circle()
                    .fill(accent.opacity(0.20))
                    .frame(width: 220, height: 220)
                    .blur(radius: 100)
                    .offset(x: geo.size.width - 110, y: 100)
                Circle()
                    .fill(amber.opacity(0.13))
                    .frame(width: 200, height: 200)
                    .blur(radius: 100)
                    .offset(x: geo.size.width / 2 - 100, y: geo.size.height - 220)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            avatarWithRing
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                    Text("FOLLOWING")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                }
                .foregroundColor(accent)

                Text(buddy.displayName)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                if let email = buddy.targetEmail, email != buddy.displayName {
                    Text(email)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var avatarWithRing: some View {
        ZStack {
            // Soft halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [macraYellow.opacity(0.30), accent.opacity(0.18), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .frame(width: 100, height: 100)
                .blur(radius: 14)

            // Static angular gradient ring
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [macraYellow, amber, pink, accent, blue, macraYellow],
                        center: .center
                    ),
                    lineWidth: 2
                )
                .frame(width: 64, height: 64)

            avatarImage
                .frame(width: 56, height: 56)
                .clipShape(Circle())
        }
        .frame(width: 64, height: 64)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let urlString = buddy.targetProfileImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: fallbackAvatarInner
                }
            }
        } else {
            fallbackAvatarInner
        }
    }

    private var fallbackAvatarInner: some View {
        let initial = (buddy.displayName.first.map { String($0) } ?? "?").uppercased()
        return ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [accent, blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(initial)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
    }

    /// Mirrors `HomeView.dayNavigator` so the chevron interaction feels
    /// identical between own-journal and buddy-journal. Future-day
    /// navigation is disabled — buddies don't pre-log the future.
    private var dayNavigator: some View {
        let isToday = Calendar.current.isDateInToday(selectedDate)

        return HStack(spacing: 12) {
            navChevron(systemImage: "chevron.left", enabled: true) {
                if let prev = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
                    selectedDate = Calendar.current.startOfDay(for: prev)
                }
            }
            .accessibilityLabel("Previous day")

            HStack(spacing: 8) {
                if isToday {
                    Circle()
                        .fill(macraYellow)
                        .frame(width: 6, height: 6)
                        .shadow(color: macraYellow.opacity(0.7), radius: 5, x: 0, y: 0)
                }
                Text(dateLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        LinearGradient(
                            colors: isToday
                                ? [macraYellow.opacity(0.55), accent.opacity(0.35)]
                                : [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )

            navChevron(systemImage: "chevron.right", enabled: canNavigateNext) {
                guard canNavigateNext else { return }
                if let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) {
                    selectedDate = Calendar.current.startOfDay(for: next)
                }
            }
            .accessibilityLabel("Next day")
        }
    }

    private func navChevron(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accent)
                .padding(10)
                .background(
                    Circle().fill(Color.secondaryCharcoal.opacity(0.6))
                )
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [accent.opacity(0.55), accent.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.4)
    }

    private var macroSummary: some View {
        let totalCalories = meals.reduce(0) { $0 + $1.calories }
        let totalProtein = meals.reduce(0) { $0 + $1.protein }
        let totalCarbs = meals.reduce(0) { $0 + $1.carbs }
        let totalFat = meals.reduce(0) { $0 + $1.fat }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(totalCalories.formatted())")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .monospacedDigit()
                Text("kcal")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(meals.count) meal\(meals.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.14)))
                .overlay(Capsule().strokeBorder(accent.opacity(0.32), lineWidth: 1))
            }

            macroDistributionBar(
                protein: totalProtein,
                carbs: totalCarbs,
                fat: totalFat
            )

            HStack(spacing: 10) {
                macroChip(label: "P", icon: "bolt.fill", value: totalProtein, tint: blue)
                macroChip(label: "C", icon: "leaf.fill", value: totalCarbs, tint: macraYellow)
                macroChip(label: "F", icon: "drop.fill", value: totalFat, tint: amber)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.40), macraYellow.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private func macroDistributionBar(protein: Int, carbs: Int, fat: Int) -> some View {
        let proteinCal = protein * 4
        let carbsCal = carbs * 4
        let fatCal = fat * 9
        let total = max(1, proteinCal + carbsCal + fatCal)
        let pPct = CGFloat(proteinCal) / CGFloat(total)
        let cPct = CGFloat(carbsCal) / CGFloat(total)
        let fPct = CGFloat(fatCal) / CGFloat(total)

        return GeometryReader { geo in
            HStack(spacing: 2) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [blue, blue.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * pPct - 1))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [macraYellow, Color(hex: "C8E60D")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * cPct - 1))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [amber, Color(hex: "F97316")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * fPct - 1))
            }
        }
        .frame(height: 6)
    }

    private func macroChip(label: String, icon: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(tint)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(tint.opacity(0.92))
            }
            Text("\(value)g")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.20), tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.50), tint.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private var mealList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 10, weight: .bold))
                Text("MEALS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                Spacer()
                Text("\(meals.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.55))

            ForEach(meals) { meal in
                Button {
                    selectedMeal = meal
                } label: {
                    BuddyMealRow(meal: meal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 38, weight: .regular))
                .foregroundColor(accent.opacity(0.55))
            Text("No meals on \(dateLabel.lowercased())")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Text("\(buddy.displayName) hasn't logged anything for this day.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(hex: "FF6B6B"))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { reloadMeals() }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(accent))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "FF6B6B").opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(hex: "FF6B6B").opacity(0.32), lineWidth: 1))
    }

    // MARK: - Data

    private func reloadMeals() {
        isLoading = true
        loadError = nil
        let buddyUid = buddy.targetUid
        let date = selectedDate
        MealService.sharedInstance.getMeals(byDate: date, userId: buddyUid) { result in
            DispatchQueue.main.async {
                guard buddyUid == buddy.targetUid, date == selectedDate else { return }
                isLoading = false
                switch result {
                case .success(let meals):
                    self.meals = meals
                case .failure(let error):
                    self.loadError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Read-only meal row

private struct BuddyMealRow: View {
    let meal: Meal

    private let blue = Color(hex: "3B82F6")
    private let lime = Color(hex: "E0FE10")
    private let amber = Color(hex: "F59E0B")

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: meal.createdAt)
    }

    /// Whichever macro contributes the most calories tints the row's
    /// leading stripe and the card's subtle stroke. Pure visual signal —
    /// at a glance the meal list reads as a colored ribbon of P/C/F days.
    private var dominantMacroColor: Color {
        let pCal = meal.protein * 4
        let cCal = meal.carbs * 4
        let fCal = meal.fat * 9
        if pCal >= cCal && pCal >= fCal { return blue }
        if cCal >= fCal { return lime }
        return amber
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Dominant-macro stripe
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [dominantMacroColor, dominantMacroColor.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)

            mealThumb
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(meal.name.isEmpty ? "Meal" : meal.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Spacer()
                    Text(timeString)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                }

                Text("\(meal.calories) cal · \(meal.protein)g P · \(meal.carbs)g C · \(meal.fat)g F")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)

                if !meal.ingredients.isEmpty {
                    Text(meal.ingredients.prefix(4).joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.42))
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(dominantMacroColor.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var mealThumb: some View {
        if !meal.image.isEmpty, let url = URL(string: meal.image) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: thumbFallback
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            thumbFallback
        }
    }

    private var thumbFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
            Image(systemName: "fork.knife")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(width: 56, height: 56)
    }
}
