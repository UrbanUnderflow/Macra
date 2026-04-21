import SwiftUI

struct MealPlanningRootView: View {
    @StateObject private var viewModel: MealPlanningRootViewModel
    @StateObject private var noraPlansViewModel: NoraPlansViewModel
    @State private var selectedTab: MealPlanningScreenMode = .plans
    @State private var activeEditor: MealPlanEditorMode?
    @State private var mealSelectionPlan: MealPlan?

    init(userId: String, store: any MealPlanningStore = FirestoreMealPlanningStore()) {
        _viewModel = StateObject(wrappedValue: MealPlanningRootViewModel(userId: userId, store: store))
        _noraPlansViewModel = StateObject(wrappedValue: NoraPlansViewModel(userId: userId))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color.secondaryCharcoal.opacity(0.98),
                    Color.blueGray.opacity(0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    heroCard

                    chromaticTabSwitcher

                    if selectedTab == .plans {
                        plansSection
                    } else {
                        NoraPlansSection(viewModel: noraPlansViewModel)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            viewModel.loadInitialData()
            noraPlansViewModel.load()
        }
        .sheet(item: $activeEditor) { mode in
            MealPlanEditorView(mode: mode) { result in
                switch result {
                case .createEmpty(let name):
                    viewModel.createPlan(name: name) { _ in }
                case .createFromDate(let date, let name):
                    viewModel.createPlanFromDate(date, name: name) { _ in }
                case .rename(let planId, let name):
                    viewModel.renamePlan(planId: planId, newName: name) { _ in }
                }
                activeEditor = nil
            } onCancel: {
                activeEditor = nil
            }
        }
        .sheet(item: $mealSelectionPlan) { plan in
            MealSelectionView(
                availableMeals: viewModel.recentMeals,
                planName: plan.planName
            ) { selectedMeals in
                viewModel.addMealsToPlan(selectedMeals, planId: plan.id) { _ in }
                mealSelectionPlan = nil
            } onCancel: {
                mealSelectionPlan = nil
            }
        }
        .alert("Meal Planning", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var heroCard: some View {
        let accent = Color(hex: "E0FE10")
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PLAN")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(accent)

                    Text("Your playbook")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                        .foregroundColor(.white)

                    Text("Reusable meal plans you can log back to your journal whenever you're ready.")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundColor(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Button {
                    viewModel.refresh()
                    noraPlansViewModel.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(accent.opacity(0.12)))
                        .overlay(Circle().strokeBorder(accent.opacity(0.34), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                PlanStatTile(label: "Plans", value: "\(viewModel.orderedMealPlans.count)", color: Color(hex: "E0FE10"))
                PlanStatTile(label: "Meals", value: "\(viewModel.totalPlannedMeals)", color: Color(hex: "3B82F6"))
                PlanStatTile(label: "Active", value: "\(viewModel.activePlanCount)", color: Color(hex: "8B5CF6"))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), .clear, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accent.opacity(0.5), accent.opacity(0.14), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: accent.opacity(0.18), radius: 22, x: 0, y: 10)
                .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 14)
        )
    }

    private var chromaticTabSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(MealPlanningScreenMode.allCases) { mode in
                let isActive = mode == selectedTab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(isActive ? .black : .white.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(isActive ? Color(hex: "E0FE10") : Color.white.opacity(0.05))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isActive ? .clear : Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule().fill(Color.white.opacity(0.04))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            actionButtons

            if let status = viewModel.statusMessage {
                PlanStatusPill(text: status)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("YOUR PLANS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "8B5CF6"))
                Spacer()
                Text("\(viewModel.orderedMealPlans.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: "8B5CF6"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: "8B5CF6").opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Color(hex: "8B5CF6").opacity(0.32), lineWidth: 1))
            }

            if viewModel.orderedMealPlans.isEmpty {
                PlansEmptyCard {
                    activeEditor = .create
                }
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.orderedMealPlans) { plan in
                        NavigationLink {
                            MealPlanDetailView(viewModel: viewModel, planID: plan.id) {
                                mealSelectionPlan = plan
                            } onRename: {
                                activeEditor = .rename(planId: plan.id, currentName: plan.planName)
                            }
                        } label: {
                            MealPlanSummaryCard(plan: plan) {
                                mealSelectionPlan = plan
                            } onRename: {
                                activeEditor = .rename(planId: plan.id, currentName: plan.planName)
                            } onDelete: {
                                viewModel.deletePlan(planId: plan.id) { _ in }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                activeEditor = .create
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("New plan")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color(hex: "E0FE10")))
                .shadow(color: Color(hex: "E0FE10").opacity(0.45), radius: 18, x: 0, y: 8)
            }
            .buttonStyle(.plain)

            Button {
                activeEditor = .createFromDate(Date())
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Create plan from today")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.88))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PlanStatTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(color.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(0.32), lineWidth: 1)
        )
    }
}

private struct PlanStatusPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundColor(Color(hex: "E0FE10"))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(hex: "E0FE10").opacity(0.10)))
        .overlay(Capsule().strokeBorder(Color(hex: "E0FE10").opacity(0.32), lineWidth: 1))
    }
}

private struct PlansEmptyCard: View {
    let onCreate: () -> Void
    private let accent = Color(hex: "8B5CF6")

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 64, height: 64)
                Image(systemName: "fork.knife")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(accent)
            }

            Text("No meal plans yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Add a reusable plan, seed one from a day of meals, or start with a blank template.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onCreate) {
                Text("Create first plan")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(hex: "E0FE10")))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

struct MealPlanSummaryCard: View {
    let plan: MealPlan
    var onAddMeals: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    private var accent: Color { Color(hex: "8B5CF6") }

    private var progressColor: Color {
        plan.completionPercentage >= 1 ? Color(hex: "E0FE10") : Color(hex: "3B82F6")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            macroTileRow

            HStack(spacing: 10) {
                MealPlanSecondaryButton(title: "Add meals", systemImage: "plus.circle", accent: accent, onTap: onAddMeals)
                MealPlanSecondaryButton(title: "Rename", systemImage: "pencil", accent: accent, onTap: onRename)
            }

            Button(action: onDelete) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Delete plan")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Color(hex: "EF4444"))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: accent.opacity(0.16), radius: 18, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.22), radius: 22, x: 0, y: 14)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.planName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text("\(plan.plannedMeals.count) planned meals")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(accent)
            }

            Spacer(minLength: 10)

            progressBadge
        }
    }

    private var progressBadge: some View {
        let label = plan.completionPercentage >= 1 ? "Complete" : "\(Int(plan.completionPercentage * 100))%"
        return Text(label)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundColor(progressColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(progressColor.opacity(0.12)))
            .overlay(Capsule().strokeBorder(progressColor.opacity(0.34), lineWidth: 1))
    }

    private var macroTileRow: some View {
        HStack(spacing: 10) {
            MealPlanMacroTile(label: "Cal", value: "\(plan.totalCalories)", color: Color(hex: "E0FE10"))
            MealPlanMacroTile(label: "P", value: "\(plan.totalProtein)g", color: Color(hex: "FAFAFA"))
            MealPlanMacroTile(label: "C", value: "\(plan.totalCarbs)g", color: Color(hex: "3B82F6"))
            MealPlanMacroTile(label: "F", value: "\(plan.totalFat)g", color: Color(hex: "FFB454"))
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(accent.opacity(0.06))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), .clear, .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [accent.opacity(0.45), accent.opacity(0.14), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

private struct MealPlanMacroTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundColor(color.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct MealPlanSecondaryButton: View {
    let title: String
    let systemImage: String
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Capsule().fill(accent.opacity(0.10)))
            .overlay(Capsule().strokeBorder(accent.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct NoraPlansSection: View {
    @ObservedObject var viewModel: NoraPlansViewModel

    private let accent = Color(hex: "8B5CF6")
    private let lime = Color(hex: "E0FE10")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if viewModel.isLoading && viewModel.plans.isEmpty {
                loadingCard
            } else if viewModel.plans.isEmpty {
                emptyCard
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.plans) { plan in
                        NoraPlanCard(plan: plan)
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(Color(hex: "EF4444"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(hex: "EF4444").opacity(0.10)))
                    .overlay(Capsule().strokeBorder(Color(hex: "EF4444").opacity(0.32), lineWidth: 1))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("NORA'S PLANS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(accent)
            Spacer()
            Text("\(viewModel.plans.count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.12)))
                .overlay(Capsule().strokeBorder(accent.opacity(0.32), lineWidth: 1))
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(lime)
            Text("Loading Nora's plans…")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 60, height: 60)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(accent)
            }
            Text("No Nora plans yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("When Nora generates a meal plan for you, it will show up here so you can revisit it anytime.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(accent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(accent.opacity(0.25), lineWidth: 1))
    }
}

private struct NoraPlanCard: View {
    let plan: NoraGeneratedPlan

    private let accent = Color(hex: "8B5CF6")
    private let lime = Color(hex: "E0FE10")

    @State private var isExpanded: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let macros = plan.inputMacros {
                macroRow(macros)
            }

            if let goal = plan.goal {
                contextChip(icon: "target", text: goal.capitalized)
            }
            if let diet = plan.dietaryPreference, diet.lowercased() != "none" {
                contextChip(icon: "leaf", text: diet.capitalized)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isExpanded ? "Hide meals" : "Show \(plan.plan.meals.count) meals")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(accent.opacity(0.10)))
                .overlay(Capsule().strokeBorder(accent.opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    ForEach(Array(plan.plan.meals.enumerated()), id: \.offset) { index, meal in
                        NoraPlanMealRow(index: index, meal: meal)
                    }
                    if let notes = plan.plan.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundColor(.white.opacity(0.68))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accent.opacity(0.45), accent.opacity(0.14), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: accent.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.isCurrent ? "Current Nora plan" : "Nora plan")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(Self.dateFormatter.string(from: plan.generatedAt))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(accent)
            }
            Spacer(minLength: 10)
            if plan.isCurrent {
                Text("Active")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(lime))
            }
        }
    }

    private func macroRow(_ macros: NoraGeneratedPlan.MacroSummary) -> some View {
        HStack(spacing: 10) {
            MealPlanMacroPill(label: "Cal", value: "\(macros.calories)", color: lime)
            MealPlanMacroPill(label: "P", value: "\(macros.protein)g", color: Color(hex: "FAFAFA"))
            MealPlanMacroPill(label: "C", value: "\(macros.carbs)g", color: Color(hex: "3B82F6"))
            MealPlanMacroPill(label: "F", value: "\(macros.fat)g", color: Color(hex: "FFB454"))
        }
    }

    private func contextChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

private struct MealPlanMacroPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundColor(color.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.22), lineWidth: 1))
    }
}

private struct NoraPlanMealRow: View {
    let index: Int
    let meal: MacraSuggestedMeal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Meal \(index + 1)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(meal.totalCalories) kcal")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(meal.items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.95))
                            Text(item.quantity)
                                .font(.system(size: 11, weight: .regular, design: .default))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                        Text("\(item.calories)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}
