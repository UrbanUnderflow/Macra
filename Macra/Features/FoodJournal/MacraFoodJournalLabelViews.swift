import SwiftUI
import UIKit

struct MacraLabelScanView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    @State private var productTitle: String = ""
    @State private var isPhotoPickerPresented = false
    @State private var pickerSourceType: UIImagePickerController.SourceType = .camera
    @State private var pickedImage: UIImage?
    @State private var isOpeningCamera: Bool = false

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                ChromaticGlassTopBar(
                    onClose: { viewModel.activeSheet = nil },
                    trailing: {
                        ChromaticGlassPillButton(
                            label: "History",
                            systemImage: "clock",
                            accent: ChromaticGlassPalette.primaryPurple
                        ) {
                            viewModel.activeSheet = .labelHistory
                        }
                    }
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ChromaticGlassEyebrow(text: "LABEL SCAN", accent: ChromaticGlassPalette.primaryCyan)

                        Text("Grade a packaged food.")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .tracking(-0.5)
                            .foregroundColor(.white)

                        Text("Frame the nutrition facts panel. Macra scores the label and suggests better alternatives.")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundColor(Color.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)

                        previewCard
                        if let errorMessage = viewModel.labelAnalysisError, !viewModel.isAnalyzingLabel {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        whatYouGetCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }

                VStack(spacing: 12) {
                    MacraPrimaryButton(
                        title: viewModel.isAnalyzingLabel ? "Analyzing label…" : "Scan a label",
                        accent: ChromaticGlassPalette.primaryGreen,
                        isLoading: viewModel.isAnalyzingLabel,
                        action: presentPhotoPicker
                    )
                    .disabled(viewModel.isAnalyzingLabel)

                    Button {
                        viewModel.activeSheet = .labelHistory
                    } label: {
                        Text("Open label history")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(ChromaticGlassPalette.primaryPurple)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .overlay {
            MacraCameraOpeningOverlay(isVisible: isOpeningCamera, message: pickerSourceType == .camera ? "Opening camera…" : "Opening photos…")
        }
        .sheet(isPresented: $isPhotoPickerPresented) {
            MacraMealPhotoPicker(sourceType: pickerSourceType, selectedImage: $pickedImage)
                .ignoresSafeArea()
        }
        .onChange(of: pickedImage) { image in
            guard let image else { return }
            pickedImage = nil
            viewModel.gradeAndSaveLabelFromImage(image)
        }
        .onChange(of: isPhotoPickerPresented) { presented in
            if !presented { isOpeningCamera = false }
        }
    }

    private func presentPhotoPicker() {
        guard !viewModel.isAnalyzingLabel else { return }
        viewModel.labelAnalysisError = nil
        pickerSourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        isOpeningCamera = true
        DispatchQueue.main.async {
            isPhotoPickerPresented = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if !isPhotoPickerPresented { isOpeningCamera = false }
        }
    }

    private var previewCard: some View {
        MacraGlassCard(
            accent: ChromaticGlassPalette.primaryCyan,
            tint: ChromaticGlassPalette.primaryCyan,
            tintOpacity: 0.08
        ) {
            Button(action: presentPhotoPicker) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(0.35))

                    VStack(spacing: 12) {
                        Image(systemName: viewModel.isAnalyzingLabel ? "sparkles" : "barcode.viewfinder")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundColor(ChromaticGlassPalette.primaryCyan)

                        Text(viewModel.isAnalyzingLabel ? "Analyzing label…" : "Position the panel in frame")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        Text(viewModel.isAnalyzingLabel
                            ? "Hold tight while Macra grades the label."
                            : "Tap to open the camera and capture the\nnutrition facts panel.")
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundColor(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                    }

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            ChromaticGlassPalette.primaryCyan.opacity(0.45),
                            style: StrokeStyle(lineWidth: 2, dash: [14, 10])
                        )
                        .padding(24)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAnalyzingLabel)

            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: "barcode")
                        .font(.system(size: 11, weight: .semibold))
                    Text("NUTRITION LABEL")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                }
                .foregroundColor(ChromaticGlassPalette.primaryCyan)

                Spacer()

                Text(viewModel.isAnalyzingLabel ? "Analyzing…" : "Tap to capture")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }

    private var whatYouGetCard: some View {
        ChromaticGlassTipsCard(
            label: "WHAT YOU GET",
            accent: ChromaticGlassPalette.primaryPurple,
            icon: "sparkles",
            tips: [
                "A grade with concerns and the sources behind them",
                "Persisted Q&A and deep-dive notes per label",
                "Healthier alternatives and a handoff into your meal log"
            ]
        )
    }
}

struct MacraLabelScanHistoryView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    var searchText: String = ""

    private var filteredLabelScans: [MacraScannedLabel] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.labelScans }
        let needle = trimmed.lowercased()
        return viewModel.labelScans.filter { scan in
            scan.displayTitle.lowercased().contains(needle)
                || scan.gradeResult.summary.lowercased().contains(needle)
                || scan.userNotes.lowercased().contains(needle)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if viewModel.isLoadingLabelHistory {
                    ProgressView("Loading label scans...")
                        .tint(MacraFoodJournalTheme.accent)
                        .foregroundColor(MacraFoodJournalTheme.textSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                } else if let labelHistoryError = viewModel.labelHistoryError {
                    MacraFoodJournalEmptyState(
                        title: "Label history unavailable",
                        message: labelHistoryError
                    )
                    Button("Try again") {
                        viewModel.loadLabelScanHistory(force: true)
                    }
                    .foregroundColor(MacraFoodJournalTheme.accent)
                } else if viewModel.labelScans.isEmpty {
                    MacraFoodJournalEmptyState(
                        title: "No label scans yet",
                        message: "Scan a packaged food label to see it listed here."
                    )
                } else if filteredLabelScans.isEmpty {
                    MacraFoodJournalEmptyState(
                        title: "No matches",
                        message: "No labels match \"\(searchText)\". Try a different search."
                    )
                } else {
                    ForEach(filteredLabelScans) { scan in
                        Button {
                            viewModel.activeSheet = .labelDetail(scan.id)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(MacraFoodJournalTheme.panelSoft)
                                        .frame(width: 78, height: 96)
                                    Image(systemName: "barcode.viewfinder")
                                        .foregroundColor(MacraFoodJournalTheme.accent2)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(scan.displayTitle)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text(scan.gradeResult.grade)
                                            .font(.title3.weight(.black))
                                            .foregroundColor(gradeColor(for: scan.gradeResult.grade))
                                    }
                                    Text(scan.gradeResult.summary)
                                        .font(.subheadline)
                                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                                        .lineLimit(2)
                                    Text(scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                                }
                            }
                            .padding(12)
                            .background(foodJournalCardBackground)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            viewModel.loadLabelScanHistory()
        }
    }

    private func gradeColor(for grade: String) -> Color {
        switch grade.uppercased() {
        case "A": return MacraFoodJournalTheme.accent
        case "B": return MacraFoodJournalTheme.accent2
        case "C": return MacraFoodJournalTheme.accent3
        case "D": return .orange
        case "F": return .red
        default: return MacraFoodJournalTheme.textMuted
        }
    }
}

struct MacraLabelScanDetailView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    @State var scannedLabel: MacraScannedLabel
    @State private var showMore = false
    @State private var editedTitle: String = ""
    @State private var isEditingTitle = false
    @FocusState private var titleFieldFocused: Bool

    init(viewModel: MacraFoodJournalViewModel, scannedLabel: MacraScannedLabel) {
        self.viewModel = viewModel
        _scannedLabel = State(initialValue: scannedLabel)
        _editedTitle = State(initialValue: scannedLabel.displayTitle)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MacraFoodJournalTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        hero
                        gradeStrip
                            .padding(.horizontal, 20)
                        VStack(spacing: 14) {
                            analysisCard
                            concernsCard
                            sourcesCard
                            deepDiveCard
                            alternativesCard
                            actions
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: viewModel.labelScanHistory) { newValue in
                guard !isEditingTitle,
                      let refreshed = newValue.first(where: { $0.id == scannedLabel.id }),
                      refreshed != scannedLabel else { return }
                scannedLabel = refreshed
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .bottomLeading) {
                heroBackground
                    .frame(height: 360)
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.35),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 360)

                heroCaption
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 360)

            heroOverlayChrome
        }
    }

    @ViewBuilder
    private var heroBackground: some View {
        if let imageURL = scannedLabel.imageURL,
           !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            RemoteImage(url: imageURL)
                .scaledToFill()
                .frame(maxWidth: .infinity)
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        gradeColor(for: scannedLabel.gradeResult.grade).opacity(0.55),
                        gradeColor(for: scannedLabel.gradeResult.grade).opacity(0.18),
                        Color.black.opacity(0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 86, weight: .light))
                    .foregroundColor(.white.opacity(0.18))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var heroCaption: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCANNED \(scannedLabel.createdAt.formatted(date: .abbreviated, time: .shortened).uppercased())")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.62))

            if isEditingTitle {
                TextField("Product title", text: $editedTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .focused($titleFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { commitTitle() }
            } else {
                Text(editedTitle.isEmpty ? "Untitled scan" : editedTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroOverlayChrome: some View {
        HStack {
            heroChromeButton(systemImage: "chevron.down") {
                viewModel.activeSheet = nil
            }
            Spacer()
            heroChromeButton(
                label: isEditingTitle ? "Done" : "Edit title",
                systemImage: isEditingTitle ? nil : "pencil"
            ) {
                if isEditingTitle {
                    commitTitle()
                } else {
                    isEditingTitle = true
                    titleFieldFocused = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func heroChromeButton(
        label: String? = nil,
        systemImage: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                }
                if let label {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, label == nil ? 12 : 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.42))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func commitTitle() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        editedTitle = trimmed
        scannedLabel.productTitle = trimmed
        scannedLabel.productTitleEdited = true
        viewModel.updateLabelScan(scannedLabel)
        titleFieldFocused = false
        isEditingTitle = false
    }

    private var gradeStrip: some View {
        let color = gradeColor(for: scannedLabel.gradeResult.grade)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 64, height: 64)
                Circle()
                    .fill(color)
                    .frame(width: 52, height: 52)
                Text(scannedLabel.gradeResult.grade.uppercased())
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(gradeDescription(for: scannedLabel.gradeResult.grade))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text("\(scannedLabel.gradeResult.confidencePercentage)% confidence")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(foodJournalCardBackground)
    }

    private func gradeDescription(for grade: String) -> String {
        switch grade.uppercased() {
        case "A": return "Excellent"
        case "B": return "Good"
        case "C": return "Moderate"
        case "D": return "Poor"
        case "F": return "Avoid"
        default: return "Unknown"
        }
    }

    private var analysisCard: some View {
        FoodJournalSection(title: "Analysis", subtitle: "Why the grade landed where it did") {
            VStack(alignment: .leading, spacing: 8) {
                Text(scannedLabel.gradeResult.detailedExplanation)
                    .foregroundColor(MacraFoodJournalTheme.textSoft)
                HStack {
                    Text("\(scannedLabel.gradeResult.confidencePercentage)% confidence")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(MacraFoodJournalTheme.accent)
                    Spacer()
                }
            }
        }
    }

    private var concernsCard: some View {
        FoodJournalSection(title: "Concerns", subtitle: "Ingredients to watch") {
            if scannedLabel.gradeResult.concerns.isEmpty {
                Text("No major concerns recorded.")
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(scannedLabel.gradeResult.concerns) { concern in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(concern.concern)
                                    .foregroundColor(.white)
                                Spacer()
                                Text(concern.severity.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(colorForSeverity(concern.severity))
                            }
                            Text(concern.scientificReason)
                                .font(.caption)
                                .foregroundColor(MacraFoodJournalTheme.textMuted)
                        }
                    }
                }
            }
        }
    }

    private var sourcesCard: some View {
        FoodJournalSection(title: "Sources", subtitle: "Evidence behind the grade") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(scannedLabel.gradeResult.sources) { source in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: source.icon)
                            .foregroundColor(MacraFoodJournalTheme.accent2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.name)
                                .foregroundColor(.white)
                            Text(source.title)
                                .font(.caption)
                                .foregroundColor(MacraFoodJournalTheme.textMuted)
                        }
                    }
                }
            }
        }
    }

    private var deepDiveCard: some View {
        FoodJournalSection(title: "Deep dive", subtitle: "Research and follow-up notes") {
            VStack(alignment: .leading, spacing: 8) {
                if let deepDive = scannedLabel.deepDiveResult {
                    Text(deepDive.summary)
                        .foregroundColor(MacraFoodJournalTheme.textSoft)
                    if showMore {
                        ForEach(deepDive.longTermEffects, id: \.self) { item in
                            TipRow(text: item)
                        }
                    }
                } else {
                    Text("No deep dive saved yet.")
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                }
                Button(showMore ? "Show less" : "Show more") {
                    showMore.toggle()
                }
                .foregroundColor(MacraFoodJournalTheme.accent)
            }
        }
    }

    private var alternativesCard: some View {
        FoodJournalSection(title: "Healthier alternatives", subtitle: "Lower-friction swaps") {
            VStack(alignment: .leading, spacing: 8) {
                if scannedLabel.alternatives.isEmpty {
                    Text("No alternatives saved.")
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                } else {
                    ForEach(scannedLabel.alternatives) { alternative in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(alternative.name)
                                    .foregroundColor(.white)
                                Spacer()
                                Text(alternative.grade)
                                    .foregroundColor(MacraFoodJournalTheme.accent)
                            }
                            Text(alternative.reason)
                                .font(.caption)
                                .foregroundColor(MacraFoodJournalTheme.textMuted)
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                scannedLabel.productTitle = editedTitle
                viewModel.updateLabelScan(scannedLabel)
                // Use a real wall-clock timestamp for the log. If the user is on
                // today's journal it's `Date()`; if they're on a past day we
                // project current time-of-day onto that day so the log lands
                // somewhere meaningful instead of midnight.
                let logTimestamp = MealService.resolveLogTimestamp(
                    forTargetDay: viewModel.selectedDate,
                    originalTimestamp: Date()
                )
                let meal = MacraFoodJournalMeal(
                    name: editedTitle,
                    caption: scannedLabel.gradeResult.summary,
                    calories: scannedLabel.gradeResult.calories ?? 0,
                    protein: scannedLabel.gradeResult.protein ?? 0,
                    carbs: scannedLabel.gradeResult.carbs ?? 0,
                    fat: scannedLabel.gradeResult.fat ?? 0,
                    fiber: scannedLabel.gradeResult.dietaryFiber,
                    sugarAlcohols: scannedLabel.gradeResult.sugarAlcohols,
                    imageURL: scannedLabel.imageURL,
                    entryMethod: .label,
                    notes: "Logged from label scan",
                    createdAt: logTimestamp,
                    updatedAt: Date()
                )
                viewModel.saveFoodJournalMeal(meal, on: viewModel.selectedDate, detailsDestination: .mealDetails(meal.id))
            } label: {
                Text("Add to meal log")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(MacraFoodJournalTheme.accent)
                    .clipShape(Capsule())
            }

            Button {
                viewModel.activeSheet = .labelHistory
            } label: {
                Text("Back to label history")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.accent2)
            }
        }
    }

    private func gradeColor(for grade: String) -> Color {
        switch grade.uppercased() {
        case "A": return MacraFoodJournalTheme.accent
        case "B": return MacraFoodJournalTheme.accent2
        case "C": return MacraFoodJournalTheme.accent3
        case "D": return .orange
        case "F": return .red
        default: return MacraFoodJournalTheme.textMuted
        }
    }

    private func colorForSeverity(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "low": return MacraFoodJournalTheme.accent2
        case "medium": return MacraFoodJournalTheme.accent3
        case "high": return .red
        default: return MacraFoodJournalTheme.textMuted
        }
    }
}
