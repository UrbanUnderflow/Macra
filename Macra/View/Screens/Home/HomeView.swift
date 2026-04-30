import SwiftUI
import PhotosUI
import Combine
import FirebaseAuth
import FirebaseFirestore

final class HomeViewModel: ObservableObject {
    let appCoordinator: AppCoordinator
    let serviceManager: ServiceManager

    @Published var macroTarget: MacroRecommendation?
    @Published var todaysMeals: [Meal] = []
    @Published var recentMeals: [Meal] = []
    @Published var recentLabelScans: [MacraScannedLabel] = []
    @Published var pinnedLabelScans: [MacraScannedLabel] = []
    @Published var pinnedFoodSnaps: [Meal] = []
    @Published var loggedSupplements: [LoggedSupplement] = []
    @Published var mealLoggedDates: Set<Date> = []
    @Published var dailyInsight: MacraFoodJournalDailyInsight?
    @Published var isGeneratingInsight: Bool = false
    @Published var dailyInsightError: String?
    @Published var isLoading = false

    private var insightSubscriptions: Set<AnyCancellable> = []
    @Published var isLoadingScans = false
    @Published var scanHistoryError: String?
    @Published var showLoader = false
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private var loadGeneration = 0
    /// Meals we've already kicked off background reanalysis for. Prevents
    /// repeated GPT calls on every journal load for meals where the analyzer
    /// genuinely can't infer macros (e.g. unreadable label, no usable text).
    private var attemptedAutoReanalysisIDs: Set<String> = []

    init(appCoordinator: AppCoordinator, serviceManager: ServiceManager) {
        self.appCoordinator = appCoordinator
        self.serviceManager = serviceManager
        bindCloudInsight()
    }

    /// Mirror the cloud-driven insight service into HomeViewModel-published state
    /// so existing views (HomeDailyInsightCard) keep their bindings unchanged.
    /// Subscription is keyed to `selectedDate`; the listener auto-rebinds when
    /// the user navigates days.
    private func bindCloudInsight() {
        Task { @MainActor in
            MacraDailyInsightService.shared.subscribe(to: self.selectedDate)
        }

        Task { @MainActor in
            MacraDailyInsightService.shared.$insight
                .receive(on: DispatchQueue.main)
                .sink { [weak self] insight in self?.dailyInsight = insight }
                .store(in: &self.insightSubscriptions)

            MacraDailyInsightService.shared.$isRegenerating
                .receive(on: DispatchQueue.main)
                .sink { [weak self] flag in self?.isGeneratingInsight = flag }
                .store(in: &self.insightSubscriptions)

            MacraDailyInsightService.shared.$lastError
                .receive(on: DispatchQueue.main)
                .sink { [weak self] err in self?.dailyInsightError = err }
                .store(in: &self.insightSubscriptions)
        }

        $selectedDate
            .removeDuplicates(by: { Calendar.current.isDate($0, inSameDayAs: $1) })
            .sink { date in
                Task { @MainActor in
                    MacraDailyInsightService.shared.subscribe(to: date)
                }
            }
            .store(in: &insightSubscriptions)
    }

    var mealCalories: Int { todaysMeals.reduce(0) { $0 + $1.calories } }
    var mealProtein: Int { todaysMeals.reduce(0) { $0 + $1.protein } }
    var mealCarbs: Int { todaysMeals.reduce(0) { $0 + $1.carbs } }
    var mealFat: Int { todaysMeals.reduce(0) { $0 + $1.fat } }

    var supplementCalories: Int { loggedSupplements.reduce(0) { $0 + $1.calories } }
    var supplementProtein: Int { loggedSupplements.reduce(0) { $0 + $1.protein } }
    var supplementCarbs: Int { loggedSupplements.reduce(0) { $0 + $1.carbs } }
    var supplementFat: Int { loggedSupplements.reduce(0) { $0 + $1.fat } }

    var totalCalories: Int { mealCalories + supplementCalories }
    var totalProtein: Int { mealProtein + supplementProtein }
    var totalCarbs: Int { mealCarbs + supplementCarbs }
    var totalFat: Int { mealFat + supplementFat }

    var todaysMealsAsFoodJournal: [MacraFoodJournalMeal] {
        todaysMeals.map(MacraFoodJournalMeal.init(meal:))
    }

    var hasNetCarbAdjustment: Bool {
        todaysMealsAsFoodJournal.contains(where: { $0.hasNetCarbAdjustment })
    }

    var totalNetCarbs: Int {
        todaysMealsAsFoodJournal.reduce(0) { $0 + $1.netCarbs }
    }

    // MARK: - Extended nutrient totals (for the full nutrition modal)

    var totalDietaryFiber: Int { todaysMeals.compactMap { $0.fiber }.reduce(0, +) }
    var totalSugars: Int { todaysMeals.compactMap { $0.sugars }.reduce(0, +) }
    var totalSugarAlcohols: Int { todaysMeals.compactMap { $0.sugarAlcohols }.reduce(0, +) }
    var totalSodium: Int { todaysMeals.compactMap { $0.sodium }.reduce(0, +) }
    var totalCholesterol: Int { todaysMeals.compactMap { $0.cholesterol }.reduce(0, +) }
    var totalSaturatedFat: Int { todaysMeals.compactMap { $0.saturatedFat }.reduce(0, +) }
    var totalUnsaturatedFat: Int { todaysMeals.compactMap { $0.unsaturatedFat }.reduce(0, +) }

    /// Vitamins from meals only — supplement contributions get tracked separately
    /// so the modal can show "+X" badges next to rows that supplements boost.
    var mealVitamins: [String: Int] {
        var bag: [String: Int] = [:]
        for meal in todaysMeals {
            guard let v = meal.vitamins else { continue }
            for (key, value) in v {
                let normalized = HomeViewModel.normalizeNutrientName(key)
                bag[normalized, default: 0] += value
            }
        }
        return bag
    }

    var mealMinerals: [String: Int] {
        var bag: [String: Int] = [:]
        for meal in todaysMeals {
            guard let m = meal.minerals else { continue }
            for (key, value) in m {
                let normalized = HomeViewModel.normalizeNutrientName(key)
                bag[normalized, default: 0] += value
            }
        }
        return bag
    }

    var supplementVitamins: [String: Int] {
        var bag: [String: Int] = [:]
        for supp in loggedSupplements {
            guard let v = supp.vitamins else { continue }
            for (key, value) in v {
                let normalized = HomeViewModel.normalizeNutrientName(key)
                bag[normalized, default: 0] += value
            }
        }
        return bag
    }

    var supplementMinerals: [String: Int] {
        var bag: [String: Int] = [:]
        for supp in loggedSupplements {
            guard let m = supp.minerals else { continue }
            for (key, value) in m {
                let normalized = HomeViewModel.normalizeNutrientName(key)
                bag[normalized, default: 0] += value
            }
        }
        return bag
    }

    /// True if anything beyond core macros has been logged today — drives
    /// whether the "Full nutrition" card surfaces.
    var hasFullNutritionDetail: Bool {
        if totalDietaryFiber > 0 { return true }
        if totalSugars > 0 { return true }
        if totalSugarAlcohols > 0 { return true }
        if totalSodium > 0 { return true }
        if totalCholesterol > 0 { return true }
        if totalSaturatedFat > 0 { return true }
        if totalUnsaturatedFat > 0 { return true }
        if !mealVitamins.isEmpty || !supplementVitamins.isEmpty { return true }
        if !mealMinerals.isEmpty || !supplementMinerals.isEmpty { return true }
        return totalCalories > 0 // always show full table once any meal is logged
    }

    /// Title-case a nutrient key while preserving vitamin letter+number suffixes
    /// (e.g. "vitamin b12" → "Vitamin B12", "iron" → "Iron").
    private static func normalizeNutrientName(_ name: String) -> String {
        name.split(separator: " ")
            .map { word -> String in
                let lower = word.lowercased()
                if lower.count <= 3, word.first?.isLetter == true, word.contains(where: { $0.isNumber }) {
                    return word.uppercased()
                }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    var loggingStats: MacraFoodJournalLoggingStats {
        MacraFoodJournalLoggingStats(loggedDates: mealLoggedDates, referenceDate: Date())
    }

    func generateDailyInsight() {
        let date = selectedDate
        Task { @MainActor in
            await MacraDailyInsightService.shared.regenerate(for: date)
        }
    }

    var canNavigateToPreviousDay: Bool { true }

    var canNavigateToNextDay: Bool {
        !Calendar.current.isDate(selectedDate, inSameDayAs: Date())
    }

    func navigateToPreviousDay() {
        guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        selectedDate = Calendar.current.startOfDay(for: previous)
        print("[Macra][Nora][SELECTED-DATE-CHANGE] navigateToPreviousDay → \(selectedDate) (now=\(Date()))")
        clearSelectedDayContext()
        load()
    }

    func navigateToNextDay() {
        guard canNavigateToNextDay,
              let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        selectedDate = min(Calendar.current.startOfDay(for: next), today)
        print("[Macra][Nora][SELECTED-DATE-CHANGE] navigateToNextDay → \(selectedDate) (now=\(Date()))")
        clearSelectedDayContext()
        load()
    }

    func setSelectedDate(_ date: Date) {
        let today = Calendar.current.startOfDay(for: Date())
        let normalized = Calendar.current.startOfDay(for: date)
        let capped = normalized > today ? today : normalized
        guard !Calendar.current.isDate(capped, inSameDayAs: selectedDate) else { return }
        selectedDate = capped
        print("[Macra][Nora][SELECTED-DATE-CHANGE] setSelectedDate(\(date)) → \(selectedDate) (now=\(Date()))")
        clearSelectedDayContext()
        load()
    }

    func load() {
        guard let userId = serviceManager.userService.user?.id ?? Auth.auth().currentUser?.uid,
              !userId.isEmpty else {
            isLoading = false
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        let requestedDate = selectedDate

        isLoading = true
        let group = DispatchGroup()

        group.enter()
        MacroRecommendationService.sharedInstance.getCurrentMacroRecommendation(for: userId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let rec) = result, let rec = rec {
                    self?.macroTarget = rec
                    UserService.sharedInstance.currentMacroTarget = rec
                }
                group.leave()
            }
        }

        group.enter()
        MealService.sharedInstance.getMeals(byDate: requestedDate, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    group.leave()
                    return
                }
                if self.isCurrentLoad(generation, for: requestedDate),
                   case .success(let meals) = result {
                    self.todaysMeals = meals
                    // Silently reanalyze any meal that landed with all-zero
                    // macros (e.g. label scans saved before the analyzer
                    // returned numbers). Runs in background; results are
                    // written back to Firestore + the source label scan so
                    // future logs of the same scan pick up the corrected macros.
                    self.autoReanalyzeZeroMacroMealsIfNeeded(in: meals, userId: userId)
                }
                group.leave()
            }
        }

        group.enter()
        MealService.sharedInstance.getRecentMeals(userId: userId, limit: 30) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let meals) = result {
                    self?.recentMeals = meals.sorted { $0.createdAt > $1.createdAt }
                }
                group.leave()
            }
        }

        group.enter()
        loadRecentLabelScans {
            group.leave()
        }

        group.enter()
        loadPinnedLabelScans {
            group.leave()
        }

        group.enter()
        loadPinnedFoodSnaps {
            group.leave()
        }

        group.enter()
        SupplementService.sharedInstance.getLoggedSupplements(byDate: requestedDate) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    group.leave()
                    return
                }
                if self.isCurrentLoad(generation, for: requestedDate) {
                    if case .success(let supplements) = result {
                        self.loggedSupplements = supplements
                    } else {
                        self.loggedSupplements = []
                    }
                }
                group.leave()
            }
        }

        group.enter()
        loadMealLoggedDates {
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, self.isCurrentLoad(generation, for: requestedDate) else { return }
            self.isLoading = false
        }
    }

    private func clearSelectedDayContext() {
        loadGeneration += 1
        todaysMeals = []
        loggedSupplements = []
        dailyInsight = nil
        dailyInsightError = nil
        isLoading = true
    }

    private func isCurrentLoad(_ generation: Int, for date: Date) -> Bool {
        generation == loadGeneration && Calendar.current.isDate(selectedDate, inSameDayAs: date)
    }

    // MARK: - Background auto-reanalyze for 0/0/0 meals

    private func autoReanalyzeZeroMacroMealsIfNeeded(in meals: [Meal], userId: String) {
        let candidates = meals.filter { meal in
            meal.calories == 0 && meal.protein == 0 && meal.carbs == 0 && meal.fat == 0
        }
        for meal in candidates where !attemptedAutoReanalysisIDs.contains(meal.id) {
            attemptedAutoReanalysisIDs.insert(meal.id)
            runAutoReanalyze(meal: meal, userId: userId)
        }
    }

    private func runAutoReanalyze(meal: Meal, userId: String) {
        let trimmedImage = meal.image.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImage = !trimmedImage.isEmpty
        let trimmedName = meal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCaption = meal.caption.trimmingCharacters(in: .whitespacesAndNewlines)

        let derivedDescription: String = {
            if !trimmedCaption.isEmpty { return trimmedCaption }
            if let detailed = meal.detailedIngredients, !detailed.isEmpty {
                return detailed
                    .map { "\($0.quantity) \($0.name)".trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            }
            if !meal.ingredients.isEmpty {
                return meal.ingredients.joined(separator: ", ")
            }
            return ""
        }()

        let hasUsableText = !trimmedName.isEmpty || !derivedDescription.isEmpty
        guard hasImage || hasUsableText else { return }

        print("[Macra][HomeViewModel.autoReanalyze] ▶️ kicking 0/0/0 meal '\(meal.name)' hasImage:\(hasImage)")

        let handler: (Result<GPTService.MealAnalysis, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let analysis):
                    self.applyAutoReanalysis(meal: meal, analysis: analysis, userId: userId)
                case .failure(let error):
                    print("[Macra][HomeViewModel.autoReanalyze] ❌ \(meal.name): \(error.localizedDescription)")
                }
            }
        }

        // Pick the right analyzer:
        //   - Label-derived meals get the label-image analyzer (reads the
        //     nutrition-facts panel directly).
        //   - Other photo-backed meals → food-photo vision.
        //   - No image → text fallback.
        let isLabelOrigin = trimmedCaption.lowercased().contains("label scan")
            || trimmedCaption.lowercased().contains("logged from label")

        if hasImage, isLabelOrigin {
            GPTService.sharedInstance.analyzeMealFromLabelImage(
                imageURL: trimmedImage,
                title: trimmedName,
                completion: handler
            )
        } else if hasImage {
            GPTService.sharedInstance.analyzeMealFromFoodPhoto(
                imageURL: trimmedImage,
                title: trimmedName,
                description: derivedDescription,
                completion: handler
            )
        } else {
            let analysisDescription = derivedDescription.isEmpty ? trimmedName : derivedDescription
            let analysisTitle = derivedDescription.isEmpty ? "" : trimmedName
            GPTService.sharedInstance.analyzeMealNote(
                title: analysisTitle,
                description: analysisDescription,
                completion: handler
            )
        }
    }

    private func applyAutoReanalysis(meal originalMeal: Meal, analysis: GPTService.MealAnalysis, userId: String) {
        var updated = originalMeal
        updated.calories = analysis.calories
        updated.protein = analysis.protein
        updated.carbs = analysis.carbs
        updated.fat = analysis.fat
        updated.fiber = analysis.fiber
        updated.sugarAlcohols = analysis.sugarAlcohols

        let mappedDetailed: [MealIngredientDetail] = analysis.ingredients.map {
            MealIngredientDetail(
                name: $0.name,
                quantity: $0.quantity,
                calories: $0.calories,
                protein: $0.protein,
                carbs: $0.carbs,
                fat: $0.fat,
                fiber: $0.fiber,
                sugarAlcohols: $0.sugarAlcohols
            )
        }
        if !mappedDetailed.isEmpty {
            updated.detailedIngredients = mappedDetailed
            updated.ingredients = mappedDetailed.map(\.name)
        }
        updated.updatedAt = Date()

        MealService.sharedInstance.updateMeal(updated, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let saved):
                    if let idx = self.todaysMeals.firstIndex(where: { $0.id == saved.id }) {
                        self.todaysMeals[idx] = saved
                    }
                    print("[Macra][HomeViewModel.autoReanalyze] ✅ '\(saved.name)' → \(saved.calories) kcal, \(saved.protein)P \(saved.carbs)C \(saved.fat)F")
                    self.persistReanalysisToLabelScan(meal: saved)
                case .failure(let error):
                    print("[Macra][HomeViewModel.autoReanalyze] ❌ save failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// If the meal was logged from a label scan, push the corrected macros
    /// back to the source `MacraScannedLabel` so future logs of the same
    /// scan don't repeat the 0/0/0 problem. Match by image URL — scans
    /// always have a unique Firebase Storage URL.
    private func persistReanalysisToLabelScan(meal: Meal) {
        let trimmedImage = meal.image.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedImage.isEmpty else { return }

        let knownScans = pinnedLabelScans + recentLabelScans
        guard let scan = knownScans.first(where: { ($0.imageURL ?? "") == trimmedImage }) else {
            return
        }

        let macros = LabelNutritionFacts(
            calories: meal.calories,
            protein: meal.protein,
            fat: meal.fat,
            carbs: meal.carbs,
            servingSize: scan.gradeResult.servingSize,
            sugars: nil,
            dietaryFiber: meal.fiber,
            sugarAlcohols: meal.sugarAlcohols,
            sodium: nil
        )

        LabelScanService.shared.updateMacros(scanId: scan.id, macros: macros) { result in
            switch result {
            case .success:
                print("[Macra][HomeViewModel.persistReanalysisToLabelScan] ✅ updated scan \(scan.id) with reanalyzed macros")
            case .failure(let error):
                print("[Macra][HomeViewModel.persistReanalysisToLabelScan] ❌ \(error.localizedDescription)")
            }
        }
    }

    private func loadMealLoggedDates(completion: @escaping () -> Void) {
        guard let userId = serviceManager.userService.user?.id ?? Auth.auth().currentUser?.uid,
              !userId.isEmpty else {
            completion()
            return
        }
        MealService.sharedInstance.getRecentMeals(userId: userId, limit: 200) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let meals) = result {
                    let calendar = Calendar.current
                    self?.mealLoggedDates = Set(meals.map { calendar.startOfDay(for: $0.createdAt) })
                }
                completion()
            }
        }
    }

    // MARK: - Pins

    func isLabelPinned(_ id: String) -> Bool {
        pinnedLabelScans.contains { $0.id == id }
    }

    func isFoodSnapPinned(_ meal: Meal) -> Bool {
        let docId = pinnedMealDocumentID(for: meal)
        return pinnedFoodSnaps.contains { pinnedMealDocumentID(for: $0) == docId }
    }

    func togglePinLabel(_ scan: MacraScannedLabel) {
        let userIDs = scanHistoryUserIDs()
        guard let userId = userIDs.first else { return }

        if isLabelPinned(scan.id) {
            pinnedLabelScans.removeAll { $0.id == scan.id }
            for candidateUserID in userIDs {
                MacraPinnedScanService.sharedInstance.unpinLabelScan(id: scan.id, userId: candidateUserID) { _ in }
            }
        } else {
            var updated = pinnedLabelScans
            updated.append(scan)
            pinnedLabelScans = updated
            let nextOrder = (pinnedLabelScans.count) * 1000
            MacraPinnedScanService.sharedInstance.pinLabelScan(scan, userId: userId, sortOrder: nextOrder) { _ in }
        }
    }

    func togglePinFoodSnap(_ meal: Meal) {
        let userIDs = scanHistoryUserIDs()
        guard let userId = userIDs.first else { return }

        let docId = pinnedMealDocumentID(for: meal)
        if isFoodSnapPinned(meal) {
            pinnedFoodSnaps.removeAll { pinnedMealDocumentID(for: $0) == docId }
            for candidateUserID in userIDs {
                MealService.sharedInstance.deletePinnedMeal(withId: docId, userId: candidateUserID) { _ in }
                MacraPinnedScanService.sharedInstance.unpinFoodSnap(id: meal.id, userId: candidateUserID) { _ in }
            }
        } else {
            var updated = pinnedFoodSnaps
            var pinnedCopy = meal
            pinnedCopy.id = docId
            updated.append(pinnedCopy)
            pinnedFoodSnaps = updated
            let nextOrder = (pinnedFoodSnaps.count) * 1000
            MealService.sharedInstance.savePinnedMeal(meal, sortOrder: nextOrder, userId: userId) { _ in }
        }
    }

    func loadPinnedLabelScans(completion: (() -> Void)? = nil) {
        loadPinnedLabelScans(from: scanHistoryUserIDs(), index: 0) { [weak self] scans in
            DispatchQueue.main.async {
                self?.pinnedLabelScans = scans
                completion?()
            }
        }
    }

    func loadPinnedFoodSnaps(completion: (() -> Void)? = nil) {
        let userIDs = scanHistoryUserIDs()
        loadPinnedMeals(from: userIDs, index: 0) { [weak self] meals in
            guard let self else {
                completion?()
                return
            }

            if !meals.isEmpty {
                DispatchQueue.main.async {
                    self.pinnedFoodSnaps = meals
                    completion?()
                }
            } else {
                self.loadPinnedLegacyFoodSnaps(from: userIDs, index: 0) { [weak self] legacyMeals in
                    DispatchQueue.main.async {
                        self?.pinnedFoodSnaps = legacyMeals
                        completion?()
                    }
                }
            }
        }
    }

    func quickLogPinnedLabel(_ scan: MacraScannedLabel) {
        guard let userId = serviceManager.userService.user?.id ?? Auth.auth().currentUser?.uid,
              !userId.isEmpty else { return }

        let grade = scan.gradeResult
        let title = scan.displayTitle
        let now = Date()
        let logged = Meal(
            id: MealPlanningIDs.make(prefix: "meal"),
            name: title,
            categories: [.unknown],
            ingredients: [],
            detailedIngredients: nil,
            caption: "Logged from pinned label scan",
            calories: grade.calories ?? 0,
            protein: grade.protein ?? 0,
            fat: grade.fat ?? 0,
            carbs: grade.carbs ?? 0,
            image: scan.imageURL ?? "",
            entryMethod: .unknown,
            servingSize: grade.servingSize,
            sourceReferences: nil,
            createdAt: now,
            updatedAt: now
        )

        MealService.sharedInstance.saveMeal(logged, for: selectedDate, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result { self?.load() }
            }
        }
    }

    func quickLogPinnedFoodSnap(_ meal: Meal) {
        guard let userId = serviceManager.userService.user?.id ?? Auth.auth().currentUser?.uid,
              !userId.isEmpty else { return }

        let now = Date()
        var copy = meal
        copy.id = MealPlanningIDs.make(prefix: "meal")
        copy.createdAt = now
        copy.updatedAt = now

        MealService.sharedInstance.saveMeal(copy, for: selectedDate, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result { self?.load() }
            }
        }
    }

    func copyTodaysMealsToDate(_ targetDate: Date, completion: @escaping (Result<Int, Error>) -> Void) {
        guard let userId = serviceManager.userService.user?.id ?? Auth.auth().currentUser?.uid,
              !userId.isEmpty else {
            completion(.failure(NSError(
                domain: "HomeViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Sign in to copy meals."]
            )))
            return
        }
        let meals = todaysMeals
        guard !meals.isEmpty else {
            completion(.success(0))
            return
        }

        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: targetDate)
        let now = Date()
        let group = DispatchGroup()
        var failure: Error?
        let failureLock = NSLock()

        for meal in meals {
            group.enter()
            var copy = meal
            copy.id = MealPlanningIDs.make(prefix: "meal")
            let time = calendar.dateComponents([.hour, .minute, .second], from: meal.createdAt)
            var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
            components.hour = time.hour
            components.minute = time.minute
            components.second = time.second
            let preservedTimestamp = calendar.date(from: components) ?? targetDay
            copy.createdAt = preservedTimestamp
            copy.updatedAt = now

            MealService.sharedInstance.saveMeal(copy, for: targetDay, userId: userId) { result in
                if case .failure(let error) = result {
                    failureLock.lock()
                    if failure == nil { failure = error }
                    failureLock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            if let failure {
                completion(.failure(failure))
            } else {
                if let self, calendar.isDate(targetDay, inSameDayAs: self.selectedDate) {
                    self.load()
                }
                completion(.success(meals.count))
            }
        }
    }

    func deleteAllTodaysMeals(completion: @escaping (Result<Int, Error>) -> Void) {
        guard let userId = serviceManager.userService.user?.id ?? Auth.auth().currentUser?.uid,
              !userId.isEmpty else {
            completion(.failure(NSError(
                domain: "HomeViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Sign in to delete meals."]
            )))
            return
        }
        let meals = todaysMeals
        guard !meals.isEmpty else {
            completion(.success(0))
            return
        }

        let group = DispatchGroup()
        var failure: Error?
        let failureLock = NSLock()

        for meal in meals {
            group.enter()
            MealService.sharedInstance.deleteMeal(meal, for: meal.createdAt, userId: userId) { result in
                if case .failure(let error) = result {
                    failureLock.lock()
                    if failure == nil { failure = error }
                    failureLock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            if let failure {
                completion(.failure(failure))
            } else {
                self?.load()
                completion(.success(meals.count))
            }
        }
    }

    func loadRecentLabelScans(completion: (() -> Void)? = nil) {
        let candidateUserIDs = scanHistoryUserIDs()
        guard !candidateUserIDs.isEmpty else {
            recentLabelScans = []
            scanHistoryError = NutritionCoreError.missingUserId.localizedDescription
            completion?()
            return
        }

        isLoadingScans = true
        scanHistoryError = nil

        let group = DispatchGroup()
        var scansByID: [String: MacraScannedLabel] = [:]
        var errors: [String] = []
        let lock = NSLock()

        for candidateUserID in candidateUserIDs {
            group.enter()
            print("[Macra][LabelScanHistory] Fetching users/\(candidateUserID)/labelScans")
            Firestore.firestore()
                .collection(NutritionCoreConfiguration.usersCollection)
                .document(candidateUserID)
                .collection(NutritionCoreConfiguration.labelScansCollection)
                .getDocuments { snapshot, error in
                    lock.lock()
                    if let error {
                        errors.append(error.localizedDescription)
                    } else {
                        let documents = snapshot?.documents ?? []
                        print("[Macra][LabelScanHistory] Found \(documents.count) scans for user \(candidateUserID)")
                        for document in documents {
                            scansByID[document.documentID] = MacraScannedLabel(id: document.documentID, data: document.data())
                        }
                    }
                    lock.unlock()
                    group.leave()
                }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else {
                completion?()
                return
            }

            self.isLoadingScans = false
            self.recentLabelScans = scansByID.values
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(60)
                .map { $0 }
            self.scanHistoryError = self.recentLabelScans.isEmpty ? errors.first : nil
            print("[Macra][LabelScanHistory] Returning \(self.recentLabelScans.count) parsed scans")
            completion?()
        }
    }

    private func scanHistoryUserIDs() -> [String] {
        var seen = Set<String>()
        return [
            serviceManager.userService.user?.id,
            UserService.sharedInstance.user?.id,
            Auth.auth().currentUser?.uid
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
    }

    private func loadPinnedLabelScans(from userIDs: [String], index: Int, completion: @escaping ([MacraScannedLabel]) -> Void) {
        guard index < userIDs.count else {
            completion([])
            return
        }

        let userId = userIDs[index]
        MacraPinnedScanService.sharedInstance.loadPinnedLabelScans(userId: userId) { [weak self] result in
            switch result {
            case .success(let scans) where !scans.isEmpty:
                print("[Macra][PinnedScans] Loaded \(scans.count) pinned label scans for user \(userId)")
                completion(scans)
            case .success:
                self?.loadPinnedLabelScans(from: userIDs, index: index + 1, completion: completion)
            case .failure(let error):
                print("[Macra][PinnedScans] Pinned label scan lookup failed for user \(userId): \(error.localizedDescription)")
                self?.loadPinnedLabelScans(from: userIDs, index: index + 1, completion: completion)
            }
        }
    }

    private func loadPinnedMeals(from userIDs: [String], index: Int, completion: @escaping ([Meal]) -> Void) {
        guard index < userIDs.count else {
            completion([])
            return
        }

        let userId = userIDs[index]
        MealService.sharedInstance.getPinnedMeals(userId: userId) { [weak self] result in
            switch result {
            case .success(let meals) where !meals.isEmpty:
                print("[Macra][PinnedScans] Loaded \(meals.count) legacy pinned meals for user \(userId)")
                completion(meals)
            case .success:
                self?.loadPinnedMeals(from: userIDs, index: index + 1, completion: completion)
            case .failure(let error):
                print("[Macra][PinnedScans] Legacy pinned meal lookup failed for user \(userId): \(error.localizedDescription)")
                self?.loadPinnedMeals(from: userIDs, index: index + 1, completion: completion)
            }
        }
    }

    private func loadPinnedLegacyFoodSnaps(from userIDs: [String], index: Int, completion: @escaping ([Meal]) -> Void) {
        guard index < userIDs.count else {
            completion([])
            return
        }

        let userId = userIDs[index]
        MacraPinnedScanService.sharedInstance.loadPinnedFoodSnaps(userId: userId) { [weak self] result in
            switch result {
            case .success(let meals) where !meals.isEmpty:
                print("[Macra][PinnedScans] Loaded \(meals.count) pinned food snaps for user \(userId)")
                completion(meals)
            case .success:
                self?.loadPinnedLegacyFoodSnaps(from: userIDs, index: index + 1, completion: completion)
            case .failure(let error):
                print("[Macra][PinnedScans] Pinned food snap lookup failed for user \(userId): \(error.localizedDescription)")
                self?.loadPinnedLegacyFoodSnaps(from: userIDs, index: index + 1, completion: completion)
            }
        }
    }

    private func pinnedMealDocumentID(for meal: Meal) -> String {
        let normalized = meal.name
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")

        return normalized.isEmpty ? meal.id : normalized
    }
}

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject private var appCoordinator: AppCoordinator
    @ObservedObject private var userService = UserService.sharedInstance
    @StateObject private var logFlowViewModel = MacraFoodJournalViewModel()
    @StateObject private var supplementViewModel = NutritionSupplementTrackerViewModel()
    @State private var isLogMenuPresented = false
    @State private var isAddingSupplement = false
    @State private var handledLogMenuRequestID = 0
    @State private var isDatePickerPresented = false
    @State private var isShareSheetPresented = false
    @State private var activeMealDetail: Meal?
    @State private var isCopyDayPickerPresented = false
    @State private var copyTargetDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var isDeleteAllMealsConfirmationPresented = false
    @State private var activeMacroBreakdown: MacraFoodJournalMacroType?
    @State private var isNetCarbInfoPresented = false
    @State private var isFullNutritionPresented = false
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: HomeViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _appCoordinator = ObservedObject(wrappedValue: viewModel.appCoordinator)
    }

    private var selectedTabBinding: Binding<AppCoordinator.NutritionShellTab> {
        Binding(
            get: { viewModel.appCoordinator.nutritionShellTab },
            set: { viewModel.appCoordinator.nutritionShellTab = $0 }
        )
    }

    private var pathBinding: Binding<[AppCoordinator.NutritionShellDestination]> {
        Binding(
            get: { viewModel.appCoordinator.nutritionPath },
            set: { viewModel.appCoordinator.nutritionPath = $0 }
        )
    }

    var body: some View {
        NavigationStack(path: pathBinding) {
            ZStack {
                darkBackground

                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            topBar

                            switch viewModel.appCoordinator.nutritionShellTab {
                            case .journal:
                                journalSurface
                            case .planner:
                                plannerSurface
                            case .scanner:
                                scannerSurface
                            case .supplements:
                                supplementSurface
                            case .more:
                                moreSurface
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                        .frame(width: geometry.size.width, alignment: .topLeading)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppCoordinator.NutritionShellDestination.self) { destination in
                NutritionDestinationView(
                    destination: destination,
                    appCoordinator: viewModel.appCoordinator,
                    serviceManager: viewModel.serviceManager,
                    onClose: {
                        viewModel.appCoordinator.nutritionPath.removeAll()
                        viewModel.appCoordinator.nutritionShellTab = .journal
                        viewModel.load()
                    }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NutritionShellTabBar(
                    selectedTab: selectedTabBinding,
                    coordinator: viewModel.appCoordinator
                )
            }
            .confirmationDialog("Log a meal", isPresented: $isLogMenuPresented, titleVisibility: .visible) {
                Button("Journal note") { presentLogSheet(.mealNotePad) }
                Button("Scan meal") {
                    logFlowViewModel.draftPhotoCaptureSource = .camera
                    presentLogSheet(.scanFood)
                }
                Button("Upload photo") {
                    // Same downstream flow as "Scan meal", but the scan view
                    // detects the .upload source on appear and jumps straight
                    // to the photo library instead of opening the camera.
                    logFlowViewModel.draftPhotoCaptureSource = .upload
                    presentLogSheet(.scanFood)
                }
                Button("Voice entry") { presentLogSheet(.voiceEntry) }
                Button("From history") { presentLogSheet(.fromHistory) }
                Button("Label scan") { presentLogSheet(.labelScan) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose how you want to add this meal.")
            }
            .confirmationDialog(
                deleteAllMealsConfirmationTitle,
                isPresented: $isDeleteAllMealsConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete all meals", role: .destructive) {
                    triggerDeleteAllTodaysMeals()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .sheet(item: $logFlowViewModel.activeSheet, onDismiss: {
                viewModel.load()
            }) { sheet in
                MacraFoodJournalSheetContentView(viewModel: logFlowViewModel, sheet: sheet)
            }
            .sheet(isPresented: $isAddingSupplement) {
                NutritionSupplementEditorView { supplement in
                    supplementViewModel.saveToLibrary(supplement)
                }
            }
            .sheet(isPresented: $isDatePickerPresented) {
                MacraDayPickerSheet(
                    selectedDate: Binding(
                        get: { viewModel.selectedDate },
                        set: { viewModel.setSelectedDate($0) }
                    ),
                    onDone: { isDatePickerPresented = false }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isCopyDayPickerPresented) {
                MacraDayPickerSheet(
                    selectedDate: $copyTargetDate,
                    confirmTitle: "Copy meals",
                    onDone: {
                        isCopyDayPickerPresented = false
                        triggerCopyDay(to: copyTargetDate)
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isShareSheetPresented) {
                MacraShareComposerSheet(
                    date: viewModel.selectedDate,
                    meals: viewModel.todaysMeals.map(MacraFoodJournalMeal.init(meal:)),
                    macroTarget: (viewModel.macroTarget ?? userService.currentMacroTarget).map {
                        MacraFoodJournalMacroTarget(
                            calories: $0.calories,
                            protein: $0.protein,
                            carbs: $0.carbs,
                            fat: $0.fat
                        )
                    },
                    onClose: { isShareSheetPresented = false }
                )
            }
            .sheet(item: $activeMealDetail) { meal in
                MealLogDetailView(
                    meal: meal,
                    onUpdated: { updatedMeal in
                        if Calendar.current.isDate(updatedMeal.createdAt, inSameDayAs: viewModel.selectedDate) {
                            viewModel.load()
                        } else {
                            viewModel.setSelectedDate(updatedMeal.createdAt)
                        }
                    },
                    onDeleted: { viewModel.load() }
                )
            }
            .sheet(item: $activeMacroBreakdown) { macroType in
                MacraFoodJournalMacroBreakdownView(
                    meals: viewModel.todaysMealsAsFoodJournal,
                    supplements: viewModel.loggedSupplements,
                    macroType: macroType,
                    selectedDate: viewModel.selectedDate,
                    macroTarget: (viewModel.macroTarget ?? userService.currentMacroTarget).map {
                        MacraFoodJournalMacroTarget(
                            calories: $0.calories,
                            protein: $0.protein,
                            carbs: $0.carbs,
                            fat: $0.fat
                        )
                    }
                )
            }
            .sheet(isPresented: $isNetCarbInfoPresented) {
                MacraFoodJournalNetCarbInfoView(
                    meals: viewModel.todaysMealsAsFoodJournal,
                    selectedDate: viewModel.selectedDate
                )
            }
            .sheet(isPresented: $isFullNutritionPresented) {
                MacraFullNutritionSheet(viewModel: viewModel)
            }
            .onAppear {
                configureLogFlow()
                viewModel.load()
                supplementViewModel.setSelectedDate(viewModel.selectedDate)
                supplementViewModel.load()
                presentPendingLogMenuIfNeeded()
            }
            .onChange(of: viewModel.appCoordinator.logMenuRequestID) { _ in
                presentPendingLogMenuIfNeeded()
            }
            .onChange(of: viewModel.appCoordinator.nutritionShellTab) { tab in
                switch tab {
                case .supplements:
                    supplementViewModel.setSelectedDate(viewModel.selectedDate)
                    supplementViewModel.load()
                case .journal, .scanner, .planner:
                    viewModel.load()
                default:
                    break
                }
            }
            .onChange(of: viewModel.selectedDate) { newDate in
                supplementViewModel.setSelectedDate(newDate)
            }
            .onChange(of: userService.user?.id) { _ in
                viewModel.load()
                supplementViewModel.setSelectedDate(viewModel.selectedDate)
                supplementViewModel.load()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                let today = Calendar.current.startOfDay(for: Date())
                if !Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: today) {
                    print("[Macra][Nora][SCENE-FOREGROUND-AUTOROLL] selectedDate=\(viewModel.selectedDate) → \(today)")
                    viewModel.setSelectedDate(today)
                    supplementViewModel.setSelectedDate(today)
                }
            }
        }
    }

    private var darkBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.secondaryCharcoal,
                    Color.primaryBlue.opacity(0.85),
                    Color.primaryBlue.opacity(0.55),
                    Color.secondaryPink.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Color.secondaryCharcoal.opacity(0.35)
                .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Button {
                        isDatePickerPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(dayLabel)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Image(systemName: "calendar")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.primaryGreen)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open calendar")
                }

                Spacer()

                if !viewModel.todaysMeals.isEmpty {
                    Button {
                        isShareSheetPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(hex: "0B0C10"))
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color.primaryGreen)
                                    .shadow(color: Color.primaryGreen.opacity(0.4), radius: 10, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share your day")
                }

                Button {
                    viewModel.appCoordinator.showSettingsModal()
                } label: {
                    ProfileAvatarView(
                        imageURL: userService.user?.profileImageURL ?? "",
                        fallbackText: userService.user?.email ?? ""
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open profile settings")
            }

            dayNavigator
        }
    }

    private var dayNavigator: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.navigateToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primaryGreen)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.secondaryCharcoal.opacity(0.6))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primaryGreen.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canNavigateToPreviousDay)
            .opacity(viewModel.canNavigateToPreviousDay ? 1.0 : 0.4)
            .accessibilityLabel("Previous day")

            Button {
                isDatePickerPresented = true
            } label: {
                Text(dayLabel == "Today" ? dateLine : dayLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open calendar")

            Button {
                viewModel.navigateToNextDay()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primaryGreen)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.secondaryCharcoal.opacity(0.6))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primaryGreen.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canNavigateToNextDay)
            .opacity(viewModel.canNavigateToNextDay ? 1.0 : 0.4)
            .accessibilityLabel("Next day")
        }
    }

    private var canCopyDay: Bool {
        !viewModel.todaysMeals.isEmpty && !Calendar.current.isDateInToday(viewModel.selectedDate)
    }

    private func triggerCopyDay(to targetDate: Date) {
        let sourceDate = viewModel.selectedDate
        let sourceLabel = copyDayLabel(for: sourceDate)
        let targetLabel = copyDayLabel(for: targetDate)
        viewModel.copyTodaysMealsToDate(targetDate) { result in
            switch result {
            case .success(let count):
                guard count > 0 else { return }
                let mealNoun = count == 1 ? "meal" : "meals"
                viewModel.appCoordinator.showToast(viewModel: ToastViewModel(
                    message: "Copied \(count) \(mealNoun) from \(sourceLabel) to \(targetLabel).",
                    backgroundColor: .secondaryCharcoal,
                    textColor: .secondaryWhite
                ))
            case .failure(let error):
                viewModel.appCoordinator.showToast(viewModel: ToastViewModel(
                    message: "Couldn't copy meals: \(error.localizedDescription)",
                    backgroundColor: .secondaryCharcoal,
                    textColor: .secondaryWhite
                ))
            }
        }
    }

    private var deleteAllMealsConfirmationTitle: String {
        let count = viewModel.todaysMeals.count
        let noun = count == 1 ? "meal" : "meals"
        return "Delete \(count) \(noun) from \(copyDayLabel(for: viewModel.selectedDate))?"
    }

    private func triggerDeleteAllTodaysMeals() {
        let dayLabel = copyDayLabel(for: viewModel.selectedDate)
        viewModel.deleteAllTodaysMeals { result in
            switch result {
            case .success(let count):
                guard count > 0 else { return }
                let mealNoun = count == 1 ? "meal" : "meals"
                viewModel.appCoordinator.showToast(viewModel: ToastViewModel(
                    message: "Deleted \(count) \(mealNoun) from \(dayLabel).",
                    backgroundColor: .secondaryCharcoal,
                    textColor: .secondaryWhite
                ))
            case .failure(let error):
                viewModel.appCoordinator.showToast(viewModel: ToastViewModel(
                    message: "Couldn't delete meals: \(error.localizedDescription)",
                    backgroundColor: .secondaryCharcoal,
                    textColor: .secondaryWhite
                ))
            }
        }
    }

    private func copyDayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private var journalSurface: some View {
        let effectiveTarget = viewModel.macroTarget ?? userService.currentMacroTarget
        return VStack(alignment: .leading, spacing: 20) {
            CalorieMacroHero(
                caloriesConsumed: viewModel.totalCalories,
                caloriesTarget: effectiveTarget?.calories,
                proteinConsumed: viewModel.totalProtein,
                proteinTarget: effectiveTarget?.protein,
                carbsConsumed: viewModel.totalCarbs,
                carbsTarget: effectiveTarget?.carbs,
                fatConsumed: viewModel.totalFat,
                fatTarget: effectiveTarget?.fat,
                hasCompletedOnboarding: userService.user?.hasCompletedMacraOnboarding == true,
                onTapMacro: { macro in
                    activeMacroBreakdown = macro
                }
            )

            if viewModel.hasNetCarbAdjustment {
                Button {
                    isNetCarbInfoPresented = true
                } label: {
                    HomeNetCarbChip(netCarbs: viewModel.totalNetCarbs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Net carbs explanation")
            }

            if viewModel.hasFullNutritionDetail {
                Button {
                    isFullNutritionPresented = true
                } label: {
                    HomeFullNutritionCard()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open full nutrition table")
            }

            MacraFoodJournalStreakStrip(stats: viewModel.loggingStats)

            Button {
                isLogMenuPresented = true
            } label: {
                LogMealCTA()
            }
            .buttonStyle(.plain)

            if canCopyDay {
                Button {
                    copyTargetDate = Calendar.current.startOfDay(for: Date())
                    isCopyDayPickerPresented = true
                } label: {
                    CopyDayCTA(mealCount: viewModel.todaysMeals.count)
                }
                .buttonStyle(.plain)
            }

            if viewModel.todaysMeals.isEmpty {
                EmptyMealsState(dayLabel: dayLabel)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("\(mealsSectionDayLabel) meals")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(viewModel.todaysMeals.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                        Button {
                            isDeleteAllMealsConfirmationPresented = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(hex: "FF6B6B"))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color(hex: "FF6B6B").opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete all meals for this day")
                    }

                    MealTimelineList(groups: mealHourGroups) { meal in
                        activeMealDetail = meal
                    }
                }
            }

            if !viewModel.todaysMeals.isEmpty {
                HomeDailyInsightCard(
                    insight: viewModel.dailyInsight,
                    isGenerating: viewModel.isGeneratingInsight,
                    errorMessage: viewModel.dailyInsightError,
                    onGenerate: { viewModel.generateDailyInsight() }
                )
            }

            AskNoraSection(
                meals: viewModel.todaysMeals,
                target: effectiveTarget,
                threadDate: viewModel.selectedDate,
                userId: viewModel.serviceManager.userService.user?.id ?? Auth.auth().currentUser?.uid,
                isDayContextLoading: viewModel.isLoading
            )
            // Pin section identity to the selected day so SwiftUI tears down
            // the @State (messages, composer text, isAsking) on every day
            // switch — prevents bubbles from one day rendering under another
            // day's "TODAY/Yesterday" pill while the async reload is in flight.
            .id(viewModel.selectedDate.macraFoodJournalDayKey)
        }
    }

    private func configureLogFlow() {
        logFlowViewModel.shouldReturnHomeAfterMealSave = true
        logFlowViewModel.onMealSaved = { meal in
            saveMealToHomeLog(meal)
        }
    }

    private func presentLogSheet(_ sheet: MacraFoodJournalSheet) {
        configureLogFlow()
        logFlowViewModel.selectedDate = viewModel.selectedDate
        if sheet == .fromHistory || sheet == .photoGrid {
            logFlowViewModel.loadMealHistory(force: true)
        }
        if sheet == .fromHistory || sheet == .labelHistory {
            logFlowViewModel.loadLabelScanHistory(force: true)
        }
        logFlowViewModel.activeSheet = sheet
    }

    private func presentPendingLogMenuIfNeeded() {
        let requestID = viewModel.appCoordinator.logMenuRequestID
        guard requestID != handledLogMenuRequestID else { return }
        handledLogMenuRequestID = requestID
        isLogMenuPresented = true
    }

    private func saveMealToHomeLog(_ foodJournalMeal: MacraFoodJournalMeal) {
        let detailed = foodJournalMeal.ingredients.map {
            MealIngredientDetail(
                id: $0.id,
                name: $0.name,
                quantity: $0.quantity,
                calories: $0.calories,
                protein: $0.protein,
                carbs: $0.carbs,
                fat: $0.fat,
                fiber: $0.fiber,
                sugarAlcohols: $0.sugarAlcohols
            )
        }
        let meal = Meal(
            id: foodJournalMeal.id,
            name: foodJournalMeal.name,
            categories: [.unknown],
            ingredients: foodJournalMeal.ingredients.map(\.name),
            detailedIngredients: detailed.isEmpty ? nil : detailed,
            caption: foodJournalMeal.caption,
            calories: foodJournalMeal.calories,
            protein: foodJournalMeal.protein,
            fat: foodJournalMeal.fat,
            carbs: foodJournalMeal.carbs,
            fiber: foodJournalMeal.fiber,
            sugarAlcohols: foodJournalMeal.sugarAlcohols,
            image: foodJournalMeal.imageURL ?? "",
            entryMethod: foodJournalMeal.entryMethod.mealEntryMethod,
            photoCaptureSource: foodJournalMeal.photoCaptureSource,
            createdAt: foodJournalMeal.createdAt,
            updatedAt: foodJournalMeal.updatedAt
        )

        MealService.sharedInstance.saveMeal(meal, for: foodJournalMeal.createdAt, userId: viewModel.serviceManager.userService.user?.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let saved):
                    MacraHealthKitService.shared.saveMeal(saved, date: saved.createdAt) { hkResult in
                        guard case .failure(let error) = hkResult,
                              (error as? MacraHealthKitService.HealthKitWriteError) == .noTypesAuthorized,
                              !MacraHealthKitService.shared.hasWarnedNoTypesAuthorized else { return }
                        MacraHealthKitService.shared.hasWarnedNoTypesAuthorized = true
                        DispatchQueue.main.async {
                            viewModel.appCoordinator.showToast(
                                viewModel: ToastViewModel(
                                    message: "Open Health → Sources → Macra to enable meal sync.",
                                    backgroundColor: .secondaryCharcoal,
                                    textColor: .secondaryWhite
                                )
                            )
                        }
                    }
                    viewModel.load()
                case .failure(let error):
                    viewModel.appCoordinator.showToast(
                        viewModel: ToastViewModel(
                            message: "Could not save meal: \(error.localizedDescription)",
                            backgroundColor: .secondaryCharcoal,
                            textColor: .secondaryWhite
                        )
                    )
                }
            }
        }
    }

    private var plannerSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let userId = viewModel.serviceManager.userService.user?.id ?? Auth.auth().currentUser?.uid {
                MacraPlanHubSurface(userId: userId, appCoordinator: viewModel.appCoordinator)
            } else {
                NutritionSectionCard(
                    title: "Meal planning",
                    subtitle: "Sign in to create reusable plans and log planned meals back to today.",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    accent: Color.primaryGreen
                ) {
                    EmptyView()
                }
            }
        }
    }

    private var scannerSurface: some View {
        VStack(alignment: .leading, spacing: 18) {
            scannerActionRow
            pinnedScansSection
            labelScanHistorySection

            if mealScanItems.isEmpty {
                scannerEmptyState
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("RECENT MEAL SCANS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(Color.primaryGreen)
                    Spacer()
                    Text("\(mealScanItems.count)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.horizontal, 4)

                VStack(spacing: 14) {
                    ForEach(mealScanItems.prefix(40)) { meal in
                        MealScanCard(
                            meal: meal,
                            isPinned: viewModel.isFoodSnapPinned(meal),
                            onTogglePin: { viewModel.togglePinFoodSnap(meal) }
                        ) {
                            // future: open meal detail
                        }
                    }
                }
            }
        }
    }

    private var pinnedScansSection: some View {
        let hasPins = !viewModel.pinnedLabelScans.isEmpty || !viewModel.pinnedFoodSnaps.isEmpty
        let totalPins = viewModel.pinnedLabelScans.count + viewModel.pinnedFoodSnaps.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("PINNED SCANS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                }
                .foregroundColor(Color.primaryGreen)

                Spacer()

                if hasPins {
                    Text("\(totalPins)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 4)

            if hasPins {
                VStack(spacing: 10) {
                    ForEach(viewModel.pinnedFoodSnaps) { meal in
                        PinnedFoodSnapQuickAddRow(
                            meal: meal,
                            onQuickLog: { viewModel.quickLogPinnedFoodSnap(meal) },
                            onUnpin: { viewModel.togglePinFoodSnap(meal) }
                        )
                    }
                    ForEach(viewModel.pinnedLabelScans) { scan in
                        PinnedLabelQuickAddRow(
                            scan: scan,
                            onQuickLog: { viewModel.quickLogPinnedLabel(scan) },
                            onUnpin: { viewModel.togglePinLabel(scan) }
                        )
                    }
                }
            } else {
                PinnedScansEmptyCard()
            }
        }
    }

    private var scannerActionRow: some View {
        HStack(spacing: 12) {
            scannerActionPill(
                title: "Snap food",
                systemImage: "camera.viewfinder",
                accent: Color(hex: "3B82F6")
            ) {
                // Route through the home-owned log flow (`logFlowViewModel`)
                // so we don't push the legacy `MacraFoodJournalRootView` /
                // `MacraFoodJournalDayView` underneath the scanner. Mirrors
                // how "Scan label" works.
                presentLogSheet(.scanFood)
            }

            scannerActionPill(
                title: "Scan label",
                systemImage: "barcode.viewfinder",
                accent: Color(hex: "06B6D4")
            ) {
                presentLogSheet(.labelScan)
            }
        }
    }

    private func scannerActionPill(title: String, systemImage: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accent.opacity(0.38), lineWidth: 1)
            )
            .shadow(color: accent.opacity(0.22), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var scannerEmptyState: some View {
        VStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primaryGreen.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(Color.primaryGreen)
            }

            Text("No scans yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Snap a meal and it'll show up here with its photo and macros.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var labelScanHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("LABEL SCAN HISTORY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "8B5CF6"))

                Spacer()

                Button {
                    viewModel.loadRecentLabelScans()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.66))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh label scans")
            }
            .padding(.horizontal, 4)

            if viewModel.isLoadingScans {
                ProgressView("Loading label scans...")
                    .tint(Color.primaryGreen)
                    .foregroundColor(.white.opacity(0.68))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(scannerPanelBackground)
            } else if let scanHistoryError = viewModel.scanHistoryError {
                ScannerInfoCard(
                    title: "Label history unavailable",
                    message: scanHistoryError,
                    systemImage: "exclamationmark.triangle.fill",
                    accent: .orange
                )
            } else if viewModel.recentLabelScans.isEmpty {
                ScannerInfoCard(
                    title: "No scanned labels",
                    message: "QuickLifts reads this from users/{userId}/labelScans. Macra did not find label scans for the current account.",
                    systemImage: "barcode.viewfinder",
                    accent: Color(hex: "8B5CF6")
                )
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.recentLabelScans) { scan in
                        QuickLiftsLabelScanCard(
                            scan: scan,
                            isPinned: viewModel.isLabelPinned(scan.id),
                            onTogglePin: { viewModel.togglePinLabel(scan) }
                        ) {
                            logFlowViewModel.presentLabelDetail(scan)
                        }
                    }
                }
            }
        }
    }

    private var mealScanItems: [Meal] {
        viewModel.recentMeals
            .filter { !$0.image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.entryMethod == .photo }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var scannerPanelBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private var supplementSurface: some View {
        NutritionSupplementTrackerContentView(
            viewModel: supplementViewModel,
            showsHeader: false,
            onAddSupplement: { isAddingSupplement = true }
        )
    }

    private var moreSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileSummaryCard(
                user: viewModel.serviceManager.userService.user,
                isSubscribed: PurchaseService.sharedInstance.isSubscribed
            ) {
                viewModel.appCoordinator.showSettingsModal()
            }

            NutritionSectionCard(
                title: "More",
                subtitle: "Macro targets, account, and settings.",
                systemImage: "ellipsis.circle",
                accent: Color.primaryGreen
            ) {
                VStack(spacing: 6) {
                    Button {
                        viewModel.appCoordinator.showNutritionDestination(.macroTargets)
                    } label: {
                        MoreRow(title: "Macro targets", subtitle: "View and edit your daily calorie and macro targets.", systemImage: "target")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.white.opacity(0.08))

                    Button {
                        viewModel.appCoordinator.showNutritionDestination(.insights)
                    } label: {
                        MoreRow(title: "Nutrition insights", subtitle: "Daily AI coaching based on your entries.", systemImage: "sparkles")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.white.opacity(0.08))

                    Button {
                        viewModel.appCoordinator.showNutritionDestination(.mealHistory)
                    } label: {
                        MoreRow(title: "Meal history", subtitle: "Browse your saved meal photos.", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.white.opacity(0.08))

                    MacraHealthKitToggleRow()

                    Divider().background(Color.white.opacity(0.08))

                    Button {
                        viewModel.appCoordinator.showSettingsModal()
                    } label: {
                        MoreRow(title: "Settings", subtitle: "Account, subscription, and preferences.", systemImage: "gearshape")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: viewModel.selectedDate)
    }

    private var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(viewModel.selectedDate) { return "Today" }
        if calendar.isDateInYesterday(viewModel.selectedDate) { return "Yesterday" }
        if calendar.isDateInTomorrow(viewModel.selectedDate) { return "Tomorrow" }
        let formatter = DateFormatter()
        if calendar.isDate(viewModel.selectedDate, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
            return formatter.string(from: viewModel.selectedDate)
        }
        formatter.dateFormat = "MMM d"
        return formatter.string(from: viewModel.selectedDate)
    }

    private var mealsSectionDayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(viewModel.selectedDate) { return "Today's" }
        if calendar.isDateInYesterday(viewModel.selectedDate) { return "Yesterday's" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: viewModel.selectedDate)
    }

    fileprivate var mealHourGroups: [MealHourGroup] {
        let sorted = viewModel.todaysMeals.sorted { $0.createdAt < $1.createdAt }
        let calendar = Calendar.current
        var buckets: [(key: Date, meals: [Meal])] = []
        for meal in sorted {
            let bucket = calendar.date(bySettingHour: calendar.component(.hour, from: meal.createdAt), minute: 0, second: 0, of: meal.createdAt) ?? meal.createdAt
            if let last = buckets.last, calendar.isDate(last.key, equalTo: bucket, toGranularity: .hour) {
                buckets[buckets.count - 1].meals.append(meal)
            } else {
                buckets.append((bucket, [meal]))
            }
        }
        return buckets.map { MealHourGroup(hour: $0.key, meals: $0.meals) }
    }
}

// MARK: - Meal Timeline

fileprivate struct MealHourGroup: Identifiable {
    let hour: Date
    let meals: [Meal]

    var id: TimeInterval { hour.timeIntervalSince1970 }
}

fileprivate struct MealTimelineList: View {
    let groups: [MealHourGroup]
    let onSelect: (Meal) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(groups) { group in
                Section {
                    VStack(spacing: 10) {
                        ForEach(group.meals) { meal in
                            Button {
                                onSelect(meal)
                            } label: {
                                MealRow(meal: meal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 14)
                } header: {
                    MealTimelineHourHeader(hour: group.hour)
                }
            }
        }
    }
}

fileprivate struct MealTimelineHourHeader: View {
    let hour: Date

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.hourFormatter.string(from: hour).uppercased())
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(Color.primaryGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.primaryGreen.opacity(0.14))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primaryGreen.opacity(0.36), lineWidth: 1)
                )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Calorie + Macro Hero

private struct CalorieMacroHero: View {
    let caloriesConsumed: Int
    let caloriesTarget: Int?
    let proteinConsumed: Int
    let proteinTarget: Int?
    let carbsConsumed: Int
    let carbsTarget: Int?
    let fatConsumed: Int
    let fatTarget: Int?
    let hasCompletedOnboarding: Bool
    var onTapMacro: ((MacraFoodJournalMacroType) -> Void)? = nil

    var body: some View {
        VStack(spacing: 18) {
            Button {
                onTapMacro?(.calories)
            } label: {
                CalorieRing(consumed: caloriesConsumed, target: caloriesTarget, hasCompletedOnboarding: hasCompletedOnboarding)
                    .frame(height: 220)
                    .padding(.top, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Calories breakdown by meal")

            HStack(spacing: 14) {
                Button {
                    onTapMacro?(.protein)
                } label: {
                    MacroBar(label: "Protein", current: proteinConsumed, target: proteinTarget, color: Color(hex: "60A5FA"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Protein breakdown by meal")

                Button {
                    onTapMacro?(.carbs)
                } label: {
                    MacroBar(label: "Carbs", current: carbsConsumed, target: carbsTarget, color: Color.primaryGreen)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Carbs breakdown by meal")

                Button {
                    onTapMacro?(.fat)
                } label: {
                    MacroBar(label: "Fat", current: fatConsumed, target: fatTarget, color: Color(hex: "FBBF24"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fat breakdown by meal")
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Tap the ring or any macro for a meal-by-meal breakdown")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct CalorieRing: View {
    let consumed: Int
    let target: Int?
    let hasCompletedOnboarding: Bool

    private var progress: Double {
        guard let target = target, target > 0 else { return 0 }
        return min(Double(consumed) / Double(target), 1.0)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let strokeWidth: CGFloat = 22
            let ringRadius = (size - strokeWidth) / 2

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: strokeWidth)
                    .frame(width: size, height: size)

                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [Color.primaryGreen, Color(hex: "C5EA17")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                        )
                        .frame(width: size, height: size)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: progress)
                } else if target != nil {
                    Circle()
                        .fill(Color.primaryGreen)
                        .frame(width: 16, height: 16)
                        .shadow(color: Color.primaryGreen.opacity(0.8), radius: 10)
                        .offset(y: -ringRadius)
                }

                centerLabel
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        if let target = target {
            if consumed == 0 {
                VStack(spacing: 6) {
                    Text("\(target)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("Daily target")
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            } else {
                VStack(spacing: 6) {
                    Text("\(consumed)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()

                    HStack(spacing: 4) {
                        Text("of \(target) kcal")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.55))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.primaryGreen.opacity(0.85))
                    }

                    remainingPill(target: target)
                        .padding(.top, 2)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text("No targets set")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                Text(hasCompletedOnboarding ? "Set macro targets" : "Finish onboarding")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.primaryGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primaryGreen.opacity(0.14)))
            }
        }
    }

    @ViewBuilder
    private func remainingPill(target: Int) -> some View {
        if consumed < target {
            Text("\(target - consumed) left")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primaryGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primaryGreen.opacity(0.14)))
        } else if consumed > target {
            Text("\(consumed - target) over")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(hex: "F87171"))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: "F87171").opacity(0.18)))
        } else {
            Text("On target")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primaryGreen)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primaryGreen.opacity(0.14)))
        }
    }
}

private struct MacroBar: View {
    let label: String
    let current: Int
    let target: Int?
    let color: Color

    private var progress: Double {
        guard let target = target, target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(current)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                if let target = target {
                    Text("/\(target)g")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .monospacedDigit()
                } else {
                    Text("g")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(4, geo.size.width * progress))
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.28), lineWidth: 1)
        )
    }
}

private extension MacraFoodJournalEntryMethod {
    var mealEntryMethod: MealEntryMethod {
        switch self {
        case .photo:
            return .photo
        case .voice:
            return .voice
        case .text, .history, .label, .quickLog, .manual:
            return .text
        }
    }
}

// MARK: - Plan Surface

private struct MealPlanningHomeSurface: View {
    @StateObject private var viewModel: MealPlanningRootViewModel
    @State private var activeEditor: MealPlanEditorMode?
    @State private var mealSelectionPlan: MealPlan?

    init(userId: String, store: any MealPlanningStore = FirestoreMealPlanningStore()) {
        _viewModel = StateObject(wrappedValue: MealPlanningRootViewModel(userId: userId, store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if viewModel.isLoading {
                ProgressView()
                    .tint(.primaryGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }

            if let statusMessage = viewModel.statusMessage {
                MealPlanningStatusPill(text: statusMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage = viewModel.errorMessage {
                NutritionSectionCard(
                    title: "Plan sync",
                    subtitle: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    accent: .orange
                ) {
                    EmptyView()
                }
            }

            actionRow
            plansList
        }
        .onAppear {
            viewModel.loadInitialData()
        }
        .sheet(item: $activeEditor) { mode in
            MealPlanEditorView(mode: mode) { result in
                handleEditorResult(result)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text("Create reusable meal plans and log planned meals back to your journal.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.primaryGreen)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh meal plans")
            }

            HStack(spacing: 10) {
                MealMetricChip(label: "Plans", value: "\(viewModel.orderedMealPlans.count)", tint: .primaryGreen)
                MealMetricChip(label: "Meals", value: "\(viewModel.totalPlannedMeals)", tint: .primaryBlue)
                MealMetricChip(label: "Active", value: "\(viewModel.activePlanCount)", tint: .lightBlue)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var actionRow: some View {
        VStack(spacing: 10) {
            MealPlanningPrimaryButton(title: "New plan", systemImage: "plus.circle.fill") {
                activeEditor = .create
            }

            MealPlanningSecondaryButton(title: "Create plan from today", systemImage: "calendar.badge.plus") {
                activeEditor = .createFromDate(Date())
            }
        }
    }

    @ViewBuilder
    private var plansList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your plans")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(viewModel.orderedMealPlans.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            if viewModel.orderedMealPlans.isEmpty {
                MealPlanningEmptyState(
                    title: "No meal plans yet",
                    message: "Create your first plan here, then add meals from your history.",
                    systemImage: "fork.knife",
                    actionTitle: "Create first plan"
                ) {
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
                            MealPlanSummaryCard(plan: plan)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func handleEditorResult(_ result: MealPlanEditorResult) {
        switch result {
        case .createEmpty(let name):
            viewModel.createPlan(name: name) { _ in }
        case .createFromDate(let date, let name):
            viewModel.createPlanFromDate(date, name: name) { _ in }
        case .rename(let planId, let name):
            viewModel.renamePlan(planId: planId, newName: name) { _ in }
        }
        activeEditor = nil
    }
}

// MARK: - Plan Hub (AI-generated suggested plan + change-plan modal)

@MainActor
final class MacraPlanHubViewModel: ObservableObject {
    @Published var macroTarget: MacroRecommendation?
    @Published var suggestedPlan: MacraSuggestedMealPlan?
    @Published var planLabel: String = "Starter Nora Plan"
    @Published var isLoading: Bool = false
    @Published var isGenerating: Bool = false
    @Published var isAdaptingTargets: Bool = false
    @Published var errorMessage: String?

    let userId: String
    private var cancellables = Set<AnyCancellable>()

    init(userId: String) {
        self.userId = userId
        // Reload Today's fuel whenever the playbook re-mirrors the active
        // plan. Without this, switching plans wouldn't take effect on this
        // screen until the user manually backed out and re-entered the tab.
        NotificationCenter.default.publisher(for: NutritionCoreNotification.activePlanDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                print("[Macra][PlanHub.observer] activePlanDidChange received — reloading")
                self?.load()
            }
            .store(in: &cancellables)
    }

    struct PlanTotals {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
    }

    var planTotals: PlanTotals? {
        guard let plan = suggestedPlan else { return nil }
        let cal = plan.meals.reduce(0) { $0 + $1.totalCalories }
        let p = plan.meals.reduce(0) { $0 + $1.totalProtein }
        let c = plan.meals.reduce(0) { $0 + $1.totalCarbs }
        let f = plan.meals.reduce(0) { $0 + $1.totalFat }
        return PlanTotals(calories: cal, protein: p, carbs: c, fat: f)
    }

    /// True when the user's saved daily macro target diverges from the
    /// active plan's totals beyond a small tolerance. Used to surface the
    /// "macros don't match this plan" banner on Today's fuel.
    var hasTargetMismatch: Bool {
        guard let totals = planTotals, let target = macroTarget else { return false }
        let calorieTolerance = 50
        let macroTolerance = 5
        return abs(totals.calories - target.calories) > calorieTolerance
            || abs(totals.protein - target.protein) > macroTolerance
            || abs(totals.carbs - target.carbs) > macroTolerance
            || abs(totals.fat - target.fat) > macroTolerance
    }

    /// Quick-fix: overwrite the user's daily macro target with whatever the
    /// active plan totals are. Saves a fresh `MacroRecommendation` (dayOfWeek
    /// nil = all-days) so the banner clears on next load.
    func adaptTargetsToPlan(completion: (() -> Void)? = nil) {
        guard let totals = planTotals else { completion?(); return }
        guard !userId.isEmpty else { completion?(); return }
        isAdaptingTargets = true

        let recommendation = MacroRecommendation(
            userId: userId,
            calories: totals.calories,
            protein: totals.protein,
            carbs: totals.carbs,
            fat: totals.fat,
            dayOfWeek: nil
        )

        MacroRecommendationService.sharedInstance.saveMacroRecommendation(recommendation) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAdaptingTargets = false
                switch result {
                case .success(let saved):
                    self.macroTarget = saved
                    UserService.sharedInstance.currentMacroTarget = saved
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                completion?()
            }
        }
    }

    func load() {
        isLoading = true
        errorMessage = nil
        let group = DispatchGroup()

        group.enter()
        MacroRecommendationService.sharedInstance.getCurrentMacroRecommendation(for: userId) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let rec) = result, let rec = rec {
                    self?.macroTarget = rec
                    UserService.sharedInstance.currentMacroTarget = rec
                }
                group.leave()
            }
        }

        group.enter()
        fetchCachedPlan { [weak self] plan, label in
            DispatchQueue.main.async {
                self?.suggestedPlan = plan
                self?.planLabel = label
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
            self?.auditAndMatchImages()
        }
    }

    /// Audit pass run on every Plan tab load. Re-evaluates every meal and every item:
    ///  - Existing imageURLs that no longer pass the (stricter) match threshold get cleared.
    ///  - Meals/items still missing an image get matched against the user's last 90 days
    ///    of logged meals.
    /// Updates `suggestedPlan` incrementally so users see images appear (or disappear) in
    /// real time, then persists the final state to Firestore.
    func auditAndMatchImages() {
        guard !userId.isEmpty, suggestedPlan != nil else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        print("[Macra][PlanHub.images] Auditing meal/item images against last 90 days of logs")
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("mealLogs")
            .whereField("createdAt", isGreaterThanOrEqualTo: cutoff.timeIntervalSince1970)
            .order(by: "createdAt", descending: true)
            .getDocuments { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    print("[Macra][PlanHub.images] mealLogs fetch failed: \(error.localizedDescription)")
                    return
                }
                let logged = snapshot?.documents.compactMap { doc -> Meal? in
                    let m = Meal(id: doc.documentID, dictionary: doc.data())
                    return m.image.isEmpty ? nil : m
                } ?? []
                print("[Macra][PlanHub.images] \(logged.count) candidate logs with images")
                self.runAudit(logged: logged)
            }
    }

    private func runAudit(logged: [Meal]) {
        Task { @MainActor [weak self] in
            guard let self, var plan = self.suggestedPlan else { return }
            // Pre-tokenize every logged meal once (name + ingredients + detailedIngredients).
            let indexed: [(meal: Meal, tokens: Set<String>)] = logged.map { log in
                var text = log.name + " " + log.ingredients.joined(separator: " ")
                if let detailed = log.detailedIngredients {
                    text += " " + detailed.map(\.name).joined(separator: " ")
                }
                return (log, Self.tokenize(text))
            }
            var changed = false

            for mealIndex in plan.meals.indices {
                // Meal-level audit: aggregate all item names as the suggested signal.
                let mealTokens = Self.tokenize(plan.meals[mealIndex].items.map(\.name).joined(separator: " "))
                let mealMatch = Self.findMealMatch(tokens: mealTokens, in: indexed)
                let newMealImage = mealMatch?.image
                if (plan.meals[mealIndex].imageURL ?? "") != (newMealImage ?? "") {
                    plan.meals[mealIndex].imageURL = newMealImage
                    changed = true
                    if let m = mealMatch {
                        print("[Macra][PlanHub.images] ✓ Meal \(mealIndex + 1) → '\(m.name)'")
                    } else {
                        print("[Macra][PlanHub.images] ✗ Meal \(mealIndex + 1) cleared (no strong match)")
                    }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.suggestedPlan = plan
                    }
                    try? await Task.sleep(nanoseconds: 140_000_000)
                }

                // Item-level audit: each item gets its own matcher with strict rules.
                for itemIndex in plan.meals[mealIndex].items.indices {
                    let itemName = plan.meals[mealIndex].items[itemIndex].name
                    let itemTokens = Self.tokenize(itemName)
                    let itemMatch = Self.findItemMatch(tokens: itemTokens, in: indexed)
                    let newItemImage = itemMatch?.image
                    if (plan.meals[mealIndex].items[itemIndex].imageURL ?? "") != (newItemImage ?? "") {
                        plan.meals[mealIndex].items[itemIndex].imageURL = newItemImage
                        changed = true
                        if let m = itemMatch {
                            print("[Macra][PlanHub.images] ✓ Item '\(itemName)' → '\(m.name)'")
                        } else {
                            print("[Macra][PlanHub.images] ✗ Item '\(itemName)' cleared")
                        }
                        withAnimation(.easeInOut(duration: 0.20)) {
                            self.suggestedPlan = plan
                        }
                        try? await Task.sleep(nanoseconds: 80_000_000)
                    }
                }
            }

            if changed {
                self.persistPlanImages(plan)
            } else {
                print("[Macra][PlanHub.images] Audit complete — no changes")
            }
        }
    }

    /// Meal-level match: requires ≥2 overlapping tokens AND ≥40% coverage of the meal's
    /// distinct tokens. Highest absolute overlap wins. Filters out the "single common
    /// token" case where one logged photo matches every meal because they all share "rice".
    private static func findMealMatch(tokens: Set<String>, in indexed: [(meal: Meal, tokens: Set<String>)]) -> Meal? {
        guard tokens.count >= 2 else { return nil }
        let coverageThreshold = 0.4
        var best: (Meal, Int)?
        for entry in indexed {
            let overlap = tokens.intersection(entry.tokens).count
            let coverage = Double(overlap) / Double(tokens.count)
            if overlap >= 2, coverage >= coverageThreshold, overlap > (best?.1 ?? 0) {
                best = (entry.meal, overlap)
            }
        }
        return best?.0
    }

    /// Item-level match: 1-token items (e.g. "almonds") need that 1 token in the log;
    /// multi-token items (e.g. "egg whites", "chicken breast") need ALL their tokens in
    /// the log. Conservative on purpose — better to leave an item unillustrated than to
    /// pin the wrong photo on it.
    private static func findItemMatch(tokens: Set<String>, in indexed: [(meal: Meal, tokens: Set<String>)]) -> Meal? {
        guard !tokens.isEmpty else { return nil }
        let needed = tokens.count
        var best: (Meal, Int)?
        for entry in indexed {
            let overlap = tokens.intersection(entry.tokens).count
            if overlap >= needed, overlap > (best?.1 ?? 0) {
                best = (entry.meal, overlap)
            }
        }
        return best?.0
    }

    private static let matchStopwords: Set<String> = [
        "a", "an", "the", "of", "with", "and", "or", "to", "in", "on",
        "cup", "cups", "oz", "ounce", "ounces", "g", "gram", "grams",
        "tbsp", "tsp", "lb", "lbs", "ml", "l", "kg",
        "large", "small", "medium", "extra", "whole",
        "plain", "raw", "cooked", "fresh", "dried"
    ]

    private static func tokenize(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let cleaned = lowered.map { ch -> Character in
            (ch.isLetter || ch.isNumber || ch == " ") ? ch : " "
        }
        return Set(
            String(cleaned)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 1 && !matchStopwords.contains($0) && Int($0) == nil }
                .map { stem($0) }
        )
    }

    /// Naive plural stripper so "almonds"↔"almond", "whites"↔"white", "cakes"↔"cake"
    /// match. Good enough for the food-vocabulary domain; stays consistent on both sides
    /// of the comparison even when it produces non-words ("asparagus" → "asparagu").
    private static func stem(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }

    private func persistPlanImages(_ plan: MacraSuggestedMealPlan) {
        guard !userId.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(plan)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let mealsArray = dict["meals"] as? [[String: Any]] else { return }
            Firestore.firestore()
                .collection("users")
                .document(userId)
                .collection("macraSuggestedMealPlans")
                .document("current")
                .updateData(["plan.meals": mealsArray]) { error in
                    if let error {
                        print("[Macra][PlanHub.images] persist failed: \(error.localizedDescription)")
                    } else {
                        print("[Macra][PlanHub.images] ✓ Persisted audit result")
                    }
                }
        } catch {
            print("[Macra][PlanHub.images] encode failed: \(error.localizedDescription)")
        }
    }

    private func fetchCachedPlan(completion: @escaping (MacraSuggestedMealPlan?, String) -> Void) {
        let docRef = Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("macraSuggestedMealPlans")
            .document("current")

        print("[Macra][PlanHub.fetch] Reading users/\(userId)/macraSuggestedMealPlans/current")
        docRef.getDocument { snapshot, error in
            if let error {
                print("[Macra][PlanHub.fetch] ❌ Read failed: \(error.localizedDescription)")
                completion(nil, "Starter Nora Plan")
                return
            }
            guard let data = snapshot?.data() else {
                print("[Macra][PlanHub.fetch] No current doc found")
                completion(nil, "Starter Nora Plan")
                return
            }
            let source = data["source"] as? String ?? "<none>"
            let mirroredName = data["planName"] as? String ?? "<none>"
            print("[Macra][PlanHub.fetch] Doc loaded | source='\(source)' | planName='\(mirroredName)'")

            guard let planDict = data["plan"] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: planDict),
                  let plan = try? JSONDecoder().decode(MacraSuggestedMealPlan.self, from: jsonData) else {
                print("[Macra][PlanHub.fetch] ❌ Failed to decode plan dict")
                completion(nil, "Starter Nora Plan")
                return
            }
            // User-mirrored plans carry their original playbook name in `planName`.
            // Nora-generated plans don't, so we keep the stable "Starter Nora Plan" label.
            let label: String
            if source == "user-selected",
               let trimmed = (data["planName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                label = trimmed
            } else {
                label = "Starter Nora Plan"
            }
            print("[Macra][PlanHub.fetch] ✓ Resolved label='\(label)', \(plan.meals.count) meals")
            completion(plan, label)
        }
    }

    func regenerate(extraContext: String?, images: [UIImage] = [], completion: (() -> Void)? = nil) {
        guard let macros = macroTarget, !isGenerating else {
            completion?()
            return
        }
        isGenerating = true
        errorMessage = nil

        Task { [weak self] in
            do {
                let imageUrls: [String]
                if !images.isEmpty {
                    imageUrls = try await MacraPlanContextImageUploader.shared.upload(images: images)
                } else {
                    imageUrls = []
                }

                let plan = try await MacraMealPlanService.shared.generate(
                    calories: macros.calories,
                    protein: macros.protein,
                    carbs: macros.carbs,
                    fat: macros.fat,
                    goal: nil,
                    dietaryPreference: nil,
                    mealsPerDay: 4,
                    forceRegenerate: true,
                    extraContext: extraContext,
                    imageUrls: imageUrls.isEmpty ? nil : imageUrls
                )
                await MainActor.run {
                    self?.suggestedPlan = plan
                    self?.isGenerating = false
                    completion?()
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                    self?.isGenerating = false
                    completion?()
                }
            }
        }
    }
}

private struct MacraPlanHubSurface: View {
    @StateObject private var viewModel: MacraPlanHubViewModel
    let appCoordinator: AppCoordinator

    @State private var isChangePlanPresented = false
    @State private var isNoraSheetPresented = false
    @State private var activeEditor: MealPlanEditorMode?

    init(userId: String, appCoordinator: AppCoordinator) {
        _viewModel = StateObject(wrappedValue: MacraPlanHubViewModel(userId: userId))
        self.appCoordinator = appCoordinator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroCard

            if viewModel.isLoading && viewModel.suggestedPlan == nil {
                loadingCard
            } else if let plan = viewModel.suggestedPlan {
                macroSummaryCard
                macroMismatchBanner
                planMealsSection(plan: plan)
            } else {
                emptyStateCard
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

            changePlanButton
        }
        .onAppear {
            viewModel.load()
        }
        .sheet(isPresented: $isChangePlanPresented) {
            ChangeMealPlanSheet(
                onNoraCreate: {
                    isChangePlanPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        isNoraSheetPresented = true
                    }
                },
                onBuildOwn: {
                    isChangePlanPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        activeEditor = .create
                    }
                },
                onUsePreexisting: {
                    isChangePlanPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        appCoordinator.showNutritionDestination(.mealPlanning)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isNoraSheetPresented) {
            NoraRegenerateSheet(viewModel: viewModel) {
                isNoraSheetPresented = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeEditor) { mode in
            MealPlanEditorView(mode: mode) { _ in
                activeEditor = nil
            } onCancel: {
                activeEditor = nil
            }
        }
    }

    private var heroCard: some View {
        let accent = Color(hex: "E0FE10")
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR PLAN")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(accent)
                Text("Today's fuel")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundColor(.white)
                if viewModel.suggestedPlan != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(viewModel.planLabel)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(accent.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(accent.opacity(0.32), lineWidth: 1))
                    .padding(.top, 2)
                }
                Text("Macra built this plan from your macro target. Swap anytime.")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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
        )
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color(hex: "E0FE10"))
            Text("Loading your plan…")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var emptyStateCard: some View {
        let accent = Color(hex: "8B5CF6")
        return VStack(spacing: 14) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(accent)
            }
            Text("No plan yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Let Macra generate a meal plan from your macro target, or build one yourself.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                viewModel.regenerate(extraContext: nil)
            } label: {
                Text("Generate a plan")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(hex: "E0FE10")))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(accent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(accent.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private var macroSummaryCard: some View {
        if let macros = viewModel.macroTarget {
            VStack(alignment: .leading, spacing: 12) {
                Text("DAILY TARGETS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "E0FE10"))
                HStack(spacing: 10) {
                    PlanHubMacroTile(label: "Cal", value: "\(macros.calories)", color: Color(hex: "E0FE10"))
                    PlanHubMacroTile(label: "P", value: "\(macros.protein)g", color: Color(hex: "FAFAFA"))
                    PlanHubMacroTile(label: "C", value: "\(macros.carbs)g", color: Color(hex: "3B82F6"))
                    PlanHubMacroTile(label: "F", value: "\(macros.fat)g", color: Color(hex: "FFB454"))
                }
            }
        }
    }

    @ViewBuilder
    private var macroMismatchBanner: some View {
        if viewModel.hasTargetMismatch,
           let totals = viewModel.planTotals,
           let target = viewModel.macroTarget {
            let warn = Color(hex: "FFB454")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(warn)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Macros don't match this plan")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Plan: \(totals.calories) cal · \(totals.protein)P / \(totals.carbs)C / \(totals.fat)F")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                        Text("Target: \(target.calories) cal · \(target.protein)P / \(target.carbs)C / \(target.fat)F")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    viewModel.adaptTargetsToPlan()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isAdaptingTargets ? "hourglass" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .bold))
                        Text(viewModel.isAdaptingTargets ? "Adapting…" : "Match targets to plan")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(warn))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isAdaptingTargets)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(warn.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(warn.opacity(0.32), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func planMealsSection(plan: MacraSuggestedMealPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("MEALS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "8B5CF6"))
                Spacer()
                Text("\(plan.meals.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: "8B5CF6"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: "8B5CF6").opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Color(hex: "8B5CF6").opacity(0.32), lineWidth: 1))
            }

            LazyVStack(spacing: 12) {
                ForEach(Array(plan.meals.enumerated()), id: \.offset) { index, meal in
                    PlanHubMealCard(index: index, meal: meal)
                }
            }

            if let notes = plan.notes, !notes.isEmpty {
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

    private var changePlanButton: some View {
        Button {
            isChangePlanPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                Text("Change meal plan")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct PlanHubMacroTile: View {
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

private struct PlanHubMealCard: View {
    let index: Int
    let meal: MacraSuggestedMeal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                if let urlString = meal.imageURL,
                   !urlString.isEmpty,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        case .failure:
                            Color.white.opacity(0.06)
                        case .empty:
                            Color.white.opacity(0.04)
                        @unknown default:
                            Color.white.opacity(0.04)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .scale))
                }

                Text("Meal \(index + 1)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(meal.totalCalories) kcal")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(meal.items) { item in
                    HStack(alignment: .center, spacing: 10) {
                        if let urlString = item.imageURL,
                           !urlString.isEmpty,
                           let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                case .failure:
                                    Color.white.opacity(0.06)
                                case .empty:
                                    Color.white.opacity(0.04)
                                @unknown default:
                                    Color.white.opacity(0.04)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .transition(.opacity.combined(with: .scale))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.95))
                            Text(item.quantity)
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                        Text("\(item.calories)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }

            HStack(spacing: 8) {
                mealMacroChip(label: "P", value: meal.totalProtein, color: Color(hex: "3B82F6"))
                mealMacroChip(label: "C", value: meal.totalCarbs, color: Color(hex: "E0FE10"))
                mealMacroChip(label: "F", value: meal.totalFat, color: Color(hex: "FFB454"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func mealMacroChip(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text("\(value)g")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
    }
}

private struct ChangeMealPlanSheet: View {
    let onNoraCreate: () -> Void
    let onBuildOwn: () -> Void
    let onUsePreexisting: () -> Void

    private let lime = Color(hex: "E0FE10")
    private let mint = Color(hex: "6EE7B7")
    private let lilac = Color(hex: "C4B5FD")

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "07070B"), Color(hex: "0C0C14"), Color(hex: "100D18")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(lime.opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: -140, y: -220)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    headerSection

                    VStack(spacing: 12) {
                        ChangeMealPlanOption(
                            icon: "sparkles",
                            title: "Have Nora create a new plan",
                            subtitle: "Answer a quick prompt and Macra's AI generates a fresh plan tuned to your macros.",
                            accent: lime,
                            isRecommended: true,
                            action: onNoraCreate
                        )

                        ChangeMealPlanOption(
                            icon: "hammer.fill",
                            title: "Build your own plan",
                            subtitle: "Start from scratch and add meals from your journal history as you go.",
                            accent: mint,
                            isRecommended: false,
                            action: onBuildOwn
                        )

                        ChangeMealPlanOption(
                            icon: "tray.full.fill",
                            title: "Use a pre-existing plan",
                            subtitle: "Pick from plans you've built before — or ones Nora made for you in the past.",
                            accent: lilac,
                            isRecommended: false,
                            action: onUsePreexisting
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHANGE YOUR PLAN")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(lime)
            Text("How do you want to roll?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .foregroundColor(.white)
            Text("Pick the starting point. You can always come back and swap.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

private struct ChangeMealPlanOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let isRecommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.14))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accent.opacity(0.28), lineWidth: 1)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if isRecommended {
                            Text("PICK")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.0)
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(accent))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(.white.opacity(0.58))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.42))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                    if isRecommended {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(accent.opacity(0.04))
                    }
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    (isRecommended ? accent : Color.white).opacity(isRecommended ? 0.35 : 0.10),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct NoraRegenerateSheet: View {
    @ObservedObject var viewModel: MacraPlanHubViewModel
    let onDone: () -> Void

    @State private var extraContext: String = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @FocusState private var focused: Bool

    private let accent = Color(hex: "E0FE10")
    private let maxImages = 5

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(hex: "0E1116"), Color(hex: "121820")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection

                    contextField
                    imagesField

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundColor(Color(hex: "EF4444"))
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }

            VStack {
                Spacer()
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if viewModel.isGenerating {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(viewModel.isGenerating ? "Generating…" : "Generate new plan")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(accent))
                    .shadow(color: accent.opacity(0.45), radius: 18, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGenerating)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
        .onChange(of: photoItems) { items in
            Task { await loadImages(from: items) }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NORA · AI COACH")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(accent)
            Text("What should Nora consider?")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(-0.4)
                .foregroundColor(.white)
            Text("Preferences, restrictions, training load, what's in your fridge. Drop in photos too — the menu, the groceries, your physique — whatever she should weigh.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var contextField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTEXT")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(accent)

            TextField(
                "",
                text: $extraContext,
                prompt: Text("e.g. vegetarian this week, skip dairy, prep-friendly")
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.38)),
                axis: .vertical
            )
            .font(.system(size: 15, weight: .regular, design: .default))
            .foregroundColor(.white)
            .lineLimit(4...10)
            .focused($focused)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(accent.opacity(0.22), lineWidth: 1))
        }
    }

    private var imagesField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("IMAGES")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "8B5CF6"))
                Text("optional · up to \(maxImages)")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.42))
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if selectedImages.count < maxImages {
                        PhotosPicker(
                            selection: $photoItems,
                            maxSelectionCount: maxImages - selectedImages.count,
                            matching: .images
                        ) {
                            addImageTile
                        }
                    }

                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                        imageTile(image: image, index: index)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var addImageTile: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.plus.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Color(hex: "8B5CF6"))
            Text("Add photo")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.72))
        }
        .frame(width: 90, height: 90)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "8B5CF6").opacity(0.10)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(hex: "8B5CF6").opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private func imageTile(image: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )

            Button {
                removeImage(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    private func removeImage(at index: Int) {
        guard selectedImages.indices.contains(index) else { return }
        selectedImages.remove(at: index)
        if photoItems.indices.contains(index) {
            photoItems.remove(at: index)
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        await MainActor.run {
            selectedImages = loaded
        }
    }

    private func submit() {
        let trimmed = extraContext.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.regenerate(
            extraContext: trimmed.isEmpty ? nil : trimmed,
            images: selectedImages
        ) {
            onDone()
        }
    }
}

// MARK: - Ask Nora (Journal AI coach)

struct NoraChatService {
    static let shared = NoraChatService()

    private struct IngredientPayload: Encodable {
        let name: String
        let quantity: String
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
    }

    private struct MealPayload: Encodable {
        let name: String
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let ingredients: [IngredientPayload]?
    }

    private struct AttachedMealPayload: Encodable {
        let name: String
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let loggedOnLabel: String?
        let loggedOnKey: String?
        let ingredients: [IngredientPayload]?
    }

    private struct TargetPayload: Encodable {
        let calories: Int?
        let protein: Int?
        let carbs: Int?
        let fat: Int?
    }

    private struct HistoryEntry: Encodable {
        let role: String
        let content: String
    }

    private struct Request: Encodable {
        let query: String
        let meals: [MealPayload]
        let attachedMeals: [AttachedMealPayload]?
        let target: TargetPayload?
        let history: [HistoryEntry]?
        let goal: String?
        let threadDate: String
        let threadDateKey: String
        let threadDateLabel: String
        let currentDate: String
        let currentDateKey: String
        let timezone: String
        let isToday: Bool
    }

    private struct Response: Decodable {
        let reply: String
        let generatedAt: Double?
    }

    func ask(
        query: String,
        meals: [Meal],
        target: MacroRecommendation?,
        history: [MacraNoraMessage] = [],
        threadDate: Date = Date(),
        attachedMeals: [(meal: Meal, loggedOn: Date)] = []
    ) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw MacraMealPlanServiceError.notAuthenticated
        }
        let token = try await user.getIDToken()

        let base = ConfigManager.shared.getWebsiteBaseURL()
        guard let url = URL(string: "\(base)/.netlify/functions/nora-nutrition-chat") else {
            throw MacraMealPlanServiceError.invalidResponse
        }

        let mealPayloads = meals.map { meal -> MealPayload in
            MealPayload(
                name: meal.name,
                calories: meal.calories,
                protein: meal.protein,
                carbs: meal.carbs,
                fat: meal.fat,
                ingredients: NoraChatService.ingredientPayloads(for: meal)
            )
        }
        let attachedPayloads = attachedMeals.map { entry -> AttachedMealPayload in
            AttachedMealPayload(
                name: entry.meal.name,
                calories: entry.meal.calories,
                protein: entry.meal.protein,
                carbs: entry.meal.carbs,
                fat: entry.meal.fat,
                loggedOnLabel: NoraChatService.attachmentDateLabel(for: entry.loggedOn),
                loggedOnKey: entry.loggedOn.macraFoodJournalDayKey,
                ingredients: NoraChatService.ingredientPayloads(for: entry.meal)
            )
        }
        let targetPayload = target.map {
            TargetPayload(calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat)
        }
        // Pass the tail of the existing thread so follow-up questions keep
        // context across turns. 6 entries ≈ 3 exchanges, matching the old
        // behavior while now reading straight from persisted thread state.
        let historyTail = history.suffix(6).map {
            HistoryEntry(role: $0.role.rawValue, content: $0.content)
        }
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let calendar = Calendar.current
        let selectedDateLabel: String = {
            if calendar.isDateInToday(threadDate) { return "Today" }
            if calendar.isDateInYesterday(threadDate) { return "Yesterday" }
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
            return formatter.string(from: threadDate)
        }()

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 45

        let payload = Request(
            query: query,
            meals: mealPayloads,
            attachedMeals: attachedPayloads.isEmpty ? nil : attachedPayloads,
            target: targetPayload,
            history: historyTail.isEmpty ? nil : historyTail,
            goal: nil,
            threadDate: isoFormatter.string(from: threadDate),
            threadDateKey: threadDate.macraFoodJournalDayKey,
            threadDateLabel: selectedDateLabel,
            currentDate: isoFormatter.string(from: now),
            currentDateKey: now.macraFoodJournalDayKey,
            timezone: TimeZone.current.identifier,
            isToday: calendar.isDateInToday(threadDate)
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, httpResponse) = try await URLSession.shared.data(for: urlRequest)
        guard let http = httpResponse as? HTTPURLResponse else {
            throw MacraMealPlanServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw MacraMealPlanServiceError.server("Nora chat returned \(http.statusCode): \(bodyString.prefix(200))")
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.reply
    }

    fileprivate static func attachmentDateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: date)
    }

    private static func ingredientPayloads(for meal: Meal) -> [IngredientPayload]? {
        guard let detailed = meal.detailedIngredients, !detailed.isEmpty else {
            return nil
        }
        let payloads = detailed.map { detail in
            IngredientPayload(
                name: detail.name,
                quantity: detail.quantity,
                calories: detail.calories,
                protein: detail.protein,
                carbs: detail.carbs,
                fat: detail.fat
            )
        }
        return payloads.isEmpty ? nil : payloads
    }
}

private struct NoraPromptPreset: Identifiable {
    let id = UUID()
    let label: String
    let prompt: String
    let icon: String
    let accentHex: String

    var accent: Color { Color(hex: accentHex) }
}

struct AskNoraSection: View {
    let meals: [Meal]
    let target: MacroRecommendation?
    let threadDate: Date
    let userId: String?
    let isDayContextLoading: Bool

    @State private var query: String = ""
    @State private var messages: [MacraNoraMessage] = []
    @State private var isAsking: Bool = false
    @State private var isLoadingThread: Bool = false
    @State private var errorMessage: String?
    @State private var loadedDayKey: String?
    @State private var attachedItems: [MealAttachmentItem] = []
    @State private var showingAttachSheet: Bool = false
    @State private var copiedToastVisible: Bool = false
    @State private var copiedToastTask: DispatchWorkItem?
    @FocusState private var focused: Bool

    private let noraAccent = Color(hex: "E0FE10")

    private let presets: [NoraPromptPreset] = [
        NoraPromptPreset(
            label: "Analyze my day",
            prompt: "Give me a complete analysis of this food log. How are my macros, calorie intake, and meal balance? What stands out?",
            icon: "chart.bar.doc.horizontal",
            accentHex: "3B82F6"
        ),
        NoraPromptPreset(
            label: "What am I missing?",
            prompt: "What key nutrients or food groups are missing from this food log? Are there any gaps in my nutrition that I should address going forward?",
            icon: "exclamationmark.triangle.fill",
            accentHex: "FFB454"
        ),
        NoraPromptPreset(
            label: "Improvement tips",
            prompt: "Based on this food log and supplements, give me 3-5 specific, actionable tips to improve my nutrition.",
            icon: "arrow.up.right.circle.fill",
            accentHex: "8B5CF6"
        )
    ]

    private var dayKey: String { threadDate.macraFoodJournalDayKey }

    private var isToday: Bool {
        Calendar.current.isDateInToday(threadDate)
    }

    private var threadDateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(threadDate) { return "Today" }
        if calendar.isDateInYesterday(threadDate) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: threadDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            presetRow
            attachmentsRow
            composer
            if let error = errorMessage {
                errorPill(error)
            }
            threadBody
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(noraAccent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [noraAccent.opacity(0.45), noraAccent.opacity(0.14), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: noraAccent.opacity(0.18), radius: 20, x: 0, y: 10)
        )
        .overlay(alignment: .top) {
            if copiedToastVisible {
                copiedToastView
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear { loadThreadIfNeeded(force: false) }
        .onChange(of: dayKey) { _ in loadThreadIfNeeded(force: true) }
        .onChange(of: userId) { _ in loadThreadIfNeeded(force: true) }
        .sheet(isPresented: $showingAttachSheet) {
            MealAttachmentSheet(
                userId: userId,
                threadDate: threadDate,
                currentlyAttached: attachedItems,
                onConfirm: { items in
                    attachedItems = items
                    showingAttachSheet = false
                },
                onCancel: { showingAttachSheet = false }
            )
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            NoraOrb(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("ASK NORA")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(noraAccent)
                Text("Your nutrition coach")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Spacer()
            if !isToday {
                Text(threadDateLabel.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(noraAccent.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(noraAccent.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(noraAccent.opacity(0.3), lineWidth: 1))
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(presets) { preset in
                Button {
                    runQuery(preset.prompt, preset: preset)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: preset.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(preset.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundColor(preset.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(preset.accent.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(preset.accent.opacity(0.34), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isAsking || isDayContextLoading)
            }
        }
        .padding(.vertical, 2)
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                focused = false
                showingAttachSheet = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(attachedItems.isEmpty ? 0.75 : 1.0))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(attachedItems.isEmpty ? Color.white.opacity(0.06) : noraAccent.opacity(0.18))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(attachedItems.isEmpty ? Color.white.opacity(0.14) : noraAccent.opacity(0.55), lineWidth: 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if !attachedItems.isEmpty {
                            Text("\(attachedItems.count)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(noraAccent))
                                .offset(x: 4, y: -2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isAsking || isDayContextLoading)
            .accessibilityLabel(attachedItems.isEmpty ? "Attach meals from history" : "\(attachedItems.count) meals attached")

            TextField(
                "",
                text: $query,
                prompt: Text(isToday ? "Ask about your nutrition today…" : "Ask Nora about \(threadDateLabel)…")
                    .foregroundColor(.white.opacity(0.38))
                    .font(.system(size: 14, weight: .regular, design: .default))
            )
            .font(.system(size: 14, weight: .regular, design: .default))
            .foregroundColor(.white)
            .submitLabel(.send)
            .focused($focused)
            .onSubmit { sendCustom() }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))

            Button(action: sendCustom) {
                Group {
                    if isAsking {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .frame(width: 40, height: 40)
                .background(Circle().fill(noraAccent))
                .shadow(color: noraAccent.opacity(0.5), radius: 12, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(isAsking || isDayContextLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(isAsking || isDayContextLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private var attachmentsRow: some View {
        if !attachedItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(attachedItems) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(noraAccent)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.meal.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(item.dayLabel.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(0.6)
                                    .foregroundColor(noraAccent.opacity(0.75))
                            }
                            Button {
                                attachedItems.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(noraAccent.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(noraAccent.opacity(0.35), lineWidth: 1))
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var copiedToastView: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 11, weight: .bold))
            Text("Copied!")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundColor(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(noraAccent))
        .shadow(color: noraAccent.opacity(0.45), radius: 10, x: 0, y: 4)
    }

    private func showCopiedToast() {
        copiedToastTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            copiedToastVisible = true
        }
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.22)) {
                copiedToastVisible = false
            }
        }
        copiedToastTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    @ViewBuilder
    private func errorPill(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(threadLoadErrorDisplayMessage(message))
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(Color(hex: "EF4444"))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                loadThreadIfNeeded(force: true)
            } label: {
                HStack(spacing: 6) {
                    if isLoadingThread {
                        ProgressView()
                            .tint(Color(hex: "EF4444"))
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text("Retry")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(hex: "EF4444"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(hex: "EF4444").opacity(0.10)))
                .overlay(Capsule().strokeBorder(Color(hex: "EF4444").opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingThread)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "EF4444").opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(hex: "EF4444").opacity(0.24), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var threadBody: some View {
        if isLoadingThread && messages.isEmpty {
            HStack(spacing: 8) {
                ProgressView().tint(noraAccent)
                Text("Loading thread…")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isDayContextLoading && messages.isEmpty {
            HStack(spacing: 8) {
                ProgressView().tint(noraAccent)
                Text("Loading \(threadDateLabel.lowercased()) context…")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if messages.isEmpty && !isAsking {
            threadEmptyState
        } else {
            threadTimeline
        }
    }

    private var threadEmptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NO THREAD FOR \(threadDateLabel.uppercased())")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundColor(.white.opacity(0.45))
            Text(isToday
                 ? "Ask Nora anything about today's food. Your conversation will be saved here."
                 : "Ask Nora about \(threadDateLabel)'s meals. The thread will be saved against that date.")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private var threadTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("THREAD · \(threadDateLabel.uppercased())")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundColor(noraAccent)
                Spacer()
                Text("\(messages.count) \(messages.count == 1 ? "message" : "messages")")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }

            VStack(spacing: 10) {
                ForEach(messages) { message in
                    NoraMessageBubble(
                        message: message,
                        defaultAccentHex: "E0FE10",
                        onCopy: { showCopiedToast() }
                    )
                }

                if isAsking {
                    NoraTypingBubble(accentHex: "E0FE10")
                }
            }
        }
    }

    // MARK: - Thread loading

    private func loadThreadIfNeeded(force: Bool) {
        let currentKey = dayKey
        print("[Macra][Nora][LOAD-START] threadDate=\(threadDate) dayKey=\(currentKey) loadedDayKey=\(loadedDayKey ?? "nil") force=\(force) isToday=\(Calendar.current.isDateInToday(threadDate)) label=\(threadDateLabel) now=\(Date())")
        if !force, loadedDayKey == currentKey, errorMessage == nil {
            print("[Macra][Nora][LOAD-SKIP] already loaded for dayKey=\(currentKey), in-memory msgCount=\(messages.count)")
            return
        }

        errorMessage = nil
        loadedDayKey = currentKey

        // Local cache is the UI source of truth — populate it synchronously
        // so the thread shows up instantly (and survives Firestore failures,
        // missing indexes, offline, or a cold-start before auth hydrates).
        messages = MacraNoraThreadCache.load(userId: userId, dayKey: currentKey)
        print("[Macra][Nora][CACHE-LOAD] requestedDayKey=\(currentKey) returned=\(messages.count)")
        for m in messages {
            print("[Macra][Nora][CACHE-LOAD-MSG] id=\(m.id) role=\(m.role.rawValue) dayKey=\(m.dayKey) ts=\(m.timestamp) preview=\(String(m.content.prefix(40)))")
        }

        guard userId != nil else {
            // Not signed in → local-only thread.
            print("[Macra][Nora][LOAD-ANON] no userId — local-only thread")
            return
        }

        isLoadingThread = true
        MacraNoraChatService.sharedInstance.loadMessages(
            for: threadDate,
            userId: userId
        ) { result in
            DispatchQueue.main.async {
                guard loadedDayKey == currentKey else {
                    print("[Macra][Nora][LOAD-RESULT-STALE] callback dayKey=\(currentKey) but loadedDayKey=\(loadedDayKey ?? "nil") — discarding")
                    return
                }
                isLoadingThread = false
                switch result {
                case .success(let loaded):
                    // Merge remote into local so we pick up cross-device
                    // history without clobbering messages that are still
                    // pending their Firestore round-trip.
                    messages = MacraNoraThreadCache.merge(
                        remote: loaded,
                        userId: userId,
                        dayKey: currentKey
                    )
                    print("[Macra][Nora][LOAD-MERGED] dayKey=\(currentKey) finalMsgCount=\(messages.count)")
                    for m in messages {
                        print("[Macra][Nora][LOAD-MERGED-MSG] id=\(m.id) role=\(m.role.rawValue) dayKey=\(m.dayKey) ts=\(m.timestamp) preview=\(String(m.content.prefix(40)))")
                    }
                case .failure(let error):
                    // Silent fallback — we still have the local cache, so
                    // the user keeps their thread. Only surface the error
                    // if the cache was empty (nothing to show otherwise).
                    if messages.isEmpty {
                        errorMessage = "Couldn't load thread: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func threadLoadErrorDisplayMessage(_ message: String) -> String {
        if message.localizedCaseInsensitiveContains("requires an index") {
            return "Nora thread is still syncing. Try again in a moment."
        }
        return message
    }

    // MARK: - Send

    private func sendCustom() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runQuery(trimmed, preset: nil)
    }

    private func runQuery(_ text: String, preset: NoraPromptPreset?) {
        guard !isAsking else { return }
        guard !isDayContextLoading else {
            errorMessage = "Nora is still loading \(threadDateLabel.lowercased())'s meals. Try again in a moment."
            return
        }
        focused = false
        isAsking = true
        errorMessage = nil
        MacraAudioService.sharedInstance.playSound(.noraGreeting)

        let askedAt = Date()
        let threadDayKey = dayKey
        let threadDateSnapshot = threadDate
        let mealsSnapshot = meals
        let targetSnapshot = target
        let userIdSnapshot = userId
        print("[Macra][Nora][WRITE-CTX] threadDate=\(threadDateSnapshot) threadDayKey=\(threadDayKey) askedAt=\(askedAt) deviceNow=\(Date()) askedAtDayKeyFromTs=\(askedAt.macraFoodJournalDayKey) isToday=\(Calendar.current.isDateInToday(threadDateSnapshot))")
        // Drop any attached meal whose content matches a meal already in
        // today's log — those reach Nora through `mealsSnapshot` and would
        // otherwise be duplicated in the prompt context.
        let primaryKeys: Set<String> = Set(mealsSnapshot.map { meal in
            let trimmedName = meal.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "\(trimmedName)|\(meal.calories)|\(meal.protein)|\(meal.carbs)|\(meal.fat)"
        })
        let attachmentsSnapshot: [(meal: Meal, loggedOn: Date)] = attachedItems
            .filter { !primaryKeys.contains($0.dedupeKey) }
            .map { ($0.meal, $0.loggedOn) }
        let userMessage = MacraNoraMessage(
            role: .user,
            content: text,
            timestamp: askedAt,
            dayKey: threadDayKey,
            accentHex: preset?.accentHex ?? "E0FE10",
            iconSystemName: preset?.icon ?? "sparkles"
        )

        // Optimistically show the user's bubble and persist it so the prompt
        // survives even if the model call fails. Write to the local cache
        // first (guaranteed durable) then fire-and-forget Firestore sync.
        messages.append(userMessage)
        query = ""
        print("[Macra][Nora][WRITE-USER-MSG] id=\(userMessage.id) dayKey=\(userMessage.dayKey) ts=\(userMessage.timestamp) tsDayKey=\(userMessage.timestamp.macraFoodJournalDayKey)")
        MacraNoraThreadCache.append(userMessage, userId: userIdSnapshot)
        MacraNoraChatService.sharedInstance.saveMessage(userMessage, userId: userIdSnapshot) { result in
            if case .failure(let error) = result {
                print("[Macra][Nora] ❌ user-message sync failed — local cache holds it: \(error.localizedDescription)")
            }
        }

        let historySnapshot = messages

        Task {
            do {
                let reply = try await NoraChatService.shared.ask(
                    query: text,
                    meals: mealsSnapshot,
                    target: targetSnapshot,
                    history: historySnapshot,
                    threadDate: threadDateSnapshot,
                    attachedMeals: attachmentsSnapshot
                )
                let assistantMessage = MacraNoraMessage(
                    role: .assistant,
                    content: reply,
                    timestamp: Date(),
                    dayKey: threadDayKey,
                    accentHex: "E0FE10",
                    iconSystemName: "sparkles"
                )
                print("[Macra][Nora][WRITE-ASSISTANT-MSG] id=\(assistantMessage.id) dayKey=\(assistantMessage.dayKey) ts=\(assistantMessage.timestamp) tsDayKey=\(assistantMessage.timestamp.macraFoodJournalDayKey)")
                await MainActor.run {
                    if dayKey == threadDayKey {
                        messages.append(assistantMessage)
                    }
                    MacraNoraThreadCache.append(assistantMessage, userId: userIdSnapshot)
                    isAsking = false
                }
                MacraNoraChatService.sharedInstance.saveMessage(assistantMessage, userId: userIdSnapshot) { result in
                    if case .failure(let error) = result {
                        print("[Macra][Nora] ❌ assistant-message sync failed — local cache holds it: \(error.localizedDescription)")
                    }
                }
            } catch {
                await MainActor.run {
                    if dayKey == threadDayKey {
                        errorMessage = error.localizedDescription
                    }
                    isAsking = false
                }
            }
        }
    }
}

// MARK: - Meal Attachments (Ask Nora)

struct MealAttachmentItem: Identifiable, Hashable {
    let id: String
    let meal: Meal
    let loggedOn: Date

    var dedupeKey: String {
        let trimmedName = meal.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(trimmedName)|\(meal.calories)|\(meal.protein)|\(meal.carbs)|\(meal.fat)"
    }

    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(loggedOn) { return "Today" }
        if calendar.isDateInYesterday(loggedOn) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: loggedOn)
    }
}

struct MealAttachmentSheet: View {
    let userId: String?
    let threadDate: Date
    let currentlyAttached: [MealAttachmentItem]
    let onConfirm: ([MealAttachmentItem]) -> Void
    let onCancel: () -> Void

    @State private var allItems: [MealAttachmentItem] = []
    @State private var selectedKeys: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var searchText: String = ""

    private let store: any MealPlanningStore = FirestoreMealPlanningStore()
    private let macraBlue = Color(hex: "3B82F6")

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Attach meals")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onCancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { confirm() }
                            .fontWeight(.semibold)
                    }
                }
                .onAppear { loadIfNeeded() }
        }
    }

    private var filteredItems: [MealAttachmentItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return allItems }
        return allItems.filter { item in
            item.meal.name.lowercased().contains(trimmed)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && allItems.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading meal history…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorMessage, allItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.orange)
                Text("Couldn't load meal history.")
                    .font(.subheadline)
                Text(err)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Retry") { loadIfNeeded(force: true) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hasLoaded && allItems.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("No meals logged in the last 24 days.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                searchField
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(macraBlue)
                                Text("LAST 24 DAYS")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .tracking(1.0)
                                    .foregroundColor(macraBlue)
                            }
                            Text("Pick meals from your last 24 days to give Nora extra context. Duplicates are filtered automatically.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    if filteredItems.isEmpty {
                        Section {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                Text("No meals match \u{201C}\(searchText)\u{201D}.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    } else {
                        ForEach(groupedItems, id: \.label) { group in
                            Section(header: Text(group.label)) {
                                ForEach(group.items) { item in
                                    attachmentRow(item)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            TextField("Search meals", text: $searchText)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func attachmentRow(_ item: MealAttachmentItem) -> some View {
        let isSelected = selectedKeys.contains(item.dedupeKey)
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(isSelected ? macraBlue : Color.secondary.opacity(0.6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.meal.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text("\(item.meal.calories) kcal · \(item.meal.protein)P \(item.meal.carbs)C \(item.meal.fat)F")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            MealPlanningMealThumbnail(meal: item.meal, size: 44)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggle(item)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private struct DayGroup {
        let label: String
        let sortDate: Date
        let items: [MealAttachmentItem]
    }

    private var groupedItems: [DayGroup] {
        let grouped = Dictionary(grouping: filteredItems, by: { $0.dayLabel })
        return grouped.map { (label, items) in
            let sorted = items.sorted { $0.loggedOn > $1.loggedOn }
            return DayGroup(
                label: label,
                sortDate: sorted.first?.loggedOn ?? .distantPast,
                items: sorted
            )
        }
        .sorted { $0.sortDate > $1.sortDate }
    }

    private func toggle(_ item: MealAttachmentItem) {
        if selectedKeys.contains(item.dedupeKey) {
            selectedKeys.remove(item.dedupeKey)
        } else {
            selectedKeys.insert(item.dedupeKey)
        }
    }

    private func confirm() {
        let chosen = allItems.filter { selectedKeys.contains($0.dedupeKey) }
        var unique: [String: MealAttachmentItem] = [:]
        for item in chosen.sorted(by: { $0.loggedOn > $1.loggedOn }) {
            if unique[item.dedupeKey] == nil {
                unique[item.dedupeKey] = item
            }
        }
        let result = unique.values.sorted { $0.loggedOn > $1.loggedOn }
        onConfirm(Array(result))
    }

    private func loadIfNeeded(force: Bool = false) {
        guard force || !hasLoaded else { return }
        guard let userId else {
            errorMessage = "Sign in to attach meals from history."
            hasLoaded = true
            return
        }

        isLoading = true
        errorMessage = nil

        store.fetchRecentMeals(userId: userId, limit: 300) { result in
            DispatchQueue.main.async {
                isLoading = false
                hasLoaded = true
                switch result {
                case .success(let meals):
                    // Window: today + previous 24 days = 25 calendar days inclusive.
                    let cutoff = Calendar.current.date(
                        byAdding: .day,
                        value: -24,
                        to: Calendar.current.startOfDay(for: Date())
                    ) ?? .distantPast

                    let candidates = meals
                        .filter { $0.createdAt >= cutoff }
                        .map { MealAttachmentItem(id: $0.id, meal: $0, loggedOn: $0.createdAt) }

                    var unique: [String: MealAttachmentItem] = [:]
                    for item in candidates.sorted(by: { $0.loggedOn > $1.loggedOn }) {
                        if unique[item.dedupeKey] == nil {
                            unique[item.dedupeKey] = item
                        }
                    }

                    // Carry forward any currently-attached items that fell
                    // outside the 24-day window so the user doesn't silently
                    // lose their selection when re-opening the sheet.
                    for attached in currentlyAttached where unique[attached.dedupeKey] == nil {
                        unique[attached.dedupeKey] = attached
                    }

                    allItems = unique.values.sorted { $0.loggedOn > $1.loggedOn }
                    selectedKeys = Set(currentlyAttached.map { $0.dedupeKey })
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct NoraMessageBubble: View {
    let message: MacraNoraMessage
    let defaultAccentHex: String
    var onCopy: (() -> Void)? = nil

    private var accent: Color {
        Color(hex: message.accentHex ?? defaultAccentHex)
    }

    private var timestampLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: message.timestamp)
    }

    private var attributedContent: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: message.content, options: options) {
            return parsed
        }
        return AttributedString(message.content)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 40)
                bubble
            } else {
                assistantAvatar
                bubble
                Spacer(minLength: 40)
            }
        }
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle().fill(accent.opacity(0.16)).frame(width: 28, height: 28)
            Circle().strokeBorder(accent.opacity(0.32), lineWidth: 1).frame(width: 28, height: 28)
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(accent)
        }
    }

    private var bubble: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                if message.role == .user, let icon = message.iconSystemName {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accent)
                }
                Text(message.role == .user ? "YOU" : "NORA")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(accent.opacity(0.8))
                Text(timestampLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            Text(attributedContent)
                .font(.system(size: 13, weight: message.role == .user ? .semibold : .regular, design: .rounded))
                .foregroundColor(.white.opacity(message.role == .user ? 1 : 0.85))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(message.role == .user ? accent.opacity(0.10) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(message.role == .user ? 0.32 : 0.2), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.4) {
            UIPasteboard.general.string = message.content
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onCopy?()
        }
    }
}

private struct NoraTypingBubble: View {
    let accentHex: String
    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color(hex: accentHex).opacity(0.16)).frame(width: 28, height: 28)
                Circle().strokeBorder(Color(hex: accentHex).opacity(0.32), lineWidth: 1).frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: accentHex))
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color(hex: accentHex))
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.55 * abs(sin(phase + Double(i) * 0.6)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: accentHex).opacity(0.2), lineWidth: 1))
            Spacer(minLength: 40)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Pin Toggle & Pinned Rows

private struct PinnedScansEmptyCard: View {
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primaryGreen.opacity(0.14))
                    .frame(width: 56, height: 56)
                Image(systemName: "pin.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.primaryGreen)
            }

            Text("Pin your go-to scans")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Tap the pin icon on any food snap or label scan below to add it here for one-tap logging.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.60))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primaryGreen.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct PinToggleBadge: View {
    let isPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isPinned ? Color.primaryGreen : .white.opacity(0.78))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isPinned ? Color.primaryGreen.opacity(0.18) : Color.black.opacity(0.45))
                )
                .overlay(
                    Circle()
                        .strokeBorder(isPinned ? Color.primaryGreen.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.32), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPinned ? "Unpin" : "Pin")
    }
}

private struct PinnedFoodSnapQuickAddRow: View {
    let meal: Meal
    let onQuickLog: () -> Void
    let onUnpin: () -> Void

    @State private var justLogged = false

    private var hasImage: Bool {
        !meal.image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name.isEmpty ? "Meal" : meal.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(meal.calories) kcal · P \(meal.protein) · C \(meal.carbs) · F \(meal.fat)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            unpinButton
            quickAddButton
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primaryGreen.opacity(0.22), lineWidth: 1)
        )
        .contextMenu {
            Button { triggerLog() } label: { Label("Log to today", systemImage: "plus.circle.fill") }
            Button(role: .destructive) { onUnpin() } label: { Label("Unpin", systemImage: "pin.slash") }
        }
    }

    private var unpinButton: some View {
        Button(action: onUnpin) {
            Image(systemName: "pin.slash.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unpin meal")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if hasImage {
            RemoteImage(url: meal.image)
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primaryGreen.opacity(0.16))
                Image(systemName: "fork.knife")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primaryGreen)
            }
            .frame(width: 44, height: 44)
        }
    }

    private var quickAddButton: some View {
        Button(action: triggerLog) {
            HStack(spacing: 6) {
                Image(systemName: justLogged ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .bold))
                Text(justLogged ? "Added" : "Log")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(justLogged ? Color.primaryGreen : .black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(justLogged ? Color.primaryGreen.opacity(0.18) : Color.primaryGreen)
            )
        }
        .buttonStyle(.plain)
    }

    private func triggerLog() {
        onQuickLog()
        withAnimation(.easeInOut(duration: 0.2)) { justLogged = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.2)) { justLogged = false }
        }
    }
}

private struct PinnedLabelQuickAddRow: View {
    let scan: MacraScannedLabel
    let onQuickLog: () -> Void
    let onUnpin: () -> Void

    @State private var justLogged = false

    private var title: String { scan.displayTitle }
    private var calories: Int { scan.gradeResult.calories ?? 0 }
    private var protein: Int { scan.gradeResult.protein ?? 0 }
    private var carbs: Int { scan.gradeResult.carbs ?? 0 }
    private var fat: Int { scan.gradeResult.fat ?? 0 }

    private var gradeColor: Color {
        switch scan.gradeResult.grade.uppercased() {
        case "A": return Color.primaryGreen
        case "B": return Color(hex: "32C997")
        case "C": return Color.primaryBlue
        case "D": return Color.orange
        case "F": return Color.red
        default: return Color.white.opacity(0.52)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(calories) kcal · P \(protein) · C \(carbs) · F \(fat)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            unpinButton
            quickAddButton
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ScanFeedAccent.labelScan.opacity(0.32), lineWidth: 1)
        )
        .contextMenu {
            Button { triggerLog() } label: { Label("Log to today", systemImage: "plus.circle.fill") }
            Button(role: .destructive) { onUnpin() } label: { Label("Unpin", systemImage: "pin.slash") }
        }
    }

    private var unpinButton: some View {
        Button(action: onUnpin) {
            Image(systemName: "pin.slash.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unpin scan")
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            if let imageURL = scan.imageURL, !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RemoteImage(url: imageURL)
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(gradeColor.opacity(0.18))
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(gradeColor)
                }
                .frame(width: 44, height: 44)
            }

            Text(scan.gradeResult.grade.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(gradeColor))
                .offset(x: 4, y: 4)
        }
        .frame(width: 44, height: 44)
    }

    private var quickAddButton: some View {
        Button(action: triggerLog) {
            HStack(spacing: 6) {
                Image(systemName: justLogged ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .bold))
                Text(justLogged ? "Added" : "Log")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(justLogged ? Color.primaryGreen : .black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(justLogged ? Color.primaryGreen.opacity(0.18) : Color.primaryGreen)
            )
        }
        .buttonStyle(.plain)
    }

    private func triggerLog() {
        onQuickLog()
        withAnimation(.easeInOut(duration: 0.2)) { justLogged = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.2)) { justLogged = false }
        }
    }
}

// MARK: - Scan Feed

enum ScanFeedItem: Identifiable {
    case meal(Meal)
    case label(MacraScannedLabel)

    var id: String {
        switch self {
        case .meal(let meal): return "meal-\(meal.id)"
        case .label(let label): return "label-\(label.id)"
        }
    }

    var createdAt: Date {
        switch self {
        case .meal(let meal): return meal.createdAt
        case .label(let label): return label.createdAt
        }
    }
}

private struct ScanFeedAccent {
    static let photoMeal = Color(hex: "3B82F6")
    static let textMeal = Color(hex: "E0FE10")
    static let voiceMeal = Color(hex: "06B6D4")
    static let labelScan = Color(hex: "8B5CF6")
}

private struct ScannerInfoCard: View {
    let title: String
    let message: String
    let systemImage: String
    let accent: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(accent.opacity(0.82))

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct QuickLiftsLabelScanCard: View {
    let scan: MacraScannedLabel
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onTap: () -> Void

    private var accent: Color { ScanFeedAccent.labelScan }

    private var displayTitle: String? {
        let fromScan = scan.productTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromScan, !fromScan.isEmpty { return fromScan }

        let fromGrade = scan.gradeResult.productTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromGrade, !fromGrade.isEmpty { return fromGrade }

        return nil
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                cardImageView
                cardContentView
            }
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.54),
                                Color.secondaryCharcoal.opacity(0.76)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                gradeColor.opacity(0.34),
                                accent.opacity(0.16),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.24), radius: 14, x: 0, y: 8)
            .overlay(alignment: .topTrailing) {
                PinToggleBadge(isPinned: isPinned, action: onTogglePin)
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTogglePin()
            } label: {
                Label(isPinned ? "Unpin scan" : "Pin scan", systemImage: isPinned ? "pin.slash" : "pin.fill")
            }
        }
    }

    private var cardImageView: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let imageURL = scan.imageURL, !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    RemoteImage(url: imageURL)
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    gradeColor.opacity(0.30),
                                    gradeColor.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(gradeColor.opacity(0.70))
                        )
                }
            }
            .frame(width: 100, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(scan.gradeResult.grade.uppercased())
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(gradeColor))
                .shadow(color: gradeColor.opacity(0.50), radius: 8, x: 0, y: 2)
                .offset(x: 6, y: 6)
        }
        .frame(width: 100, height: 120)
    }

    private var cardContentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(displayTitle ?? gradeDescription)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.32))
                    .padding(.top, 2)
            }

            if displayTitle != nil {
                Text(gradeDescription)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(gradeColor)
                    .padding(.top, 2)
            }

            Text(scan.gradeResult.summary)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.58))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .padding(.top, 8)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                Text(scan.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.weight(.semibold))
            }
            .foregroundColor(.white.opacity(0.42))
            .padding(.top, 8)
        }
        .padding(.leading, 2)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var gradeColor: Color {
        switch scan.gradeResult.grade.uppercased() {
        case "A": return Color.primaryGreen
        case "B": return Color(hex: "32C997")
        case "C": return Color.primaryBlue
        case "D": return Color.orange
        case "F": return Color.red
        default: return Color.white.opacity(0.52)
        }
    }

    private var gradeDescription: String {
        switch scan.gradeResult.grade.uppercased() {
        case "A": return "Excellent"
        case "B": return "Good"
        case "C": return "Moderate"
        case "D": return "Poor"
        case "F": return "Avoid"
        default: return "Unknown"
        }
    }
}

private struct MealScanCard: View {
    let meal: Meal
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onTap: () -> Void

    private var accent: Color {
        switch meal.entryMethod {
        case .photo: return ScanFeedAccent.photoMeal
        case .voice: return ScanFeedAccent.voiceMeal
        case .text, .unknown: return ScanFeedAccent.textMeal
        }
    }

    private var methodBadge: (String, String) {
        switch meal.entryMethod {
        case .photo: return ("Photo", "camera.fill")
        case .voice: return ("Voice", "waveform")
        case .text: return ("Note", "text.alignleft")
        case .unknown: return ("Meal", "fork.knife")
        }
    }

    private var hasImage: Bool {
        !meal.image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                imageHeader
                statsFooter
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(accent.opacity(0.30), lineWidth: 1)
            )
            .shadow(color: accent.opacity(0.18), radius: 20, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.28), radius: 26, x: 0, y: 18)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                PinToggleBadge(isPinned: isPinned, action: onTogglePin)
                    .padding(12)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTogglePin()
            } label: {
                Label(isPinned ? "Unpin meal" : "Pin meal", systemImage: isPinned ? "pin.slash" : "pin.fill")
            }
        }
    }

    @ViewBuilder
    private var imageHeader: some View {
        ZStack(alignment: .topLeading) {
            if hasImage {
                RemoteImage(url: meal.image)
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                placeholderHeader
            }

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)

            VStack {
                HStack {
                    methodChip
                    Spacer()
                    timeChip(meal.createdAt)
                }
                Spacer()
                HStack {
                    Text(meal.name.isEmpty ? "Meal" : meal.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.5), radius: 6, y: 2)
                        .lineLimit(2)
                    Spacer()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: 180, alignment: .topLeading)
        }
        .frame(height: 180)
    }

    private var placeholderHeader: some View {
        ZStack {
            LinearGradient(
                colors: [
                    accent.opacity(0.32),
                    Color.black.opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 180)

            Circle()
                .fill(accent.opacity(0.22))
                .frame(width: 180, height: 180)
                .blur(radius: 50)
                .offset(x: -40, y: -30)

            Image(systemName: placeholderIcon)
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .shadow(color: accent.opacity(0.5), radius: 20, y: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    private var placeholderIcon: String {
        switch meal.entryMethod {
        case .photo: return "photo.fill"
        case .voice: return "waveform"
        case .text, .unknown: return "fork.knife"
        }
    }

    private var methodChip: some View {
        HStack(spacing: 5) {
            Image(systemName: methodBadge.1)
                .font(.system(size: 10, weight: .semibold))
            Text(methodBadge.0.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
        }
        .foregroundColor(accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(accent.opacity(0.55), lineWidth: 1))
    }

    private func timeChip(_ date: Date) -> some View {
        Text(relativeTime(from: date))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    private var statsFooter: some View {
        HStack(spacing: 0) {
            statColumn(label: "KCAL", value: "\(meal.calories)", color: .white)
            divider
            statColumn(label: "P", value: "\(meal.protein)g", color: Color(hex: "60A5FA"))
            divider
            statColumn(label: "C", value: "\(meal.carbs)g", color: Color.primaryGreen)
            divider
            statColumn(label: "F", value: "\(meal.fat)g", color: Color(hex: "FFB454"))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
    }

    private func statColumn(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(color.opacity(0.75))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct LabelScanFeedCard: View {
    let label: MacraScannedLabel
    let onTap: () -> Void

    private var accent: Color { ScanFeedAccent.labelScan }

    private var gradeColor: Color {
        switch label.gradeResult.grade.uppercased() {
        case "A": return Color(hex: "18BE53")
        case "B": return Color(hex: "32C997")
        case "C": return Color(hex: "FFAD30")
        case "D": return Color(hex: "FF8A5C")
        case "F": return Color(hex: "EF4444")
        default: return Color.white.opacity(0.5)
        }
    }

    private var title: String {
        if let product = label.productTitle, !product.isEmpty { return product }
        if let gradeProduct = label.gradeResult.productTitle, !gradeProduct.isEmpty { return gradeProduct }
        return "Scanned label"
    }

    private var hasImage: Bool {
        if let url = label.imageURL, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                thumbnail

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "barcode")
                            .font(.system(size: 10, weight: .semibold))
                        Text("LABEL SCAN")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                    }
                    .foregroundColor(accent)

                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(label.gradeResult.summary)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(relativeTime(from: label.createdAt))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(accent.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: accent.opacity(0.14), radius: 16, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.24), radius: 22, x: 0, y: 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let url = label.imageURL, !url.isEmpty {
                    RemoteImage(url: url)
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [
                                accent.opacity(0.32),
                                Color.black.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                    }
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )

            gradeBadge
                .offset(x: 4, y: 4)
        }
    }

    private var gradeBadge: some View {
        Text(label.gradeResult.grade.uppercased())
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundColor(.black)
            .frame(width: 30, height: 30)
            .background(Circle().fill(gradeColor))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            .shadow(color: gradeColor.opacity(0.6), radius: 8, y: 2)
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Copy Day CTA

private struct HomeDailyInsightCard: View {
    let insight: MacraFoodJournalDailyInsight?
    let isGenerating: Bool
    let errorMessage: String?
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: insight?.icon ?? "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primaryGreen)
                Text(insight?.title ?? "Daily insight")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if let insight {
                    Text(insight.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }

            if let insight {
                if let badge = insight.typeBadge {
                    Text(badge.label.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.primaryGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.primaryGreen.opacity(0.12))
                        )
                        .overlay(
                            Capsule().strokeBorder(Color.primaryGreen.opacity(0.35), lineWidth: 1)
                        )
                }
                if let points = insight.points, !points.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color.primaryGreen)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 7)
                                Text(point)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(2)
                            }
                        }
                    }
                } else {
                    Text(insight.response)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                }
                if let action = insight.action, !action.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.primaryGreen)
                            .padding(.top, 1)
                        Text(action)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primaryGreen.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primaryGreen.opacity(0.25), lineWidth: 1)
                    )
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button {
                        onGenerate()
                    } label: {
                        Label(isGenerating ? "Regenerating…" : "Regenerate", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primaryGreen)
                    }
                    .disabled(isGenerating)
                }
            } else if isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.primaryGreen)
                    Text("Nora is reading your day…")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            } else {
                Text("See what Nora notices about today's meals — protein cadence, fiber density, macro balance, or what's missing.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
                Button {
                    onGenerate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                        Text("Generate insight")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.primaryGreen))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color(hex: "F87171"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primaryGreen.opacity(0.24), lineWidth: 1)
        )
    }
}

private struct HomeNetCarbChip: View {
    let netCarbs: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "60A5FA"))
            Text("Net carbs: \(netCarbs)g")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer()
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "60A5FA").opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(hex: "60A5FA").opacity(0.28), lineWidth: 1)
        )
    }
}

private struct HomeFullNutritionCard: View {
    private let macraBlue = Color(hex: "3B82F6")

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(macraBlue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Full nutrition")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("Sugars, fiber, sodium, vitamins & more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(macraBlue.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(macraBlue.opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - Full Nutrition Sheet

private struct MacraFullNutritionSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    private let macraBlue = Color(hex: "3B82F6")

    private enum RowKind {
        /// Standard nutrient row: name on left, big blue value + unit on right.
        case nutrient
        /// Supplement breakdown row: name + dosage on left, small descriptive
        /// macro summary on right (no unit, normal weight).
        case supplement(subtitle: String?)
    }

    private struct Row: Identifiable {
        let id = UUID()
        let name: String
        let value: String
        let unit: String?
        /// >0 means a supplement contributed to this row; rendered as a +X badge.
        let supplementContribution: Int
        /// Optional pre-net value rendered with a strikethrough next to `value`.
        /// Used for carbs to show "186 (struck) 144 g net" when fiber/sugar
        /// alcohols pull net carbs below total carbs.
        let crossedOutValue: String?
        /// Suffix label rendered after `unit` (e.g. "net"). Tiny accent.
        let trailingLabel: String?
        let kind: RowKind

        init(
            name: String,
            value: String,
            unit: String?,
            supplementContribution: Int,
            crossedOutValue: String? = nil,
            trailingLabel: String? = nil,
            kind: RowKind = .nutrient
        ) {
            self.name = name
            self.value = value
            self.unit = unit
            self.supplementContribution = supplementContribution
            self.crossedOutValue = crossedOutValue
            self.trailingLabel = trailingLabel
            self.kind = kind
        }
    }

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let rows: [Row]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "0B1220").ignoresSafeArea())
            .navigationTitle("Full nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FOR \(dateLabel.uppercased())")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(macraBlue)
            Text("Daily nutrition breakdown")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Aggregated across \(viewModel.todaysMeals.count) meal\(viewModel.todaysMeals.count == 1 ? "" : "s") and \(viewModel.loggedSupplements.count) supplement\(viewModel.loggedSupplements.count == 1 ? "" : "s") logged today.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(macraBlue.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(macraBlue.opacity(0.28), lineWidth: 1)
        )
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(viewModel.selectedDate) { return "Today" }
        if cal.isDateInYesterday(viewModel.selectedDate) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: viewModel.selectedDate)
    }

    private var sections: [Section] {
        var output: [Section] = []

        // Daily totals (always show — these are the macros).
        // Carbs row collapses fiber/sugar-alcohol adjustments inline:
        // "186 (struck) 144 g net" instead of a separate Net Carbs row below.
        let carbsRow: Row = {
            if viewModel.hasNetCarbAdjustment, viewModel.totalNetCarbs != viewModel.totalCarbs {
                return Row(
                    name: "Total Carbohydrates",
                    value: "\(viewModel.totalNetCarbs)",
                    unit: "g",
                    supplementContribution: viewModel.supplementCarbs,
                    crossedOutValue: "\(viewModel.totalCarbs)",
                    trailingLabel: "net"
                )
            }
            return Row(
                name: "Total Carbohydrates",
                value: "\(viewModel.totalCarbs)",
                unit: "g",
                supplementContribution: viewModel.supplementCarbs
            )
        }()

        output.append(
            Section(
                title: "Daily totals",
                subtitle: "Calories and macros",
                rows: [
                    Row(name: "Total Calories", value: "\(viewModel.totalCalories)", unit: "kcal", supplementContribution: viewModel.supplementCalories),
                    Row(name: "Total Protein", value: "\(viewModel.totalProtein)", unit: "g", supplementContribution: viewModel.supplementProtein),
                    carbsRow,
                    Row(name: "Total Fat", value: "\(viewModel.totalFat)", unit: "g", supplementContribution: viewModel.supplementFat)
                ]
            )
        )

        // Supplements breakdown — itemizes what each logged supplement
        // contributed today, mirroring FWP's "supplement boosts the daily
        // table" behavior. Section only renders when at least one supplement
        // is logged. Inline +X badges on macros/vitamins/minerals stay where
        // they are; this section is the explicit ledger.
        if !viewModel.loggedSupplements.isEmpty {
            let suppRows: [Row] = viewModel.loggedSupplements.map { supp in
                let macroBits: [String] = {
                    var bits: [String] = []
                    if supp.calories > 0 { bits.append("\(supp.calories) kcal") }
                    if supp.protein > 0 { bits.append("\(supp.protein)P") }
                    if supp.carbs > 0 { bits.append("\(supp.carbs)C") }
                    if supp.fat > 0 { bits.append("\(supp.fat)F") }
                    return bits
                }()
                let vitMineralCount = (supp.vitamins?.count ?? 0) + (supp.minerals?.count ?? 0)
                let contributionSummary: String = {
                    if !macroBits.isEmpty {
                        return macroBits.joined(separator: " · ")
                    }
                    if vitMineralCount > 0 {
                        return "\(vitMineralCount) micronutrient\(vitMineralCount == 1 ? "" : "s")"
                    }
                    return "logged"
                }()
                let totalContribution = supp.calories + supp.protein + supp.carbs + supp.fat
                return Row(
                    name: supp.name,
                    value: contributionSummary,
                    unit: nil,
                    supplementContribution: totalContribution,
                    kind: .supplement(subtitle: supp.dosageDescription)
                )
            }
            output.append(
                Section(
                    title: "Supplements",
                    subtitle: "What each supplement added today",
                    rows: suppRows
                )
            )
        }

        // Additional nutrients section — only rows that actually have data.
        // (Net Carbs no longer gets its own row; it's inlined into the carbs
        // row above.)
        var extras: [Row] = []
        if viewModel.totalDietaryFiber > 0 {
            extras.append(Row(name: "Total Dietary Fiber", value: "\(viewModel.totalDietaryFiber)", unit: "g", supplementContribution: 0))
        }
        if viewModel.totalSugars > 0 {
            extras.append(Row(name: "Total Sugars", value: "\(viewModel.totalSugars)", unit: "g", supplementContribution: 0))
        }
        if viewModel.totalSugarAlcohols > 0 {
            extras.append(Row(name: "Sugar Alcohols", value: "\(viewModel.totalSugarAlcohols)", unit: "g", supplementContribution: 0))
        }
        if viewModel.totalSodium > 0 {
            extras.append(Row(name: "Total Sodium", value: "\(viewModel.totalSodium)", unit: "mg", supplementContribution: 0))
        }
        if viewModel.totalCholesterol > 0 {
            extras.append(Row(name: "Total Cholesterol", value: "\(viewModel.totalCholesterol)", unit: "mg", supplementContribution: 0))
        }
        if viewModel.totalSaturatedFat > 0 {
            extras.append(Row(name: "Total Saturated Fat", value: "\(viewModel.totalSaturatedFat)", unit: "g", supplementContribution: 0))
        }
        if viewModel.totalUnsaturatedFat > 0 {
            extras.append(Row(name: "Total Unsaturated Fat", value: "\(viewModel.totalUnsaturatedFat)", unit: "g", supplementContribution: 0))
        }
        if !extras.isEmpty {
            output.append(Section(title: "Other nutrients", subtitle: "Beyond the core macros", rows: extras))
        }

        // Vitamins (meals + supplements merged, supplements tracked for badge).
        let vitaminRows = mergedRows(meals: viewModel.mealVitamins, supplements: viewModel.supplementVitamins, unit: "mg")
        if !vitaminRows.isEmpty {
            output.append(Section(title: "Vitamins", subtitle: "Aggregated across meals & supplements", rows: vitaminRows))
        }

        // Minerals.
        let mineralRows = mergedRows(meals: viewModel.mealMinerals, supplements: viewModel.supplementMinerals, unit: "mg")
        if !mineralRows.isEmpty {
            output.append(Section(title: "Minerals", subtitle: "Aggregated across meals & supplements", rows: mineralRows))
        }

        return output
    }

    /// Produces sorted rows that combine meal + supplement values for the same
    /// nutrient, with the supplement-contribution payload preserved so the
    /// row UI can show a "+X" badge next to anything supplements added to.
    private func mergedRows(meals: [String: Int], supplements: [String: Int], unit: String) -> [Row] {
        let allKeys = Set(meals.keys).union(supplements.keys)
        return allKeys
            .sorted()
            .compactMap { key in
                let mealValue = meals[key] ?? 0
                let suppValue = supplements[key] ?? 0
                let total = mealValue + suppValue
                guard total > 0 else { return nil }
                return Row(name: key, value: "\(total)", unit: unit, supplementContribution: suppValue)
            }
    }

    @ViewBuilder
    private func sectionView(_ section: Section) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(macraBlue)
                    Text(section.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer()
                if section.rows.contains(where: { $0.supplementContribution > 0 }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.purple)
                        Text("Supplement enhanced")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.purple.opacity(0.9))
                            .tracking(0.3)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.purple.opacity(0.14)))
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row)
                    if index < section.rows.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(macraBlue.opacity(0.18), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row.kind {
        case .nutrient:
            nutrientRow(row)
        case .supplement(let subtitle):
            supplementRow(row, subtitle: subtitle)
        }
    }

    @ViewBuilder
    private func nutrientRow(_ row: Row) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                if row.supplementContribution > 0 {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 5, height: 5)
                }
                Text(row.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.88))
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let crossed = row.crossedOutValue {
                    Text(crossed)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .strikethrough(true, color: Color.white.opacity(0.45))
                        .monospacedDigit()
                }
                Text(row.value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(macraBlue)
                    .monospacedDigit()
                if let unit = row.unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                if let label = row.trailingLabel {
                    Text(label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(macraBlue.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(macraBlue.opacity(0.16)))
                }
                if row.supplementContribution > 0 {
                    Text("+\(row.supplementContribution)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.purple.opacity(0.14)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func supplementRow(_ row: Row, subtitle: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "pills.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.purple.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.purple)
                    .multilineTextAlignment(.trailing)
                Text("ADDED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.purple.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct CopyDayCTA: View {
    let mealCount: Int

    private var title: String {
        let noun = mealCount == 1 ? "meal" : "meals"
        return "Copy these \(mealCount) \(noun) to…"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primaryGreen)

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.primaryGreen)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primaryGreen.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primaryGreen.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Log Meal CTA

private struct LogMealCTA: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22, weight: .semibold))

            Text("Log a meal")
                .font(.system(size: 17, weight: .bold, design: .rounded))

            Spacer()

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(Color(hex: "0B0C10"))
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.primaryGreen, Color(hex: "C5EA17")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.primaryGreen.opacity(0.28), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Meal Row + Empty State

private struct MealRow: View {
    let meal: Meal

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            mealThumbnail
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name.isEmpty ? "Meal" : meal.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(Self.timeFormatter.string(from: meal.createdAt))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(meal.calories) kcal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                macroLine
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var mealThumbnail: some View {
        if !meal.image.isEmpty, let url = URL(string: meal.image) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primaryGreen.opacity(0.16))
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.primaryGreen)
            )
    }

    private var macroLine: Text {
        let prefix = Text("P \(meal.protein) · C ")
        let suffix = Text(" · F \(meal.fat)")
        if meal.hasNetCarbAdjustment, meal.netCarbs != meal.carbs {
            let original = Text("\(meal.carbs)")
                .strikethrough(true, color: Color.white.opacity(0.45))
                .foregroundColor(Color.white.opacity(0.4))
            let net = Text(" \(meal.netCarbs)")
                .foregroundColor(Color.primaryGreen)
            return prefix + original + net + suffix
        } else {
            return prefix + Text("\(meal.carbs)") + suffix
        }
    }
}

private struct EmptyMealsState: View {
    let dayLabel: String

    private var emptyTitle: String {
        switch dayLabel {
        case "Today": return "No meals yet today"
        case "Yesterday": return "No meals logged yesterday"
        case "Tomorrow": return "No meals planned for tomorrow"
        default: return "No meals on \(dayLabel)"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color.primaryGreen.opacity(0.75))

            Text(emptyTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Tap **Log a meal** above to add your first entry.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Destination router

private struct NutritionDestinationView: View {
    let destination: AppCoordinator.NutritionShellDestination
    let appCoordinator: AppCoordinator
    let serviceManager: ServiceManager
    let onClose: () -> Void

    var body: some View {
        destinationContent
            .background(Color(.systemBackground))
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: onClose)
            }
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .mealPlanning:
            if let userId = serviceManager.userService.user?.id ?? Auth.auth().currentUser?.uid {
                MealPlanningRootView(userId: userId)
            } else {
                NutritionRequiresAccountView(message: "Sign in to build meal plans that sync with your nutrition profile.")
            }
        case .macroTargets:
            if let userId = serviceManager.userService.user?.id ?? Auth.auth().currentUser?.uid {
                NutritionMacroTargetsRouteView(userId: userId)
            } else {
                NutritionRequiresAccountView(message: "Sign in to save macro targets and recommendation history.")
            }
        case .supplementTracker:
            NutritionSupplementTrackerRouteView()
        case .mealHistory:
            MacraFoodJournalMealHistoryRouteView()
        case .insights:
            MacraNutritionInsightsRootView()
        case .settings:
            NutritionSettingsRouteView(appCoordinator: appCoordinator)
        }
    }
}

// MARK: - Tab bar

private struct NutritionShellTabBar: View {
    @Binding var selectedTab: AppCoordinator.NutritionShellTab
    let coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppCoordinator.NutritionShellTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.primaryGreen : Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selectedTab == tab ? Color.primaryGreen.opacity(0.14) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onChange(of: selectedTab) { newValue in
            coordinator.nutritionShellTab = newValue
        }
    }
}

// MARK: - Shared helpers

private struct NutritionSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.14)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct ProfileAvatarView: View {
    let imageURL: String
    let fallbackText: String

    private var initials: String {
        let base = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = base.first else { return "" }
        return String(first).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.primaryGreen, Color.secondaryWhite.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RemoteImage(url: imageURL)
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
            } else if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primaryPurple)
            } else {
                Text(initials)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.primaryPurple)
            }
        }
        .frame(width: 42, height: 42)
        .overlay(
            Circle()
                .strokeBorder(Color.secondaryWhite.opacity(0.78), lineWidth: 2)
        )
        .shadow(color: Color.secondaryCharcoal.opacity(0.22), radius: 12, x: 0, y: 8)
    }
}

private struct ProfileSummaryCard: View {
    let user: User?
    let isSubscribed: Bool
    let action: () -> Void

    private var email: String {
        let value = user?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Macra profile" : value
    }

    private var planText: String {
        isSubscribed ? "Macra Plus active" : "Free plan"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ProfileAvatarView(
                    imageURL: user?.profileImageURL ?? "",
                    fallbackText: email
                )
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Profile")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.secondaryWhite)

                    Text(email)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.secondaryWhite.opacity(0.76))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(planText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.primaryGreen)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.secondaryWhite.opacity(0.55))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.secondaryWhite.opacity(0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.secondaryWhite.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ShellCTAButton: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(Color(hex: "0B0C10"))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color.primaryGreen, Color(hex: "C5EA17")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.primaryGreen.opacity(0.25), radius: 14, x: 0, y: 8)
    }
}

private struct MacraHealthKitToggleRow: View {
    @State private var isOn: Bool = MacraHealthKitService.shared.userOptIn
    @State private var authErrorMessage: String?
    @State private var isRequesting: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: "F87171"))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(hex: "F87171").opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Sync meals to Apple Health")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.primaryGreen)
                .disabled(isRequesting || !MacraHealthKitService.shared.isAvailable)
                .onChange(of: isOn) { newValue in
                    handleToggle(newValue)
                }
        }
        .padding(.vertical, 10)
    }

    private var subtitleText: String {
        if !MacraHealthKitService.shared.isAvailable {
            return "HealthKit isn't available on this device."
        }
        if let authErrorMessage {
            return authErrorMessage
        }
        return "Write dietary energy, protein, carbs, fat, and fiber when you log a meal."
    }

    private func handleToggle(_ newValue: Bool) {
        guard MacraHealthKitService.shared.isAvailable else {
            isOn = false
            return
        }
        if newValue {
            isRequesting = true
            authErrorMessage = nil
            MacraHealthKitService.shared.requestAuthorization { granted, error in
                isRequesting = false
                if let error {
                    authErrorMessage = error.localizedDescription
                    isOn = false
                    MacraHealthKitService.shared.userOptIn = false
                } else if granted {
                    MacraHealthKitService.shared.userOptIn = true
                } else {
                    authErrorMessage = "Enable Macra in Health app → Sources to sync."
                    isOn = false
                    MacraHealthKitService.shared.userOptIn = false
                }
            }
        } else {
            MacraHealthKitService.shared.userOptIn = false
        }
    }
}

private struct MoreRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primaryGreen)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primaryGreen.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.vertical, 10)
    }
}

private struct MacraDayPickerSheet: View {
    @Binding var selectedDate: Date
    let confirmTitle: String
    let onDone: () -> Void

    @State private var workingDate: Date
    @State private var displayedMonth: Date
    @State private var loggedDates: Set<Date> = []

    private let calendar = Calendar.current

    init(selectedDate: Binding<Date>, confirmTitle: String = "Done", onDone: @escaping () -> Void) {
        self._selectedDate = selectedDate
        self.confirmTitle = confirmTitle
        self.onDone = onDone
        let initial = selectedDate.wrappedValue
        self._workingDate = State(initialValue: initial)
        let monthStart = Calendar.current.dateInterval(of: .month, for: initial)?.start ?? initial
        self._displayedMonth = State(initialValue: monthStart)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                monthHeader
                weekdayHeader
                daysGrid

                if !calendar.isDateInToday(workingDate) {
                    HStack(spacing: 12) {
                        Button {
                            let today = calendar.startOfDay(for: Date())
                            workingDate = today
                            selectedDate = today
                            let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
                            if monthStart != displayedMonth {
                                displayedMonth = monthStart
                                loadLoggedDates()
                            }
                        } label: {
                            Text("Jump to today")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.primaryGreen)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.primaryGreen.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primaryGreen.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .background(Color.secondaryCharcoal.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationTitle("Pick a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, action: onDone)
                        .tint(Color.primaryGreen)
                }
            }
            .onAppear(perform: loadLoggedDates)
        }
    }

    // MARK: Month header

    private var monthHeader: some View {
        HStack {
            Text(monthTitle(displayedMonth))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Button {
                stepMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.primaryGreen)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primaryGreen.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Button {
                stepMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(canStepForward ? Color.primaryGreen : Color.white.opacity(0.25))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primaryGreen.opacity(canStepForward ? 0.12 : 0.04)))
            }
            .buttonStyle(.plain)
            .disabled(!canStepForward)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Grid

    private var daysGrid: some View {
        let cells = monthCells(for: displayedMonth)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(cells) { cell in
                dayCell(cell)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ cell: DayCell) -> some View {
        if let date = cell.date {
            let isSelected = calendar.isDate(date, inSameDayAs: workingDate)
            let isToday = calendar.isDateInToday(date)
            let isFuture = date > calendar.startOfDay(for: Date())
            let hasLog = loggedDates.contains(calendar.startOfDay(for: date))
            let day = calendar.component(.day, from: date)

            Button {
                guard !isFuture else { return }
                workingDate = date
                selectedDate = date
            } label: {
                VStack(spacing: 3) {
                    Text("\(day)")
                        .font(.system(size: 16, weight: isSelected || isToday ? .bold : .semibold, design: .rounded))
                        .foregroundColor(textColor(isSelected: isSelected, isToday: isToday, isFuture: isFuture))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(isSelected ? Color.primaryGreen : (isToday ? Color.primaryGreen.opacity(0.15) : Color.clear))
                        )

                    Circle()
                        .fill(hasLog ? (isSelected ? Color.black.opacity(0.85) : Color.primaryGreen) : Color.clear)
                        .frame(width: 5, height: 5)
                        .opacity(isFuture ? 0 : 1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isFuture)
        } else {
            Color.clear.frame(height: 44)
        }
    }

    private func textColor(isSelected: Bool, isToday: Bool, isFuture: Bool) -> Color {
        if isSelected { return .black }
        if isFuture { return Color.white.opacity(0.22) }
        if isToday { return Color.primaryGreen }
        return .white
    }

    // MARK: Data

    private func loadLoggedDates() {
        MealService.sharedInstance.getLoggedDates(inMonth: displayedMonth) { result in
            DispatchQueue.main.async {
                if case .success(let dates) = result {
                    loggedDates = dates
                }
            }
        }
    }

    private func stepMonth(by delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        let monthStart = calendar.dateInterval(of: .month, for: next)?.start ?? next
        let todayMonthStart = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        guard monthStart <= todayMonthStart else { return }
        displayedMonth = monthStart
        loadLoggedDates()
    }

    private var canStepForward: Bool {
        let todayMonthStart = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return displayedMonth < todayMonthStart
    }

    // MARK: Helpers

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date)
    }

    private var weekdaySymbols: [String] {
        let f = DateFormatter()
        f.calendar = calendar
        let symbols = f.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let firstWeekday = calendar.firstWeekday - 1
        let rotated = Array(symbols[firstWeekday...] + symbols[..<firstWeekday])
        return rotated.map { $0.uppercased() }
    }

    private func monthCells(for month: Date) -> [DayCell] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstOfMonth = interval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

        let firstWeekdayIndex = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (firstWeekdayIndex - calendar.firstWeekday + 7) % 7

        var cells: [DayCell] = []
        for _ in 0..<leadingBlanks {
            cells.append(DayCell(id: UUID().uuidString, date: nil))
        }
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(DayCell(id: ISO8601DateFormatter().string(from: date), date: date))
            }
        }
        let trailing = (7 - (cells.count % 7)) % 7
        for _ in 0..<trailing {
            cells.append(DayCell(id: UUID().uuidString, date: nil))
        }
        return cells
    }

    private struct DayCell: Identifiable {
        let id: String
        let date: Date?
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(viewModel: HomeViewModel(appCoordinator: AppCoordinator(serviceManager: ServiceManager()), serviceManager: ServiceManager()))
    }
}
