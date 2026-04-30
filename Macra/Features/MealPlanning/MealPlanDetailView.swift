import SwiftUI

struct MealPlanDetailView: View {
    @ObservedObject var viewModel: MealPlanningRootViewModel
    let planID: String
    var onAddMeals: () -> Void
    var onRename: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var logContext: MealLogContext?
    @State private var isEditing: Bool = false
    @State private var isConfirmingDelete: Bool = false

    private var plan: MealPlan? {
        viewModel.mealPlans.first(where: { $0.id == planID })
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

            ScrollView {
                VStack(spacing: 16) {
                    if let plan {
                        header(for: plan)
                        if isEditing {
                            actionRow(for: plan)
                        } else {
                            readOnlyActionRow(for: plan)
                        }

                        if plan.orderedMeals.isEmpty {
                            MealPlanningEmptyState(
                                title: "No planned meals yet",
                                message: isEditing ? "Add a meal from your history or build this plan from scratch." : "Tap Edit to add meals to this plan.",
                                systemImage: "fork.knife",
                                actionTitle: isEditing ? "Add meals" : nil
                            ) {
                                if isEditing { onAddMeals() }
                            }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(plan.orderedMeals.enumerated()), id: \.element.id) { index, plannedMeal in
                                    PlannedMealCardView(
                                        plannedMeal: plannedMeal,
                                        plan: plan,
                                        index: index,
                                        isEditing: isEditing,
                                        onLog: {
                                            logContext = MealLogContext(plan: plan, plannedMeal: plannedMeal)
                                        },
                                        onToggleComplete: {
                                            if plannedMeal.isCompleted {
                                                viewModel.markPlannedMealIncomplete(plannedMealId: plannedMeal.id, planId: plan.id) { _ in }
                                            } else {
                                                viewModel.markPlannedMealCompleted(plannedMealId: plannedMeal.id, planId: plan.id) { _ in }
                                            }
                                        },
                                        onMoveUp: {
                                            viewModel.reorderPlannedMeal(plannedMealId: plannedMeal.id, to: max(1, plannedMeal.order - 1), planId: plan.id) { _ in }
                                        },
                                        onMoveDown: {
                                            viewModel.reorderPlannedMeal(plannedMealId: plannedMeal.id, to: min(plan.orderedMeals.count, plannedMeal.order + 1), planId: plan.id) { _ in }
                                        },
                                        onCombineWithNext: {
                                            guard index + 1 < plan.orderedMeals.count else { return }
                                            viewModel.combinePlannedMeal(
                                                primaryPlannedMealId: plannedMeal.id,
                                                secondaryPlannedMealId: plan.orderedMeals[index + 1].id,
                                                planId: plan.id
                                            ) { _ in }
                                        },
                                        onSeparate: {
                                            viewModel.separatePlannedMeal(plannedMealId: plannedMeal.id, planId: plan.id) { _ in }
                                        },
                                        onDelete: {
                                            viewModel.removePlannedMeal(plannedMealId: plannedMeal.id, planId: plan.id) { _ in }
                                        }
                                    )
                                }
                            }
                        }
                    } else {
                        MealPlanningEmptyState(
                            title: "Plan not found",
                            message: "This plan may have been deleted or is still loading.",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(plan?.planName ?? "Meal Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditing {
                    Button {
                        onAddMeals()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.secondaryWhite)
                    }
                }

                Button {
                    isEditing.toggle()
                } label: {
                    Text(isEditing ? "Done" : "Edit")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(isEditing ? .primaryGreen : .secondaryWhite)
                }
            }
        }
        .sheet(item: $logContext) { context in
            LogPlannedMealSheet(
                context: context
            ) { date in
                viewModel.logPlannedMeal(plannedMeal: context.plannedMeal, planId: context.plan.id, at: date) { _ in }
                logContext = nil
            } onCancel: {
                logContext = nil
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
        .confirmationDialog(
            "Delete \(plan?.planName ?? "this plan")?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete plan", role: .destructive) {
                guard let plan else { return }
                viewModel.deletePlan(planId: plan.id) { _ in }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private func header(for plan: MealPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.planName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondaryWhite)

                    Text(plan.isActive ? "Active plan" : "Inactive plan")
                        .font(.subheadline)
                        .foregroundColor(.secondaryWhite.opacity(0.68))
                }

                Spacer()

                MealPlanningStatusPill(
                    text: plan.completionPercentage >= 1 ? "Complete" : "\(Int(plan.completionPercentage * 100))%",
                    tint: plan.completionPercentage >= 1 ? .primaryGreen : .lightBlue
                )
            }

            HStack(spacing: 10) {
                MealMetricChip(label: "Cal", value: "\(plan.totalCalories)", tint: .primaryGreen)
                MealMetricChip(label: "Protein", value: "\(plan.totalProtein)g", tint: .secondaryWhite)
                MealMetricChip(label: "Carbs", value: "\(plan.totalCarbs)g", tint: .primaryBlue)
                MealMetricChip(label: "Fat", value: "\(plan.totalFat)g", tint: .orange)
            }

            if let first = plan.orderedMeals.first {
                HStack(spacing: 12) {
                    if let meal = first.meals.first {
                        MealPlanningMealThumbnail(meal: meal, size: 58)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next up")
                            .font(.caption)
                            .foregroundColor(.secondaryWhite.opacity(0.55))
                        Text(first.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondaryWhite)
                    }
                    Spacer()
                }
            }
        }
        .padding(18)
        .background(MealPlanningCardBackground())
    }

    private func actionRow(for plan: MealPlan) -> some View {
        VStack(spacing: 10) {
            MealPlanningPrimaryButton(title: "Add meals from history", systemImage: "clock.arrow.circlepath") {
                onAddMeals()
            }

            HStack(spacing: 10) {
                MealPlanningSecondaryButton(title: "Rename", systemImage: "pencil") {
                    onRename()
                }

                MealPlanningSecondaryButton(title: "Log all", systemImage: "tray.and.arrow.down") {
                    logAllPendingMeals(in: plan)
                }
            }

            Button {
                isConfirmingDelete = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Delete plan")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Color(hex: "EF4444"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color(hex: "EF4444").opacity(0.10)))
                .overlay(Capsule().strokeBorder(Color(hex: "EF4444").opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func readOnlyActionRow(for plan: MealPlan) -> some View {
        // Non-edit mode keeps mass-logging available (a daily action) but
        // hides structural changes (rename, add, reorder, remove).
        MealPlanningPrimaryButton(title: "Log all", systemImage: "tray.and.arrow.down") {
            logAllPendingMeals(in: plan)
        }
    }

    private func logAllPendingMeals(in plan: MealPlan) {
        let mealsToLog = plan.pendingMeals.isEmpty ? plan.orderedMeals : plan.pendingMeals
        guard !mealsToLog.isEmpty else { return }

        let date = Date()
        let group = DispatchGroup()

        for meal in mealsToLog {
            group.enter()
            viewModel.logPlannedMeal(plannedMeal: meal, planId: plan.id, at: date) { _ in
                group.leave()
            }
        }

        group.notify(queue: .main) {
            logContext = nil
        }
    }
}

struct PlannedMealCardView: View {
    let plannedMeal: PlannedMeal
    let plan: MealPlan
    let index: Int
    var isEditing: Bool = true
    var onLog: () -> Void
    var onToggleComplete: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onCombineWithNext: () -> Void
    var onSeparate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if let meal = plannedMeal.meals.first {
                    MealPlanningMealThumbnail(meal: meal, size: 70)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(plannedMeal.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primaryGreen)
                        Spacer()
                        MealPlanningStatusPill(
                            text: plannedMeal.isCompleted ? "Logged" : "Pending",
                            tint: plannedMeal.isCompleted ? .primaryGreen : .lightBlue
                        )
                    }

                    Text(plannedMeal.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondaryWhite)
                        .lineLimit(2)

                    Text("\(plannedMeal.calories) cal · \(plannedMeal.protein)g P · \(plannedMeal.carbs)g C · \(plannedMeal.fat)g F")
                        .font(.subheadline)
                        .foregroundColor(.secondaryWhite.opacity(0.68))

                    if let notes = plannedMeal.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondaryWhite.opacity(0.56))
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: onLog) {
                    Label("Log", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondaryCharcoal)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primaryGreen)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onToggleComplete) {
                    Label(plannedMeal.isCompleted ? "Undo" : "Complete", systemImage: plannedMeal.isCompleted ? "arrow.uturn.backward" : "checkmark.circle")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondaryWhite)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.secondaryWhite.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                if isEditing {
                    Menu {
                        Button("Move up", action: onMoveUp)
                        Button("Move down", action: onMoveDown)
                        if plannedMeal.isCombinedMeal {
                            Button("Separate meal", action: onSeparate)
                        } else {
                            Button("Combine with next", action: onCombineWithNext)
                        }
                        Button(role: .destructive, action: onDelete) {
                            Text("Remove")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.secondaryWhite.opacity(0.8))
                    }
                }
            }

            if plannedMeal.isCombinedMeal {
                Text("\(plannedMeal.meals.count) meals combined into this slot")
                    .font(.caption)
                    .foregroundColor(.secondaryWhite.opacity(0.56))
            }
        }
        .padding(18)
        .background(MealPlanningCardBackground())
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(plannedMeal.isCompleted ? Color.primaryGreen.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .opacity(plannedMeal.isCompleted ? 0.94 : 1)
    }
}

struct MealLogContext: Identifiable {
    let id = UUID()
    let plan: MealPlan
    let plannedMeal: PlannedMeal
}

struct LogPlannedMealSheet: View {
    let context: MealLogContext
    var onLog: (Date) -> Void
    var onCancel: () -> Void

    @State private var logDate = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.secondaryCharcoal.ignoresSafeArea()

                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text("Log planned meal")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondaryWhite)
                        Text(context.plannedMeal.name)
                            .font(.subheadline)
                            .foregroundColor(.secondaryWhite.opacity(0.68))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    MealPlanningCardBackground()
                        .overlay(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 12) {
                                if let meal = context.plannedMeal.meals.first {
                                    MealPlanningMealThumbnail(meal: meal, size: 72)
                                }
                                Text(context.plan.planName)
                                    .font(.headline)
                                    .foregroundColor(.secondaryWhite)
                                Text("\(context.plannedMeal.meals.count) meal(s) will be logged to the journal.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondaryWhite.opacity(0.7))
                                Text(context.plannedMeal.calories.description + " calories")
                                    .font(.caption)
                                    .foregroundColor(.secondaryWhite.opacity(0.55))
                            }
                            .padding(18)
                        }
                        .frame(height: 220)

                    DatePicker("Log time", selection: $logDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .colorScheme(.dark)

                    MealPlanningPrimaryButton(title: "Log meal", systemImage: "checkmark") {
                        onLog(logDate)
                    }

                    MealPlanningSecondaryButton(title: "Cancel", systemImage: "xmark") {
                        onCancel()
                    }
                }
                .padding(16)
            }
            .navigationBarHidden(true)
        }
    }
}
