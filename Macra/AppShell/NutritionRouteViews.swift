import SwiftUI
import FirebaseAuth

struct NutritionMacroTargetsRouteView: View {
    @StateObject private var viewModel: MacroTargetsViewModel

    init(userId: String, store: any MealPlanningStore = FirestoreMealPlanningStore()) {
        _viewModel = StateObject(wrappedValue: MacroTargetsViewModel(userId: userId, store: store))
    }

    var body: some View {
        ScrollView {
            MacroTargetsView(viewModel: viewModel)
                .padding(20)
        }
        .background(
            LinearGradient(
                colors: [Color.black, Color.secondaryCharcoal, Color.blueGray.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .onAppear {
            viewModel.load()
        }
    }
}

@MainActor
final class NutritionSupplementTrackerViewModel: ObservableObject {
    @Published var savedSupplements: [LoggedSupplement] = []
    @Published var loggedForSelectedDate: [LoggedSupplement] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    func setSelectedDate(_ date: Date) {
        let normalized = Calendar.current.startOfDay(for: date)
        guard !Calendar.current.isDate(normalized, inSameDayAs: selectedDate) else { return }
        selectedDate = normalized
        loggedForSelectedDate = []
        load()
    }

    func load() {
        guard Auth.auth().currentUser?.uid != nil else {
            errorMessage = "Sign in to manage supplements."
            return
        }

        isLoading = true
        let dateForQuery = selectedDate
        let group = DispatchGroup()

        group.enter()
        SupplementService.sharedInstance.getSavedSupplements { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let supplements):
                    self?.savedSupplements = supplements
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
                group.leave()
            }
        }

        group.enter()
        SupplementService.sharedInstance.getLoggedSupplements(byDate: dateForQuery) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { group.leave(); return }
                // Drop the response if the user has navigated to another day mid-flight.
                guard Calendar.current.isDate(self.selectedDate, inSameDayAs: dateForQuery) else {
                    group.leave()
                    return
                }
                switch result {
                case .success(let supplements):
                    // Defensive client-side filter: only keep entries whose createdAt
                    // actually falls on the queried day. Guards against legacy logs
                    // whose createdAt was written without day-normalization.
                    self.loggedForSelectedDate = supplements.filter {
                        Calendar.current.isDate($0.createdAt, inSameDayAs: dateForQuery)
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
        }
    }

    func saveToLibrary(_ supplement: LoggedSupplement) {
        SupplementService.sharedInstance.saveSupplementToLibrary(supplement) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    if let existingIndex = self?.savedSupplements.firstIndex(where: { $0.libraryIdentityKey == supplement.libraryIdentityKey }) {
                        self?.savedSupplements[existingIndex] = supplement
                    } else if self?.savedSupplements.contains(where: { $0.id == supplement.id }) == false {
                        self?.savedSupplements.insert(supplement, at: 0)
                    }
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func toggleLogged(_ supplement: LoggedSupplement) {
        let dateForToggle = selectedDate
        if let existing = loggedForSelectedDate.first(where: {
            $0.name == supplement.name && Calendar.current.isDate($0.createdAt, inSameDayAs: dateForToggle)
        }) {
            SupplementService.sharedInstance.deleteLoggedSupplement(withId: existing.id) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.loggedForSelectedDate.removeAll { $0.id == existing.id }
                    case .failure(let error):
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
            return
        }

        var logged = supplement
        logged.id = generateUniqueID(prefix: "supplement")
        logged.createdAt = dateForToggle
        logged.updatedAt = Date()

        SupplementService.sharedInstance.addLoggedSupplement(logged, date: dateForToggle) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                // If the user navigated away from the day they tapped, don't pollute
                // the new day's view with the entry that belongs to the old day.
                guard Calendar.current.isDate(self.selectedDate, inSameDayAs: dateForToggle) else { return }
                switch result {
                case .success:
                    var displaySupplement = logged
                    displaySupplement.id = "\(dateForToggle.dayMonthYearFormat)\(logged.id)"
                    self.loggedForSelectedDate.append(displaySupplement)
                    self.loggedForSelectedDate.sort { $0.createdAt < $1.createdAt }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func isLoggedOnSelectedDate(_ supplement: LoggedSupplement) -> Bool {
        loggedForSelectedDate.contains {
            $0.name == supplement.name && Calendar.current.isDate($0.createdAt, inSameDayAs: selectedDate)
        }
    }
}

struct NutritionSupplementTrackerRouteView: View {
    @StateObject private var viewModel = NutritionSupplementTrackerViewModel()
    @State private var isAddingSupplement = false

    var body: some View {
        ScrollView {
            NutritionSupplementTrackerContentView(
                viewModel: viewModel,
                showsHeader: true,
                onAddSupplement: { isAddingSupplement = true }
            )
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [Color.black, Color.secondaryCharcoal, Color.blueGray.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .onAppear {
            viewModel.load()
        }
        .sheet(isPresented: $isAddingSupplement) {
            NutritionSupplementEditorView { supplement in
                viewModel.saveToLibrary(supplement)
            }
        }
    }
}

struct NutritionSupplementTrackerContentView: View {
    @ObservedObject var viewModel: NutritionSupplementTrackerViewModel
    var showsHeader = false
    let onAddSupplement: () -> Void

    private let greenAccent = Color(hex: "E0FE10")
    private let blueAccent = Color(hex: "3B82F6")
    private let purpleAccent = Color(hex: "8B5CF6")
    private let redAccent = Color(hex: "EF4444")

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if showsHeader {
                headerCard
            }

            titleRow

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(greenAccent)
                        .padding(.vertical, 14)
                    Spacer()
                }
            }

            if let errorMessage = viewModel.errorMessage {
                SupplementErrorCard(message: errorMessage)
            }

            todaySection
            librarySection
        }
    }

    private var headerCard: some View {
        SupplementHeroCard()
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SUPPLEMENTS")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(greenAccent)

                Text("Your stack")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundColor(.white)

                Text("Tap a supplement to log or unlog it for \(relativeDayLabel.lowercased()).")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(action: onAddSupplement) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add new")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(greenAccent))
                .shadow(color: greenAccent.opacity(0.45), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add new supplement")
            .padding(.top, 18)
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                label: "LOGGED \(relativeDayLabel.uppercased())",
                count: viewModel.loggedForSelectedDate.count,
                accent: blueAccent
            )

            if viewModel.loggedForSelectedDate.isEmpty {
                SupplementEmptyCard(
                    title: "Nothing logged yet",
                    subtitle: "Your supplement entries for \(relativeDayLabel.lowercased()) will appear here.",
                    systemImage: "calendar.badge.plus",
                    accent: blueAccent
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.loggedForSelectedDate) { supplement in
                        NutritionSupplementRow(supplement: supplement, isLogged: true) {
                            viewModel.toggleLogged(supplement)
                        }
                    }
                }
            }
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                label: "YOUR SUPPLEMENTS",
                count: viewModel.savedSupplements.count,
                accent: purpleAccent
            )

            if viewModel.savedSupplements.isEmpty {
                SupplementEmptyCard(
                    title: "No supplements yet",
                    subtitle: "Add the supplements you actually use, then log them from this tab.",
                    systemImage: "sparkles",
                    accent: purpleAccent
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.savedSupplements) { supplement in
                        NutritionSupplementRow(
                            supplement: supplement,
                            isLogged: viewModel.isLoggedOnSelectedDate(supplement)
                        ) {
                            viewModel.toggleLogged(supplement)
                        }
                    }
                }
            }
        }
    }

    private var relativeDayLabel: String {
        let calendar = Calendar.current
        let date = viewModel.selectedDate
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    private func sectionHeader(label: String, count: Int, accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(accent)

            Spacer()

            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(accent.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.12)))
                .overlay(Capsule().strokeBorder(accent.opacity(0.32), lineWidth: 1))
        }
    }
}

private struct SupplementHeroCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "E0FE10").opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "pills.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(hex: "E0FE10"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SUPPLEMENT TRACKER")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(Color(hex: "E0FE10"))

                Text("Track today's fuel")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Quick-log your stack and keep nutrient contributions visible alongside your macros.")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(hex: "E0FE10").opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color(hex: "E0FE10").opacity(0.45), Color(hex: "E0FE10").opacity(0.12), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color(hex: "E0FE10").opacity(0.18), radius: 20, x: 0, y: 10)
        )
    }
}

private struct SupplementEmptyCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: accent.opacity(0.12), radius: 14, x: 0, y: 8)
        )
    }
}

private struct SupplementErrorCard: View {
    let message: String
    private let accent = Color(hex: "EF4444")

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Supplement sync")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.32), lineWidth: 1)
                )
        )
    }
}

struct NutritionSupplementEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (LoggedSupplement) -> Void

    @State private var name = ""
    @State private var form = "capsule"
    @State private var dosageString = "1"
    @State private var unit = "capsule(s)"
    @State private var brand = ""
    @State private var notes = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    private let formOptions = ["capsule", "tablet", "powder", "softgel", "liquid", "other"]
    private let unitOptions = ["capsule(s)", "tablet(s)", "scoop(s)", "mg", "g", "mcg", "IU", "mL", "drop(s)"]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color.secondaryCharcoal, Color.blueGray.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        editorHeader
                        basicInfoSection
                        nutritionSection
                        saveButton
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Add supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.white.opacity(0.78))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var editorHeader: some View {
        NutritionInfoCard(
            title: "New supplement",
            subtitle: "Add the exact supplement you take so it can be quick-logged into today.",
            systemImage: "pills.circle.fill",
            accent: .primaryGreen
        )
    }

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            editorSectionTitle("Supplement info")

            NutritionSupplementTextField(title: "Name", placeholder: "Vitamin D3 5000 IU", text: $name)

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Form")
                NutritionSupplementChipPicker(options: formOptions, selection: $form) { option in
                    HStack(spacing: 5) {
                        Image(systemName: formIcon(for: option))
                            .font(.caption2.weight(.semibold))
                        Text(option.capitalized)
                    }
                }
            }

            HStack(spacing: 12) {
                NutritionSupplementTextField(title: "Dose", placeholder: "1", text: $dosageString, keyboardType: .decimalPad)
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Unit")
                    Menu {
                        ForEach(unitOptions, id: \.self) { option in
                            Button(option) { unit = option }
                        }
                    } label: {
                        HStack {
                            Text(unit)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                    }
                }
            }

            NutritionSupplementTextField(title: "Brand", placeholder: "Optional", text: $brand)
            NutritionSupplementTextField(title: "Notes", placeholder: "Timing, instructions, etc.", text: $notes)
        }
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            editorSectionTitle("Nutrition contribution")

            HStack(spacing: 12) {
                NutritionSupplementTextField(title: "Calories", placeholder: "0", text: $calories, keyboardType: .numberPad)
                NutritionSupplementTextField(title: "Protein", placeholder: "0g", text: $protein, keyboardType: .numberPad)
            }

            HStack(spacing: 12) {
                NutritionSupplementTextField(title: "Carbs", placeholder: "0g", text: $carbs, keyboardType: .numberPad)
                NutritionSupplementTextField(title: "Fat", placeholder: "0g", text: $fat, keyboardType: .numberPad)
            }
        }
    }

    private var saveButton: some View {
        Button {
            var supplement = LoggedSupplement(
                id: generateUniqueID(prefix: "supplement"),
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                form: form,
                dosage: Double(dosageString) ?? 1,
                unit: unit,
                brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: Int(calories) ?? 0,
                protein: Int(protein) ?? 0,
                carbs: Int(carbs) ?? 0,
                fat: Int(fat) ?? 0
            )
            supplement.inferMicronutrients()
            onSave(supplement)
            dismiss()
        } label: {
            Text("Save supplement")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color(hex: "0B0C10"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(canSave ? Color.primaryGreen : Color.white.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    private func editorSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(Color.primaryGreen)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.65))
    }

    private func formIcon(for form: String) -> String {
        switch form.lowercased() {
        case "capsule": return "capsule.fill"
        case "tablet": return "pill.fill"
        case "powder": return "spoon"
        case "softgel": return "oval.fill"
        case "liquid": return "drop.fill"
        default: return "cross.case.fill"
        }
    }
}

private struct NutritionSupplementTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.65))

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NutritionSupplementChipPicker<Label: View>: View {
    let options: [String]
    @Binding var selection: String
    let label: (String) -> Label

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        label(option)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selection == option ? Color(hex: "0B0C10") : Color.white.opacity(0.82))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(selection == option ? Color.primaryGreen : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private extension LoggedSupplement {
    var libraryIdentityKey: String {
        [
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            brand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            form.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            dosage == dosage.rounded() ? String(Int(dosage)) : String(dosage),
            unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ].joined(separator: "|")
    }
}

struct NutritionRequiresAccountView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            NutritionInfoCard(
                title: "Account required",
                subtitle: message,
                systemImage: "person.crop.circle.badge.exclamationmark",
                accent: .lightBlue
            )
            Spacer()
        }
        .padding(20)
        .background(Color(.systemBackground))
    }
}

struct NutritionSettingsRouteView: View {
    let appCoordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NutritionInfoCard(
                    title: "Settings",
                    subtitle: "Account, subscription, and profile controls.",
                    systemImage: "gearshape.fill",
                    accent: .primaryGreen
                )

                Button {
                    appCoordinator.showSettingsModal()
                } label: {
                    Text("Open settings modal")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primaryGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.primaryPurple,
                    Color.secondaryPink.opacity(0.86),
                    Color.primaryBlue.opacity(0.70)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}

private struct NutritionInfoCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.secondaryCharcoal.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

private struct NutritionSupplementRow: View {
    let supplement: LoggedSupplement
    let isLogged: Bool
    let action: () -> Void

    private var accent: Color {
        // Rotate chromatic-glass category colors by supplement form so the list reads as a
        // colorful stack rather than all-green. Green stays the brand primary for CTAs.
        switch supplement.formIcon {
        case "capsule.fill", "capsule": return Color(hex: "06B6D4")  // cyan
        case "pill.fill", "pill": return Color(hex: "3B82F6")         // blue
        case "drop.fill", "drop": return Color(hex: "FFB454")         // amber
        case "powder": return Color(hex: "8B5CF6")                     // purple
        case "wineglass.fill", "wineglass": return Color(hex: "EF4444")// red
        default: return Color(hex: "E0FE10")                          // green fallback
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                iconBadge

                VStack(alignment: .leading, spacing: 5) {
                    Text(supplement.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)

                    if supplement.hasMacroContribution {
                        macroChipRow
                    }
                }

                Spacer(minLength: 6)

                logButton
            }
            .padding(14)
            .background(cardBackground)
            .overlay(cardBorder)
            .shadow(color: accent.opacity(isLogged ? 0.28 : 0.14), radius: isLogged ? 20 : 12, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.16))
                .frame(width: 46, height: 46)
            Circle()
                .strokeBorder(accent.opacity(0.34), lineWidth: 1)
                .frame(width: 46, height: 46)
            Image(systemName: supplement.formIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(accent)
        }
    }

    private var subtitle: String {
        let dosage = supplement.dosageDescription
        let brand = supplement.brand.isEmpty ? "Macra library" : supplement.brand
        return "\(dosage) · \(brand)"
    }

    private var macroChipRow: some View {
        HStack(spacing: 6) {
            macroChip(label: "\(supplement.calories)", unit: "cal", color: Color(hex: "E0FE10"))
            if supplement.protein > 0 {
                macroChip(label: "\(supplement.protein)", unit: "P", color: Color(hex: "FAFAFA"))
            }
            if supplement.carbs > 0 {
                macroChip(label: "\(supplement.carbs)", unit: "C", color: Color(hex: "3B82F6"))
            }
            if supplement.fat > 0 {
                macroChip(label: "\(supplement.fat)", unit: "F", color: Color(hex: "FFB454"))
            }
        }
        .padding(.top, 2)
    }

    private func macroChip(label: String, unit: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(unit)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(color.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
    }

    private var logButton: some View {
        HStack(spacing: 4) {
            if isLogged {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
            }
            Text(isLogged ? "Logged" : "Log now")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundColor(isLogged ? .black : .white.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(isLogged ? Color(hex: "E0FE10") : Color.white.opacity(0.08))
        )
        .overlay(
            Capsule()
                .strokeBorder(isLogged ? Color.clear : Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: isLogged ? Color(hex: "E0FE10").opacity(0.45) : .clear, radius: isLogged ? 14 : 0, x: 0, y: 6)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(accent.opacity(isLogged ? 0.12 : 0.06))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        accent.opacity(isLogged ? 0.55 : 0.35),
                        accent.opacity(0.14),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}
