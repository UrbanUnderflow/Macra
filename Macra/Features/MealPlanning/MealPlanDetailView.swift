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
    /// Weekday currently displayed when the plan has per-day variants.
    /// Defaults to today; users can scrub to preview other days.
    @State private var selectedDay: Weekday = Weekday.from(date: Date())

    private var plan: MealPlan? {
        viewModel.mealPlans.first(where: { $0.id == planID })
    }

    /// Visible meals for the current selection. Plans without day variants
    /// fall back to the legacy "every meal, every day" ordering.
    private func visibleMeals(in plan: MealPlan) -> [PlannedMeal] {
        plan.hasDayVariants ? plan.orderedMeals(for: selectedDay) : plan.orderedMeals
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
                        if plan.hasDayVariants {
                            dayPicker(for: plan)
                        }
                        let allowEdit = !plan.hasDayVariants
                        if isEditing && allowEdit {
                            actionRow(for: plan)
                        } else {
                            readOnlyActionRow(for: plan)
                        }

                        let meals = visibleMeals(in: plan)
                        if meals.isEmpty {
                            MealPlanningEmptyState(
                                title: plan.hasDayVariants ? "No meals on \(selectedDay.shortLabel)" : "No planned meals yet",
                                message: plan.hasDayVariants
                                    ? "This plan doesn't schedule any meals for \(selectedDay.shortLabel). Pick another day to see what's planned."
                                    : (isEditing ? "Add a meal from your history or build this plan from scratch." : "Tap Edit to add meals to this plan."),
                                systemImage: "fork.knife",
                                actionTitle: (allowEdit && isEditing) ? "Add meals" : nil
                            ) {
                                if isEditing { onAddMeals() }
                            }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(meals.enumerated()), id: \.element.id) { index, plannedMeal in
                                    PlannedMealCardView(
                                        plannedMeal: plannedMeal,
                                        plan: plan,
                                        index: index,
                                        isEditing: isEditing && allowEdit,
                                        onLog: {
                                            logContext = MealLogContext(plan: plan, plannedMeal: plannedMeal, day: selectedDay)
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
                                            viewModel.reorderPlannedMeal(plannedMealId: plannedMeal.id, to: min(meals.count, plannedMeal.order + 1), planId: plan.id) { _ in }
                                        },
                                        onCombineWithNext: {
                                            guard index + 1 < meals.count else { return }
                                            viewModel.combinePlannedMeal(
                                                primaryPlannedMealId: plannedMeal.id,
                                                secondaryPlannedMealId: meals[index + 1].id,
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
                let editingDisabled = plan?.hasDayVariants ?? false
                if isEditing && !editingDisabled {
                    Button {
                        onAddMeals()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.secondaryWhite)
                    }
                }

                if !editingDisabled {
                    Button {
                        isEditing.toggle()
                    } label: {
                        Text(isEditing ? "Done" : "Edit")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(isEditing ? .primaryGreen : .secondaryWhite)
                    }
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
        let calories = plan.hasDayVariants ? plan.totalCalories(for: selectedDay) : plan.totalCalories
        let protein = plan.hasDayVariants ? plan.totalProtein(for: selectedDay) : plan.totalProtein
        let carbs = plan.hasDayVariants ? plan.totalCarbs(for: selectedDay) : plan.totalCarbs
        let fat = plan.hasDayVariants ? plan.totalFat(for: selectedDay) : plan.totalFat
        let firstVisible = plan.hasDayVariants ? plan.orderedMeals(for: selectedDay).first : plan.orderedMeals.first

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.planName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondaryWhite)

                    Text(plan.hasDayVariants
                         ? "Showing \(selectedDay.shortLabel)"
                         : (plan.isActive ? "Active plan" : "Inactive plan"))
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
                MealMetricChip(label: "Cal", value: "\(calories)", tint: .primaryGreen)
                MealMetricChip(label: "Protein", value: "\(protein)g", tint: .secondaryWhite)
                MealMetricChip(label: "Carbs", value: "\(carbs)g", tint: .primaryBlue)
                MealMetricChip(label: "Fat", value: "\(fat)g", tint: .orange)
            }

            if let first = firstVisible {
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

    /// Mon–Sun pill row shown when the plan carries day-specific variants.
    /// Selection drives both the meal list and the macro chips above.
    private func dayPicker(for plan: MealPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondaryWhite.opacity(0.5))
                Text("VIEW BY DAY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(.secondaryWhite.opacity(0.55))
                Spacer()
                Button {
                    selectedDay = Weekday.from(date: Date())
                } label: {
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primaryGreen)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(Weekday.displayOrder) { day in
                    let isOn = (day == selectedDay)
                    Button {
                        selectedDay = day
                    } label: {
                        Text(day.shortLabel)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(isOn ? .black : .secondaryWhite.opacity(0.78))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isOn ? Color.primaryGreen : Color.white.opacity(0.05))
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isOn ? Color.primaryGreen : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
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
        // For day-variant plans, only log meals scheduled for the selected
        // day so "Log all" doesn't dump a Sunday's meals into a Friday view.
        let visible = visibleMeals(in: plan)
        let pending = visible.filter { !$0.isCompleted }
        let mealsToLog = pending.isEmpty ? visible : pending
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
                        if plannedMeal.hasDayScope, let days = plannedMeal.daysActive {
                            Text(days.map(\.shortLabel).joined(separator: "/") + " only")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primaryGreen.opacity(0.85)))
                        }
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
    /// Weekday the user was viewing when they tapped Log. `nil` for plans
    /// without day variants — the picker just defaults to "now".
    var day: Weekday? = nil
}

struct LogPlannedMealSheet: View {
    let context: MealLogContext
    var onLog: (Date) -> Void
    var onCancel: () -> Void

    @State private var logDate: Date

    init(context: MealLogContext, onLog: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        self.context = context
        self.onLog = onLog
        self.onCancel = onCancel
        _logDate = State(initialValue: Self.initialLogDate(for: context))
    }

    /// Default the picker to the next occurrence of the viewed weekday so a
    /// user previewing Friday's plan logs against Friday, not against today
    /// — but for plans without variants we just use "now".
    private static func initialLogDate(for context: MealLogContext) -> Date {
        guard let day = context.day else { return Date() }
        let now = Date()
        let calendar = Calendar.current
        let todayWeekday = Weekday.from(date: now, calendar: calendar)
        if day == todayWeekday { return now }
        let order = Weekday.displayOrder
        guard let todayIndex = order.firstIndex(of: todayWeekday),
              let targetIndex = order.firstIndex(of: day) else { return now }
        let daysAhead = (targetIndex - todayIndex + 7) % 7
        return calendar.date(byAdding: .day, value: daysAhead == 0 ? 7 : daysAhead, to: now) ?? now
    }

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

                    let pickedWeekday = Weekday.from(date: logDate)
                    if !context.plannedMeal.appliesOn(pickedWeekday) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                            Text("This meal isn't scheduled on \(pickedWeekday.shortLabel). It'll still log to your journal.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondaryWhite.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.orange.opacity(0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.32), lineWidth: 1)
                        )
                    }

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
