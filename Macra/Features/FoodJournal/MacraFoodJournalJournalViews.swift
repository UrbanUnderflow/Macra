import Photos
import SwiftUI
import UIKit

struct MacraFoodJournalRootView: View {
    @StateObject var viewModel: MacraFoodJournalViewModel
    let initialSheet: MacraFoodJournalSheet?

    init(
        viewModel: MacraFoodJournalViewModel = MacraFoodJournalViewModel(),
        initialSheet: MacraFoodJournalSheet? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.initialSheet = initialSheet
    }

    var body: some View {
        MacraFoodJournalDayView(viewModel: viewModel)
            .onAppear {
                if viewModel.activeSheet == nil, let initialSheet {
                    viewModel.activeSheet = initialSheet
                }
            }
            .sheet(item: $viewModel.activeSheet) { sheet in
                MacraFoodJournalSheetContentView(viewModel: viewModel, sheet: sheet)
            }
    }
}

struct MacraFoodJournalSheetContentView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    let sheet: MacraFoodJournalSheet

    var body: some View {
        sheetContent(for: sheet)
    }

    @ViewBuilder
    private func sheetContent(for sheet: MacraFoodJournalSheet) -> some View {
        switch sheet {
        case .scanFood:
            MacraFoodJournalScanFoodView(viewModel: viewModel)
        case .mealDetails(let id):
            if let meal = viewModel.meal(for: id) {
                MacraFoodJournalMealDetailsView(viewModel: viewModel, meal: meal)
            } else {
                MacraFoodJournalMissingMealView()
            }
        case .imageConfirmation:
            MacraFoodJournalImageConfirmationView(viewModel: viewModel)
        case .foodIdentifier(let id):
            MacraFoodJournalFoodIdentifierView(viewModel: viewModel, meal: viewModel.meal(for: id))
        case .mealNotePad:
            MacraFoodJournalMealNotePadView(viewModel: viewModel)
        case .voiceEntry:
            MacraFoodJournalVoiceMealEntryView(viewModel: viewModel)
        case .fromHistory:
            MacraFoodJournalFromHistoryView(viewModel: viewModel)
        case .photoGrid:
            MacraFoodJournalPhotoFoodGridView(viewModel: viewModel)
        case .month:
            MacraFoodJournalMonthView(viewModel: viewModel)
        case .share:
            MacraShareComposerSheet(
                date: viewModel.selectedDate,
                meals: viewModel.mealsForSelectedDay,
                macroTarget: viewModel.daySummary.macroTarget,
                onClose: { viewModel.activeSheet = nil }
            )
        case .labelHistory:
            MacraLabelScanHistoryView(viewModel: viewModel)
        case .labelScan:
            MacraLabelScanView(viewModel: viewModel)
        case .labelDetail(let id):
            if let scan = viewModel.labelScan(for: id) {
                MacraLabelScanDetailView(viewModel: viewModel, scannedLabel: scan)
            } else {
                MacraFoodJournalMissingMealView(message: "Label scan unavailable.")
            }
        }
    }
}

struct MacraFoodJournalDayView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel

    private var summary: MacraFoodJournalDaySummary { viewModel.daySummary }

    var body: some View {
        ZStack {
            MacraFoodJournalTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    heroCard
                    quickActions
                    pinnedMealsSection
                    mealsSection
                    insightSection
                    historyPreviewSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Macra")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                        .tracking(1.8)
                    Text("Food Journal")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [MacraFoodJournalTheme.text, MacraFoodJournalTheme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                Spacer()
                HStack(spacing: 10) {
                    // Share a full-day recap as an Instagram-ready image.
                    // Hidden when no meals are logged so the user doesn't
                    // share an empty card accidentally.
                    if !viewModel.mealsForSelectedDay.isEmpty {
                        Button { viewModel.activeSheet = .share } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(14)
                                .background(
                                    Circle()
                                        .fill(MacraFoodJournalTheme.accent)
                                        .overlay(Circle().stroke(MacraFoodJournalTheme.accent2.opacity(0.5), lineWidth: 1))
                                        .shadow(color: MacraFoodJournalTheme.accent.opacity(0.4), radius: 10, x: 0, y: 4)
                                )
                        }
                        .accessibilityLabel("Share your day")
                    }

                    Button { viewModel.activeSheet = .month } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(
                                Circle()
                                    .fill(MacraFoodJournalTheme.panel)
                                    .overlay(Circle().stroke(MacraFoodJournalTheme.accent.opacity(0.35), lineWidth: 1))
                            )
                    }
                }
            }

            HStack(spacing: 10) {
                datePill(title: viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted), icon: "calendar.badge.clock")
                datePill(title: "\(summary.mealCount) meals", icon: "fork.knife")
                Spacer()
                Button("Today") { viewModel.selectToday() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.accent)
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Today's totals")
                        .font(.headline)
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                    Text("\(summary.totalCalories)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [MacraFoodJournalTheme.accent, MacraFoodJournalTheme.accent2],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("calories • \(summary.totalProtein)P \(summary.totalCarbs)C \(summary.totalFat)F")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(MacraFoodJournalTheme.textSoft)
                }
                Spacer()
                FoodJournalMacroRing(
                    calories: summary.totalCalories,
                    target: summary.macroTarget?.calories,
                    accent: MacraFoodJournalTheme.accent
                )
                .frame(width: 110, height: 110)
            }

            HStack(spacing: 12) {
                foodJournalMacroCard(title: "Protein", value: summary.totalProtein, target: summary.macroTarget?.protein, tint: MacraFoodJournalTheme.accent)
                foodJournalMacroCard(title: "Carbs", value: summary.totalCarbs, target: summary.macroTarget?.carbs, tint: MacraFoodJournalTheme.accent2)
                foodJournalMacroCard(title: "Fat", value: summary.totalFat, target: summary.macroTarget?.fat, tint: MacraFoodJournalTheme.accent3)
            }
        }
        .padding(20)
        .background(foodJournalCardBackground)
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            FoodJournalActionCard(title: "Scan meal", subtitle: "Photo or camera flow", icon: "camera.fill", tint: MacraFoodJournalTheme.accent) {
                viewModel.activeSheet = .scanFood
            }
            FoodJournalActionCard(title: "Voice entry", subtitle: "Talk it out", icon: "mic.fill", tint: MacraFoodJournalTheme.accent2) {
                viewModel.activeSheet = .voiceEntry
            }
            FoodJournalActionCard(title: "From history", subtitle: "Log a repeat meal", icon: "clock.arrow.circlepath", tint: MacraFoodJournalTheme.accent3) {
                viewModel.activeSheet = .fromHistory
            }
            FoodJournalActionCard(title: "Label scan", subtitle: "Grade packaged food", icon: "barcode.viewfinder", tint: MacraFoodJournalTheme.textMuted) {
                viewModel.activeSheet = .labelScan
            }
        }
    }

    private var pinnedMealsSection: some View {
        FoodJournalSection(title: "Pinned meals", subtitle: "One-tap repeats") {
            VStack(spacing: 10) {
                if viewModel.pinnedMeals.isEmpty {
                    MacraFoodJournalEmptyState(
                        title: "No pinned meals yet",
                        message: "Pin a meal from details to make quick logging easier."
                    )
                } else {
                    ForEach(viewModel.pinnedMeals) { meal in
                        MacraFoodJournalMealRow(meal: meal, onTap: { viewModel.openMealDetails(meal) }) {
                            viewModel.logMealFromHistory(meal)
                        } trailingAction: {
                            viewModel.togglePin(meal)
                        }
                    }
                    Button {
                        viewModel.quickLogPinnedMeals()
                    } label: {
                        Text("Log all pinned meals")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(MacraFoodJournalTheme.accent)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var mealsSection: some View {
        FoodJournalSection(title: "Today's meals", subtitle: "Tap to edit, pin, or relog") {
            VStack(spacing: 12) {
                if viewModel.mealsForSelectedDay.isEmpty {
                    MacraFoodJournalEmptyState(
                        title: "Nothing logged yet",
                        message: "Start with a photo, a voice note, or a text meal entry."
                    )
                } else {
                    ForEach(viewModel.mealsForSelectedDay) { meal in
                        MacraFoodJournalMealRow(meal: meal, onTap: { viewModel.openMealDetails(meal) }) {
                            viewModel.activeSheet = .foodIdentifier(meal.id)
                        } trailingAction: {
                            viewModel.togglePin(meal)
                        }
                    }
                }
            }
        }
    }

    private var insightSection: some View {
        FoodJournalSection(title: "Daily insights", subtitle: "AI feedback and macro coaching") {
            VStack(spacing: 12) {
                if summary.insights.isEmpty {
                    MacraFoodJournalEmptyState(
                        title: "No insights yet",
                        message: "Add a meal and we can generate a day summary here."
                    )
                } else {
                    ForEach(summary.insights) { insight in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: insight.icon)
                                    .foregroundColor(MacraFoodJournalTheme.accent)
                                Text(insight.title)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Text(insight.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(MacraFoodJournalTheme.textMuted)
                            }
                            Text(insight.response)
                                .font(.subheadline)
                                .foregroundColor(MacraFoodJournalTheme.textSoft)
                                .lineSpacing(4)
                        }
                        .padding(14)
                        .background(foodJournalCardBackground)
                    }
                }
                Button("Open share card") { viewModel.activeSheet = .share }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var historyPreviewSection: some View {
        FoodJournalSection(title: "Photo history", subtitle: "Recent logged meals") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.photoHistory.prefix(8)) { meal in
                        FoodJournalPhotoTile(meal: meal) {
                            viewModel.openMealDetails(meal)
                        }
                    }
                }
            }
        }
    }

    private func datePill(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundColor(MacraFoodJournalTheme.textSoft)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(MacraFoodJournalTheme.panel))
    }

    private func foodJournalMacroCard(title: String, value: Int, target: Int?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
            Text(target.map { "Target \($0)" } ?? "No target set")
                .font(.caption)
                .foregroundColor(tint.opacity(0.95))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(foodJournalCardBackground)
    }
}

struct MacraFoodJournalMonthView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel

    var body: some View {
        ZStack {
            MacraFoodJournalTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Button { viewModel.activeSheet = nil } label: {
                            Image(systemName: "chevron.down")
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(MacraFoodJournalTheme.panel))
                        }
                        Spacer()
                        VStack(spacing: 4) {
                            Text(viewModel.selectedDate.formatted(.dateTime.month(.wide).year()))
                                .font(.title3.weight(.bold))
                                .foregroundColor(.white)
                            Text("Tap a day to inspect your journal")
                                .font(.caption)
                                .foregroundColor(MacraFoodJournalTheme.textMuted)
                        }
                        Spacer()
                        Color.clear.frame(width: 36, height: 36)
                    }

                    let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { label in
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(MacraFoodJournalTheme.textMuted)
                        }
                        ForEach(monthGridPrefix, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.clear)
                                .frame(height: 52)
                        }
                        ForEach(viewModel.monthDays) { day in
                            Button {
                                viewModel.selectedDate = day.date
                                viewModel.activeSheet = nil
                            } label: {
                                VStack(spacing: 6) {
                                    Text("\(Calendar.current.component(.day, from: day.date))")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.white)
                                    if day.mealCount > 0 {
                                        Text("\(day.mealCount)")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(MacraFoodJournalTheme.accent.opacity(0.2)))
                                            .foregroundColor(MacraFoodJournalTheme.accent)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(day.isToday ? MacraFoodJournalTheme.accent.opacity(0.2) : MacraFoodJournalTheme.panel)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(day.isToday ? MacraFoodJournalTheme.accent : Color.clear, lineWidth: 1.2)
                                        )
                                )
                            }
                            .disabled(Calendar.current.isDate(day.date, inSameDayAs: Date()) == false && day.mealCount == 0)
                        }
                    }
                }
                .padding(20)
            }
        }
        .presentationDetents([.large])
    }

    private var monthGridPrefix: [Int] {
        guard let first = viewModel.monthDays.first else { return [] }
        let weekday = Calendar.current.component(.weekday, from: first.date)
        return Array(repeating: 0, count: max(0, weekday - 1))
    }
}

struct MacraFoodJournalMealDetailsView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    @State var meal: MacraFoodJournalMeal
    @State private var draftDate: Date
    @State private var showDeleteConfirmation = false

    init(viewModel: MacraFoodJournalViewModel, meal: MacraFoodJournalMeal) {
        self.viewModel = viewModel
        _meal = State(initialValue: meal)
        _draftDate = State(initialValue: meal.createdAt)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    mealHero
                    editFields
                    macroGrid
                    ingredientList
                    noteCard
                    actions
                }
                .padding(20)
            }
            .background(MacraFoodJournalTheme.background)
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(meal.isPinned ? "Unpin" : "Pin") {
                        viewModel.togglePin(meal)
                        meal.isPinned.toggle()
                    }
                    .foregroundColor(MacraFoodJournalTheme.accent)
                }
            }
            #endif
        }
        .confirmationDialog("Delete meal?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                viewModel.deleteMeal(meal)
            }
        } message: {
            Text("This removes the meal from the day journal.")
        }
    }

    private var header: some View {
        HStack {
            Button("Done") { viewModel.activeSheet = nil }
                .foregroundColor(MacraFoodJournalTheme.textSoft)
            Spacer()
            Text("Meal details")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
    }

    private var mealHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Meal name", text: $meal.name)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            TextField("Caption", text: $meal.caption)
                .foregroundColor(MacraFoodJournalTheme.textSoft)
            HStack {
                Text(meal.displayTime)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
                Spacer()
                Picker("", selection: $meal.entryMethod) {
                    ForEach(MacraFoodJournalEntryMethod.allCases, id: \.self) { method in
                        Text(method.rawValue.capitalized).tag(method)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(MacraFoodJournalTheme.accent)
            }
        }
        .padding(18)
        .background(foodJournalCardBackground)
    }

    private var editFields: some View {
        VStack(spacing: 12) {
            DatePicker("Time", selection: $draftDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .tint(MacraFoodJournalTheme.accent)
            TextField("Notes", text: $meal.notes, axis: .vertical)
                .lineLimit(2...5)
                .foregroundColor(.white)
        }
        .padding(18)
        .background(foodJournalCardBackground)
    }

    private var macroGrid: some View {
        HStack(spacing: 12) {
            mealMacroCard(label: "Calories", value: "\(meal.calories)")
            mealMacroCard(label: "Protein", value: "\(meal.protein)g")
            mealMacroCard(label: "Carbs", value: "\(meal.carbs)g")
            mealMacroCard(label: "Fat", value: "\(meal.fat)g")
        }
    }

    private func mealMacroCard(label: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(foodJournalCardBackground)
    }

    private var ingredientList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingredients")
                .font(.headline)
                .foregroundColor(.white)
            if meal.ingredients.isEmpty {
                Text("No ingredient breakdown saved yet.")
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
                    .font(.subheadline)
            } else {
                ForEach(meal.ingredients) { ingredient in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.name)
                                .foregroundColor(.white)
                            Text(ingredient.quantity)
                                .font(.caption)
                                .foregroundColor(MacraFoodJournalTheme.textMuted)
                        }
                        Spacer()
                        Text("\(ingredient.calories) cal")
                            .foregroundColor(MacraFoodJournalTheme.accent)
                    }
                }
            }
        }
        .padding(18)
        .background(foodJournalCardBackground)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Journal note")
                .font(.headline)
                .foregroundColor(.white)
            TextField("Add context, cravings, or meal prep notes", text: $meal.notes, axis: .vertical)
                .lineLimit(3...6)
                .foregroundColor(.white)
        }
        .padding(18)
        .background(foodJournalCardBackground)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                meal.updatedAt = Date()
                meal.createdAt = draftDate
                viewModel.updateMeal(meal)
                viewModel.activeSheet = nil
            } label: {
                Text("Save changes")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(MacraFoodJournalTheme.accent)
                    .clipShape(Capsule())
            }

            Button {
                viewModel.logMealFromHistory(meal)
                viewModel.activeSheet = nil
            } label: {
                Text("Eat again")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.accent)
            }
        }
    }
}

struct MacraFoodJournalFromHistoryView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    @State private var selection: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                MacraFoodJournalTheme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    HStack {
                        Button("Done") { viewModel.activeSheet = nil }
                            .foregroundColor(MacraFoodJournalTheme.textSoft)
                        Spacer()
                        Text("From history")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Color.clear.frame(width: 42, height: 1)
                    }

                    Picker("History", selection: $selection) {
                        Text("Meals").tag(0)
                        Text("Photos").tag(1)
                        Text("Labels").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if selection == 0 {
                        historyMealsList
                    } else if selection == 1 {
                        MacraFoodJournalPhotoFoodGridView(viewModel: viewModel)
                    } else {
                        MacraLabelScanHistoryView(viewModel: viewModel)
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            viewModel.loadMealHistory()
            viewModel.loadLabelScanHistory()
        }
    }

    @ViewBuilder
    private var historyMealsList: some View {
        if viewModel.isLoadingHistory {
            Spacer()
            ProgressView("Loading meal history...")
                .tint(MacraFoodJournalTheme.accent)
                .foregroundColor(MacraFoodJournalTheme.textSoft)
            Spacer()
        } else if let historyError = viewModel.historyError {
            MacraFoodJournalEmptyState(
                title: "History unavailable",
                message: historyError
            )
            Button("Try again") {
                viewModel.loadMealHistory(force: true)
            }
            .foregroundColor(MacraFoodJournalTheme.accent)
        } else if viewModel.allMealHistory.isEmpty {
            MacraFoodJournalEmptyState(
                title: "No meal history yet",
                message: "Meals you log from Home will appear here so you can quickly eat them again."
            )
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.allMealHistory) { meal in
                        MacraFoodJournalMealRow(meal: meal, onTap: { viewModel.logMealFromHistory(meal) }) {
                            viewModel.logMealFromHistory(meal)
                        } trailingAction: {
                            viewModel.togglePin(meal)
                        }
                    }
                }
            }
        }
    }
}

struct MacraFoodJournalPhotoFoodGridView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingHistory {
                ProgressView("Loading photos...")
                    .tint(MacraFoodJournalTheme.accent)
                    .foregroundColor(MacraFoodJournalTheme.textSoft)
            } else if viewModel.photoHistory.isEmpty {
                MacraFoodJournalEmptyState(
                    title: "No meal photos yet",
                    message: "Meals logged with photos will show up here."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(viewModel.photoHistory) { meal in
                            FoodJournalPhotoTile(meal: meal) {
                                viewModel.openMealDetails(meal)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            viewModel.loadMealHistory()
        }
    }
}

struct MacraFoodJournalMealHistoryRouteView: View {
    @StateObject private var viewModel = MacraFoodJournalViewModel()

    var body: some View {
        ZStack {
            MacraFoodJournalTheme.background.ignoresSafeArea()
            MacraFoodJournalPhotoFoodGridView(viewModel: viewModel)
                .padding(.horizontal, 16)
        }
        .sheet(item: $viewModel.activeSheet) { sheet in
            MacraFoodJournalSheetContentView(viewModel: viewModel, sheet: sheet)
        }
    }
}

// MARK: - Share card layouts

/// Visual variants the user can pick from in the share composer. Each
/// variant renders at a fixed pixel size so `ImageRenderer` always produces
/// a social-media-ready export.
enum MacraShareCardLayout: String, CaseIterable, Identifiable {
    /// 1080×1920 — Instagram Story / TikTok vertical.
    case story
    /// 1080×1080 — Instagram feed / X post.
    case square
    /// 1080×1080 — transparent PNG "sticker" for layering on top of a user
    /// photo in Stories. Same dimensions as `.square` but background is
    /// fully transparent so the meal list floats.
    case sticker

    var id: String { rawValue }

    var renderSize: CGSize {
        switch self {
        case .story: return CGSize(width: 1080, height: 1920)
        case .square, .sticker: return CGSize(width: 1080, height: 1080)
        }
    }

    var displayName: String {
        switch self {
        case .story: return "Story"
        case .square: return "Post"
        case .sticker: return "Sticker"
        }
    }

    var subtitle: String {
        switch self {
        case .story: return "1080×1920 · vertical"
        case .square: return "1080×1080 · feed"
        case .sticker: return "Transparent PNG"
        }
    }

    var isTransparent: Bool { self == .sticker }
}

/// Shareable card summarizing a full day of meals. Fixed-size, designed to
/// be rasterized by `ImageRenderer` rather than displayed in the app chrome.
///
/// Port of the QuickLifts `DailyNutritionShareView` spirit — a hero calorie
/// display, colored macro pills, and a photo grid of the meals — tailored
/// to Macra's data model (`MacraFoodJournalMeal` + preloaded `UIImage`s so
/// photos actually appear in the exported render).
struct MacraFoodJournalDailyNutritionShareView: View {
    let date: Date
    let meals: [MacraFoodJournalMeal]
    let preloadedImages: [String: UIImage]
    let macroTarget: MacraFoodJournalMacroTarget?
    let layout: MacraShareCardLayout

    init(
        date: Date,
        meals: [MacraFoodJournalMeal],
        preloadedImages: [String: UIImage] = [:],
        macroTarget: MacraFoodJournalMacroTarget? = nil,
        layout: MacraShareCardLayout = .story
    ) {
        self.date = date
        self.meals = meals
        self.preloadedImages = preloadedImages
        self.macroTarget = macroTarget
        self.layout = layout
    }

    private var totalCalories: Int { meals.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Int { meals.reduce(0) { $0 + $1.protein } }
    private var totalCarbs: Int { meals.reduce(0) { $0 + $1.carbs } }
    private var totalFat: Int { meals.reduce(0) { $0 + $1.fat } }

    private var calorieProgress: Double {
        guard let target = macroTarget, target.calories > 0 else { return 0 }
        return min(1.2, Double(totalCalories) / Double(target.calories))
    }

    private var sortedMeals: [MacraFoodJournalMeal] {
        meals.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ZStack {
            if !layout.isTransparent {
                background
            }

            switch layout {
            case .story: storyLayout
            case .square: squareLayout
            case .sticker: stickerLayout
            }
        }
        .frame(width: layout.renderSize.width, height: layout.renderSize.height)
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.08, green: 0.10, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Single bold accent glow instead of three competing ones —
            // keeps the card readable when the rasterized image shows up
            // on top of a Story photo.
            RadialGradient(
                colors: [MacraFoodJournalTheme.accent.opacity(0.28), .clear],
                center: .init(x: 0.1, y: 0.05),
                startRadius: 60,
                endRadius: 900
            )
            RadialGradient(
                colors: [MacraFoodJournalTheme.accent2.opacity(0.18), .clear],
                center: .init(x: 0.9, y: 0.95),
                startRadius: 60,
                endRadius: 900
            )
        }
    }

    // MARK: - Adaptive grid density
    //
    // The canvas is fixed (1080px wide); the number of meals is not. Pick a
    // column count so every meal fits without overflowing — users expect to
    // see their full day, not a truncated "+N more" placeholder.

    /// Resolved grid density for a given layout + meal count.
    private struct GridSpec {
        let columns: Int
        /// Approximate square-ish tile height the layout will clip to.
        let tileHeight: CGFloat
        /// When true, tiles collapse to photo + kcal badge only. Kicks in
        /// for dense grids so 16+ meals still fit without clipping the
        /// meal name.
        let compact: Bool
        /// Gap between tiles in both axes.
        let spacing: CGFloat
    }

    private func gridSpec(for canvas: CGSize, contentInset: CGFloat, reservedAboveGrid: CGFloat, reservedBelowGrid: CGFloat) -> GridSpec {
        let count = max(meals.count, 1)
        let columns: Int = {
            switch count {
            case 1: return 1
            case 2: return 2
            case 3...4: return 2
            case 5...9: return 3
            case 10...15: return 4
            default: return 5
            }
        }()

        // Compute available area so tiles always fit the canvas, not the
        // other way around. This is what keeps 11 meals from clipping.
        let available = CGSize(
            width: canvas.width - contentInset * 2,
            height: canvas.height - reservedAboveGrid - reservedBelowGrid
        )
        let rows = Int(ceil(Double(count) / Double(columns)))
        let spacing: CGFloat = count > 9 ? 12 : 16
        let totalSpacingY = spacing * CGFloat(max(rows - 1, 0))
        let tileHeight = max(110, floor((available.height - totalSpacingY) / CGFloat(max(rows, 1))))

        // Tiles go compact when they're physically too small to fit a full
        // text label (name + macro chips) legibly.
        let compact = tileHeight < 220 || columns >= 4

        return GridSpec(columns: columns, tileHeight: tileHeight, compact: compact, spacing: spacing)
    }

    // MARK: - Shared building blocks

    private func brandBadge(small: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(MacraFoodJournalTheme.accent)
                .frame(width: small ? 10 : 12, height: small ? 10 : 12)
            VStack(alignment: .leading, spacing: small ? 0 : 2) {
                Text("MACRA")
                    .font(.system(size: small ? 14 : 18, weight: .black, design: .rounded))
                    .tracking(small ? 2 : 3)
                    .foregroundColor(MacraFoodJournalTheme.accent)
                if !small {
                    Text("food journal")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, small ? 12 : 16)
        .padding(.vertical, small ? 8 : 11)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule().strokeBorder(MacraFoodJournalTheme.accent.opacity(0.45), lineWidth: 1)
                )
        )
    }

    private func datePill(small: Bool = false) -> some View {
        Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .font(.system(size: small ? 13 : 16, weight: .bold, design: .rounded))
            .tracking(small ? 0.8 : 1.2)
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, small ? 12 : 16)
            .padding(.vertical, small ? 8 : 10)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            )
    }

    private func calorieRing(diameter: CGFloat, calorieFontSize: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: calorieProgress)
                .stroke(
                    AngularGradient(
                        colors: [
                            MacraFoodJournalTheme.accent,
                            MacraFoodJournalTheme.accent2,
                            MacraFoodJournalTheme.accent
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(totalCalories)")
                    .font(.system(size: calorieFontSize, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, MacraFoodJournalTheme.accent],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("KCAL")
                    .font(.system(size: calorieFontSize * 0.18, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(lineWidth * 1.6)
        }
        .frame(width: diameter, height: diameter)
    }

    /// Horizontal macro bar with inline progress dots — compact replacement
    /// for the three oversized pill cards that used to clip the canvas.
    private func macroBar(itemHeight: CGFloat) -> some View {
        HStack(spacing: 12) {
            macroCell(label: "PROTEIN", value: totalProtein, target: macroTarget?.protein, tint: MacraFoodJournalTheme.accent2, height: itemHeight)
            macroCell(label: "CARBS", value: totalCarbs, target: macroTarget?.carbs, tint: MacraFoodJournalTheme.accent, height: itemHeight)
            macroCell(label: "FAT", value: totalFat, target: macroTarget?.fat, tint: MacraFoodJournalTheme.accent3, height: itemHeight)
        }
    }

    private func macroCell(label: String, value: Int, target: Int?, tint: Color, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundColor(tint.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("g")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            if let target, target > 0 {
                let progress = min(1.2, Double(value) / Double(target))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                        Capsule()
                            .fill(tint)
                            .frame(width: CGFloat(min(1.0, progress)) * proxy.size.width, height: 4)
                    }
                }
                .frame(height: 4)
                Text("of \(target)g")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(tint.opacity(0.32), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        HStack {
            Text("macra.app")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text("Tracked with Macra")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.38))
        }
    }

    // MARK: - Meal grid (adaptive)

    private func mealGrid(spec: GridSpec) -> some View {
        let columnsArray = Array(repeating: GridItem(.flexible(), spacing: spec.spacing), count: spec.columns)
        return LazyVGrid(columns: columnsArray, spacing: spec.spacing) {
            ForEach(sortedMeals) { meal in
                mealTile(meal: meal, height: spec.tileHeight, compact: spec.compact)
            }
        }
    }

    private var emptyMealsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 54, weight: .regular))
                .foregroundColor(MacraFoodJournalTheme.accent.opacity(0.6))
            Text("Nothing logged today")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                )
        )
    }

    private func mealTile(meal: MacraFoodJournalMeal, height: CGFloat, compact: Bool) -> some View {
        let cornerRadius: CGFloat = height < 150 ? 16 : 22
        let titleFontSize: CGFloat = {
            if compact { return 14 }
            if height >= 280 { return 20 }
            return 16
        }()

        return ZStack(alignment: .bottomLeading) {
            tileBackground(for: meal, height: height)
                .clipped()

            LinearGradient(
                colors: [.clear, .clear, Color.black.opacity(compact ? 0.55 : 0.78)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                calorieBadge(meal.calories, compact: compact)
                if !compact {
                    Text(meal.name)
                        .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if height >= 200 {
                        HStack(spacing: 4) {
                            miniMacro("P", value: meal.protein, tint: MacraFoodJournalTheme.accent2)
                            miniMacro("C", value: meal.carbs, tint: MacraFoodJournalTheme.accent)
                            miniMacro("F", value: meal.fat, tint: MacraFoodJournalTheme.accent3)
                        }
                    }
                }
            }
            .padding(compact ? 10 : 14)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tileBackground(for meal: MacraFoodJournalMeal, height: CGFloat) -> some View {
        if let image = preloadedImages[meal.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            LinearGradient(
                colors: [
                    Color(hue: meal.colorSeed, saturation: 0.55, brightness: 0.32),
                    Color(hue: meal.colorSeed, saturation: 0.80, brightness: 0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: meal.entryMethod == .voice ? "waveform" : "fork.knife")
                    .font(.system(size: min(height * 0.3, 56), weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
            )
        }
    }

    private func calorieBadge(_ calories: Int, compact: Bool) -> some View {
        Text("\(calories) kcal")
            .font(.system(size: compact ? 11 : 13, weight: .heavy, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 3 : 5)
            .background(Capsule().fill(MacraFoodJournalTheme.accent))
    }

    private func miniMacro(_ letter: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            Text(letter)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(tint)
            Text("\(value)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    // MARK: - Story (1080×1920)

    private var storyLayout: some View {
        // Canvas math — works out how much vertical space the header + hero
        // + macro bar consume so the meal grid can claim the rest.
        let inset: CGFloat = 56
        let headerH: CGFloat = 100
        let heroH: CGFloat = 420
        let macroH: CGFloat = 120
        let footerH: CGFloat = 40
        let reservedAbove = 72 + headerH + 32 + heroH + 32 + macroH + 36
        let reservedBelow = 72 + footerH
        let spec = gridSpec(
            for: CGSize(width: layout.renderSize.width, height: layout.renderSize.height),
            contentInset: inset,
            reservedAboveGrid: reservedAbove,
            reservedBelowGrid: reservedBelow
        )

        return VStack(alignment: .leading, spacing: 32) {
            storyHeader
            storyHeroCard(height: heroH)
            macroBar(itemHeight: macroH)
            if meals.isEmpty {
                emptyMealsState
                Spacer(minLength: 0)
            } else {
                mealGrid(spec: spec)
                Spacer(minLength: 0)
            }
            footer
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 72)
    }

    private var storyHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 10) {
                datePill()
                Text("What I ate")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, MacraFoodJournalTheme.accent.opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .tracking(-1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            brandBadge()
        }
    }

    private func storyHeroCard(height: CGFloat) -> some View {
        HStack(spacing: 24) {
            calorieRing(diameter: 300, calorieFontSize: 76, lineWidth: 18)

            VStack(alignment: .leading, spacing: 14) {
                if let target = macroTarget, target.calories > 0 {
                    Text("\(Int(calorieProgress * 100))%")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("of \(target.calories) kcal goal")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Text("\(meals.count)")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(meals.count == 1 ? "meal logged" : "meals logged")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }

                // Inline mini-macro stamp so the hero gives the full picture.
                HStack(spacing: 8) {
                    miniMacro("P", value: totalProtein, tint: MacraFoodJournalTheme.accent2)
                    miniMacro("C", value: totalCarbs, tint: MacraFoodJournalTheme.accent)
                    miniMacro("F", value: totalFat, tint: MacraFoodJournalTheme.accent3)
                }
                .scaleEffect(1.4, anchor: .leading)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .frame(height: height)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [MacraFoodJournalTheme.accent.opacity(0.4), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
    }

    // MARK: - Square / Post (1080×1080)

    private var squareLayout: some View {
        let inset: CGFloat = 44
        let headerH: CGFloat = 80
        let heroH: CGFloat = 260
        let macroH: CGFloat = 96
        let footerH: CGFloat = 30
        let reservedAbove = inset + headerH + 20 + heroH + 18 + macroH + 22
        let reservedBelow = inset + footerH + 16
        let spec = gridSpec(
            for: CGSize(width: layout.renderSize.width, height: layout.renderSize.height),
            contentInset: inset,
            reservedAboveGrid: reservedAbove,
            reservedBelowGrid: reservedBelow
        )

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                datePill(small: true)
                Spacer()
                brandBadge(small: true)
            }
            squareHeroCard(height: heroH)
            macroBar(itemHeight: macroH)
            if meals.isEmpty {
                emptyMealsState
                Spacer(minLength: 0)
            } else {
                mealGrid(spec: spec)
                Spacer(minLength: 0)
            }
            footer
        }
        .padding(inset)
    }

    private func squareHeroCard(height: CGFloat) -> some View {
        HStack(spacing: 20) {
            calorieRing(diameter: 220, calorieFontSize: 54, lineWidth: 14)

            VStack(alignment: .leading, spacing: 10) {
                if let target = macroTarget, target.calories > 0 {
                    Text("\(Int(calorieProgress * 100))%")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("of \(target.calories) kcal")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                } else {
                    Text("\(meals.count)")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(meals.count == 1 ? "meal" : "meals")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }

                HStack(spacing: 6) {
                    miniMacro("P", value: totalProtein, tint: MacraFoodJournalTheme.accent2)
                    miniMacro("C", value: totalCarbs, tint: MacraFoodJournalTheme.accent)
                    miniMacro("F", value: totalFat, tint: MacraFoodJournalTheme.accent3)
                }
                .scaleEffect(1.15, anchor: .leading)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(height: height)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(MacraFoodJournalTheme.accent.opacity(0.35), lineWidth: 1.2)
                )
        )
    }

    // MARK: - Sticker (transparent 1080×1080)

    private var stickerLayout: some View {
        let inset: CGFloat = 36
        let headerH: CGFloat = 64
        let statsH: CGFloat = 96
        let reservedAbove = inset + headerH + 16 + statsH + 18
        let reservedBelow = inset
        let spec = gridSpec(
            for: CGSize(width: layout.renderSize.width, height: layout.renderSize.height),
            contentInset: inset,
            reservedAboveGrid: reservedAbove,
            reservedBelowGrid: reservedBelow
        )

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                datePill(small: true)
                Spacer()
                brandBadge(small: true)
            }

            HStack(spacing: 10) {
                stickerStat(value: "\(totalCalories)", label: "kcal", tint: MacraFoodJournalTheme.accent, emphasize: true)
                stickerStat(value: "\(totalProtein)g", label: "protein", tint: MacraFoodJournalTheme.accent2)
                stickerStat(value: "\(totalCarbs)g", label: "carbs", tint: MacraFoodJournalTheme.accent)
                stickerStat(value: "\(totalFat)g", label: "fat", tint: MacraFoodJournalTheme.accent3)
            }
            .frame(height: statsH)

            if meals.isEmpty {
                emptyMealsState
            } else {
                mealGrid(spec: spec)
            }
            Spacer(minLength: 0)
        }
        .padding(inset)
    }

    private func stickerStat(value: String, label: String, tint: Color, emphasize: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: emphasize ? 34 : 28, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.8)
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(tint.opacity(emphasize ? 0.6 : 0.35), lineWidth: 1.2)
                )
        )
    }
}

struct MacraFoodJournalMealRow: View {
    let meal: MacraFoodJournalMeal
    let onTap: () -> Void
    let relogAction: () -> Void
    let trailingAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FoodJournalThumbnail(meal: meal)
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(meal.shortSummary)
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
                Text(meal.displayTime)
                    .font(.caption2)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
            Spacer()
            VStack(spacing: 8) {
                Button(action: relogAction) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(MacraFoodJournalTheme.accent)
                        .padding(8)
                        .background(Circle().fill(MacraFoodJournalTheme.panel))
                }
                Button(action: trailingAction) {
                    Image(systemName: meal.isPinned ? "pin.fill" : "pin")
                        .foregroundColor(meal.isPinned ? MacraFoodJournalTheme.accent : MacraFoodJournalTheme.textMuted)
                        .padding(8)
                        .background(Circle().fill(MacraFoodJournalTheme.panel))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .padding(12)
        .background(foodJournalCardBackground)
    }
}

struct FoodJournalThumbnail: View {
    let meal: MacraFoodJournalMeal

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: meal.colorSeed, saturation: 0.45, brightness: 0.28),
                            Color(hue: meal.colorSeed, saturation: 0.75, brightness: 0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 68, height: 68)
            if meal.hasPhoto {
                AsyncImage(url: URL(string: meal.imageURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: meal.entryMethod == .voice ? "mic.fill" : "fork.knife")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Image(systemName: meal.entryMethod == .voice ? "mic.fill" : "fork.knife")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
            }
        }
    }
}

struct FoodJournalPhotoTile: View {
    let meal: MacraFoodJournalMeal
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: meal.colorSeed, saturation: 0.5, brightness: 0.25),
                                Color(hue: meal.colorSeed, saturation: 0.6, brightness: 0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 170)
                AsyncImage(url: URL(string: meal.imageURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "photo.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 170)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text("\(meal.calories) cal")
                        .font(.caption)
                        .foregroundColor(MacraFoodJournalTheme.textSoft)
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FoodJournalMacroRing: View {
    let calories: Int
    let target: Int?
    let accent: Color

    private var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(1, Double(calories) / Double(target))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [accent, MacraFoodJournalTheme.accent2, accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(target == nil ? "--" : "\(Int(progress * 100))%")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                Text(target == nil ? "no goal" : "of goal")
                    .font(.caption2)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
        }
    }
}

struct FoodJournalActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(14)
            .background(foodJournalCardBackground)
        }
        .buttonStyle(.plain)
    }
}

struct FoodJournalSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
            content
        }
        .padding(16)
        .background(foodJournalCardBackground)
    }
}

struct MacraFoodJournalEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf")
                .font(.title2)
                .foregroundColor(MacraFoodJournalTheme.accent)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(MacraFoodJournalTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

struct MacraFoodJournalMissingMealView: View {
    var message: String = "That meal is no longer available."

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(message)
                .font(.headline)
                .foregroundColor(.white)
            Text("Try opening a different journal entry.")
                .font(.subheadline)
                .foregroundColor(MacraFoodJournalTheme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(MacraFoodJournalTheme.background)
    }
}

var foodJournalCardBackground: some View {
    RoundedRectangle(cornerRadius: 24)
        .fill(
            LinearGradient(
                colors: [
                    MacraFoodJournalTheme.panel,
                    MacraFoodJournalTheme.panelSoft
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
}

// MARK: - Share composer

/// Pre-fetches every `meal.imageURL` so the rasterized share card actually
/// contains photos (`ImageRenderer` can't wait on `AsyncImage`). Kept
/// lightweight — simple URLSession + NSCache to avoid double-loading when
/// the user flicks between layout variants.
@MainActor
final class MacraShareImageLoader: ObservableObject {
    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var isLoading: Bool = false

    private var inFlight: Set<String> = []

    /// Kick off fetches for any meals whose photos aren't already loaded.
    /// Safe to call repeatedly; already-fetched URLs are skipped.
    func prefetch(meals: [MacraFoodJournalMeal]) async {
        let urls: [(id: String, url: URL)] = meals.compactMap { meal in
            guard
                let raw = meal.imageURL,
                !raw.isEmpty,
                images[meal.id] == nil,
                !inFlight.contains(meal.id),
                let url = URL(string: raw)
            else { return nil }
            return (meal.id, url)
        }

        guard !urls.isEmpty else { return }

        isLoading = true
        urls.forEach { inFlight.insert($0.id) }

        // Fetch `Data` on background tasks (Data is Sendable; UIImage is not
        // strictly Sendable, so we convert after hopping back to the actor).
        await withTaskGroup(of: (String, Data?).self) { group in
            for (id, url) in urls {
                group.addTask {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        return (id, data)
                    } catch {
                        print("[Macra][ShareLoader] ❌ failed to load \(url.absoluteString): \(error.localizedDescription)")
                        return (id, nil)
                    }
                }
            }
            for await (id, data) in group {
                if let data, let image = UIImage(data: data) {
                    images[id] = image
                }
                inFlight.remove(id)
            }
        }

        isLoading = false
    }
}

/// Shareable-card composer. Matches the QuickLifts pattern:
/// - swipable carousel of layout variants
/// - fixed-size card rasterized on demand via `ImageRenderer`
/// - primary actions: Share, Save to Photos, Copy, Save transparent PNG
struct MacraShareComposerSheet: View {
    let date: Date
    let meals: [MacraFoodJournalMeal]
    let macroTarget: MacraFoodJournalMacroTarget?
    let onClose: () -> Void

    @StateObject private var loader = MacraShareImageLoader()
    @State private var selectedLayout: MacraShareCardLayout = .story
    @State private var isExporting: Bool = false
    @State private var toastMessage: String?

    var body: some View {
        ZStack {
            MacraFoodJournalTheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                header

                GeometryReader { proxy in
                    TabView(selection: $selectedLayout) {
                        ForEach(MacraShareCardLayout.allCases) { layout in
                            carouselCard(for: layout, availableSize: proxy.size)
                                .tag(layout)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 560)

                layoutPicker

                actionButtons

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)

            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(MacraFoodJournalTheme.accent))
                        .padding(.bottom, 120)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            if isExporting {
                Color.black.opacity(0.55).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: MacraFoodJournalTheme.accent))
                    .scaleEffect(1.4)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await loader.prefetch(meals: meals)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            Spacer()
            VStack(spacing: 2) {
                Text("Share your day")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                Text(loader.isLoading ? "Loading photos…" : date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
    }

    // MARK: - Carousel preview

    /// Builds one preview tile for the carousel. Scale is computed from the
    /// available space (minus room for the label below + horizontal padding)
    /// so the full card is always visible — no cropping on small phones,
    /// no dead space on larger ones.
    private func carouselCard(for layout: MacraShareCardLayout, availableSize: CGSize) -> some View {
        let labelReserve: CGFloat = 48
        let horizontalInset: CGFloat = 40
        let maxWidth = max(availableSize.width - horizontalInset, 100)
        let maxHeight = max(availableSize.height - labelReserve, 100)

        let widthScale = maxWidth / layout.renderSize.width
        let heightScale = maxHeight / layout.renderSize.height
        let scale = min(widthScale, heightScale)

        let scaledWidth = layout.renderSize.width * scale
        let scaledHeight = layout.renderSize.height * scale

        return VStack(spacing: 12) {
            ZStack {
                if layout.isTransparent {
                    // Visual checkerboard so users see that transparency is
                    // intentional — matches the PNG output.
                    CheckerboardBackground()
                }

                MacraFoodJournalDailyNutritionShareView(
                    date: date,
                    meals: meals,
                    preloadedImages: loader.images,
                    macroTarget: macroTarget,
                    layout: layout
                )
                .frame(width: layout.renderSize.width, height: layout.renderSize.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: scaledWidth, height: scaledHeight)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 22, x: 0, y: 12)

            Text("\(layout.displayName) · \(layout.subtitle)")
                .font(.caption.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var layoutPicker: some View {
        HStack(spacing: 8) {
            ForEach(MacraShareCardLayout.allCases) { layout in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedLayout = layout }
                } label: {
                    Text(layout.displayName)
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundColor(selectedLayout == layout ? .black : .white.opacity(0.75))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(selectedLayout == layout ? MacraFoodJournalTheme.accent : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                actionButton(title: "Share", systemImage: "square.and.arrow.up", tint: MacraFoodJournalTheme.accent, isPrimary: true) {
                    exportAndPerform { image in
                        MacraShareSheetPresenter.present(items: [image])
                    }
                }
                actionButton(title: "Save", systemImage: "photo.on.rectangle", tint: MacraFoodJournalTheme.accent2) {
                    exportAndPerform { image in
                        MacraSharePhotoSaver.save(image: image, asPNG: selectedLayout.isTransparent) { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success: flashToast("Saved to Photos")
                                case .failure(let error):
                                    print("[Macra][ShareComposer] ❌ save failed: \(error.localizedDescription)")
                                    flashToast("Couldn't save — check Photos permission")
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                actionButton(title: "Copy", systemImage: "doc.on.doc", tint: MacraFoodJournalTheme.accent3) {
                    exportAndPerform { image in
                        UIPasteboard.general.image = image
                        flashToast("Copied to clipboard")
                    }
                }
                actionButton(title: "Done", systemImage: "checkmark", tint: Color.white.opacity(0.12)) {
                    onClose()
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(title: String, systemImage: String, tint: Color, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.subheadline.weight(.bold))
            }
            .foregroundColor(isPrimary ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isPrimary ? tint : tint)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rendering

    /// Render the current layout to a `UIImage`, then invoke `action` on the
    /// main thread. Shows a spinner while rendering — the work is cheap but
    /// the loader state also keeps users from triple-tapping.
    private func exportAndPerform(_ action: @escaping (UIImage) -> Void) {
        let layout = selectedLayout
        let date = date
        let meals = meals
        let target = macroTarget
        let images = loader.images

        isExporting = true

        DispatchQueue.main.async {
            let view = MacraFoodJournalDailyNutritionShareView(
                date: date,
                meals: meals,
                preloadedImages: images,
                macroTarget: target,
                layout: layout
            )
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = .init(width: layout.renderSize.width, height: layout.renderSize.height)
            renderer.scale = UIScreen.main.scale

            // Transparent PNG needs a clear background on the root renderer so
            // `uiImage` carries through the alpha channel. `ImageRenderer`
            // bakes whatever is in the view; the sticker layout skips the
            // background gradient so this effectively works.
            if layout.isTransparent {
                renderer.isOpaque = false
            }

            isExporting = false

            guard let uiImage = renderer.uiImage else {
                print("[Macra][ShareComposer] ❌ ImageRenderer returned nil for layout:\(layout.rawValue)")
                flashToast("Couldn't render that card — try another layout")
                return
            }
            print("[Macra][ShareComposer] ✅ rendered \(layout.rawValue) size:\(Int(uiImage.size.width))×\(Int(uiImage.size.height))")
            action(uiImage)
        }
    }

    private func flashToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.25)) { toastMessage = nil }
        }
    }
}

// MARK: - Share plumbing helpers

/// Presents a `UIActivityViewController` from the top-most view controller.
///
/// `MacraShareComposerSheet` is itself shown as a SwiftUI sheet, and SwiftUI
/// sheets can't reliably present another sheet on top of themselves. Routing
/// directly through UIKit avoids the "nested sheet" brittleness and works
/// from any presentation context.
enum MacraShareSheetPresenter {
    @MainActor
    static func present(items: [Any]) {
        guard let root = topViewController() else {
            print("[Macra][ShareSheet] ❌ no root view controller available")
            return
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad requires a source view/rect for the popover presentation.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(
                x: root.view.bounds.midX,
                y: root.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        root.present(controller, animated: true)
    }

    @MainActor
    private static func topViewController(base: UIViewController? = {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        return keyWindow?.rootViewController
    }()) -> UIViewController? {
        if let navigation = base as? UINavigationController {
            return topViewController(base: navigation.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

/// Subtle checkerboard so users see that the sticker layout is a true
/// transparent PNG in the preview.
private struct CheckerboardBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size: CGFloat = 20
            let cols = Int(ceil(proxy.size.width / size))
            let rows = Int(ceil(proxy.size.height / size))
            Canvas { context, canvasSize in
                for row in 0..<rows {
                    for col in 0..<cols {
                        let isDark = (row + col).isMultiple(of: 2)
                        let rect = CGRect(x: CGFloat(col) * size, y: CGFloat(row) * size, width: size, height: size)
                        context.fill(Path(rect), with: .color(isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.09)))
                    }
                }
                _ = canvasSize
            }
        }
    }
}

/// Routes `Save to Photos` through `PHPhotoLibrary` so we can preserve the
/// PNG's alpha channel for the sticker layout. JPEG encoding (the default
/// behavior of `UIImageWriteToSavedPhotosAlbum`) would flatten transparency
/// against white.
enum MacraSharePhotoSaver {
    static func save(image: UIImage, asPNG: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(.failure(NSError(
                    domain: "MacraSharePhotoSaver",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Photo Library access is required to save share cards."]
                )))
                return
            }

            PHPhotoLibrary.shared().performChanges({
                if asPNG, let pngData = image.pngData() {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = "public.png"
                    request.addResource(with: .photo, data: pngData, options: options)
                } else {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }, completionHandler: { success, error in
                if let error {
                    completion(.failure(error))
                } else if success {
                    completion(.success(()))
                } else {
                    completion(.failure(NSError(
                        domain: "MacraSharePhotoSaver",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Photo Library rejected the save."]
                    )))
                }
            })
        }
    }
}
