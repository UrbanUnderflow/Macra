import SwiftUI
import UIKit

// MARK: - Chromatic Glass tokens (mirrors ChromaticGlassDesignSystem)

enum ChromaticGlassPalette {
    static let primaryGreen = Color(hex: "E0FE10")
    static let primaryBlue = Color(hex: "3B82F6")
    static let primaryCyan = Color(hex: "06B6D4")
    static let primaryPurple = Color(hex: "8B5CF6")
    static let secondaryRed = Color(hex: "EF4444")
    static let warningAmber = Color(hex: "FFAD30")
}

struct ChromaticGlassEyebrow: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .tracking(0.8)
            .foregroundColor(accent)
    }
}

struct ChromaticGlassTopBar<Trailing: View>: View {
    let onClose: () -> Void
    let trailing: () -> Trailing

    init(onClose: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.onClose = onClose
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }

            Spacer()

            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

struct ChromaticGlassPillButton: View {
    let label: String
    let systemImage: String?
    let accent: Color
    let action: () -> Void

    init(label: String, systemImage: String? = nil, accent: Color, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.accent = accent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(accent.opacity(0.10)))
            .overlay(Capsule().strokeBorder(accent.opacity(0.34), lineWidth: 1))
        }
    }
}

func ChromaticGlassPlaceholder(_ text: String) -> Text {
    Text(text)
        .font(.system(size: 15, weight: .regular, design: .default))
        .foregroundColor(.white.opacity(0.38))
}

struct ChromaticGlassFieldCard<Content: View>: View {
    let label: String
    let optional: Bool
    let accent: Color
    let content: Content

    init(label: String, optional: Bool, accent: Color, @ViewBuilder content: () -> Content) {
        self.label = label
        self.optional = optional
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        MacraGlassCard(accent: accent, tint: accent, tintOpacity: 0.06) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ChromaticGlassEyebrow(text: label, accent: accent)
                if optional {
                    Text("optional")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundColor(.white.opacity(0.42))
                }
                Spacer()
            }
            content
        }
    }
}

struct ChromaticGlassTipsCard: View {
    let label: String
    let accent: Color
    let icon: String
    let tips: [String]

    var body: some View {
        MacraGlassCard(accent: accent, tint: accent, tintOpacity: 0.08) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent)
                ChromaticGlassEyebrow(text: label, accent: accent)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(tips, id: \.self) { tip in
                    ChromaticGlassTipRow(text: tip, accent: accent)
                }
            }
        }
    }
}

struct ChromaticGlassTipRow: View {
    let text: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(accent.opacity(0.18)))
                .overlay(Circle().strokeBorder(accent.opacity(0.32), lineWidth: 1))
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MacraMealPhotoPicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: MacraMealPhotoPicker

        init(_ parent: MacraMealPhotoPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.selectedImage = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct MacraFoodJournalScanFoodView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    @State private var mealTitle: String = ""
    @State private var mealCaption: String = ""
    @State private var isPhotoPickerPresented = false
    @State private var pickerSourceType: UIImagePickerController.SourceType = .camera
    @FocusState private var focusedField: ScanField?

    private enum ScanField: Hashable {
        case title
        case caption
    }

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                ChromaticGlassTopBar(
                    onClose: { viewModel.activeSheet = nil },
                    trailing: {
                        ChromaticGlassPillButton(
                            label: "Labels",
                            systemImage: "barcode.viewfinder",
                            accent: ChromaticGlassPalette.primaryCyan
                        ) {
                            viewModel.activeSheet = .labelScan
                        }
                    }
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ChromaticGlassEyebrow(text: "SCAN FOOD", accent: ChromaticGlassPalette.primaryBlue)

                        Text("Snap your plate.")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .tracking(-0.5)
                            .foregroundColor(.white)

                        Text("Capture a meal, then confirm the photo before Macra analyzes it.")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundColor(Color.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)

                        previewCard
                        titleCard
                        captionCard
                        tipsCard
                        secondaryCTAs
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }

                MacraPrimaryButton(
                    title: viewModel.draftMealImage == nil ? "Take photo" : "Continue to confirmation",
                    accent: ChromaticGlassPalette.primaryGreen,
                    isLoading: false,
                    action: primaryAction
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            mealTitle = viewModel.draftMealTitle
            mealCaption = viewModel.draftMealCaption
        }
        .sheet(isPresented: $isPhotoPickerPresented) {
            MacraMealPhotoPicker(sourceType: pickerSourceType, selectedImage: $viewModel.draftMealImage)
                .ignoresSafeArea()
        }
    }

    private func primaryAction() {
        if viewModel.draftMealImage == nil {
            presentPhotoPicker()
        } else {
            viewModel.draftMealTitle = mealTitle
            viewModel.draftMealCaption = mealCaption
            viewModel.activeSheet = .imageConfirmation
        }
    }

    private var previewCard: some View {
        MacraGlassCard(
            accent: ChromaticGlassPalette.primaryBlue,
            tint: ChromaticGlassPalette.primaryBlue,
            tintOpacity: 0.08
        ) {
            Button {
                presentPhotoPicker()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .frame(height: 300)

                    if let image = viewModel.draftMealImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        cameraPlaceholder
                    }

                    if viewModel.draftMealImage == nil {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                ChromaticGlassPalette.primaryBlue.opacity(0.45),
                                style: StrokeStyle(lineWidth: 2, dash: [14, 10])
                            )
                            .padding(24)
                            .frame(height: 300)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("PHOTO SCAN")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                }
                .foregroundColor(ChromaticGlassPalette.primaryBlue)

                Spacer()

                Text(viewModel.draftMealImage == nil ? "Tap to capture" : "Photo captured")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(ChromaticGlassPalette.primaryBlue)

            Text("Place food in the frame")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Text("Tap to take a photo")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }

    private var titleCard: some View {
        ChromaticGlassFieldCard(
            label: "MEAL NAME",
            optional: true,
            accent: ChromaticGlassPalette.primaryBlue
        ) {
            TextField("", text: $mealTitle, prompt: ChromaticGlassPlaceholder("Give your meal a name"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .caption }
        }
    }

    private var captionCard: some View {
        ChromaticGlassFieldCard(
            label: "CONTEXT OR NOTE",
            optional: true,
            accent: ChromaticGlassPalette.primaryGreen
        ) {
            TextField(
                "",
                text: $mealCaption,
                prompt: ChromaticGlassPlaceholder("Anything Macra should know before analyzing?"),
                axis: .vertical
            )
            .font(.system(size: 15, weight: .regular, design: .default))
            .foregroundColor(.white)
            .lineLimit(3...6)
            .focused($focusedField, equals: .caption)
        }
    }

    private var tipsCard: some View {
        ChromaticGlassTipsCard(
            label: "HELPFUL CUES",
            accent: ChromaticGlassPalette.primaryPurple,
            icon: "sparkles",
            tips: [
                "Include cooking method and portion size",
                "Mention sauces, oils, or seasonings",
                "Use history if the meal is a repeat"
            ]
        )
    }

    private var secondaryCTAs: some View {
        VStack(spacing: 12) {
            if viewModel.draftMealImage != nil {
                Button(action: presentPhotoPicker) {
                    Text("Retake photo")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }
            }

            Button {
                viewModel.draftMealTitle = mealTitle
                viewModel.draftMealCaption = mealCaption
                viewModel.activeSheet = .mealNotePad
            } label: {
                Text("Use text note instead")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(ChromaticGlassPalette.primaryPurple)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func presentPhotoPicker() {
        pickerSourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        isPhotoPickerPresented = true
    }
}

struct MacraFoodJournalImageConfirmationView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    @State private var mealTime: Date = Date()
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                MacraFoodJournalTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        preview
                        fields
                        tips
                        Button {
                            viewModel.selectedDate = mealTime
                            viewModel.draftMealNotes = note
                            viewModel.addMealFromDraft(entryMethod: .photo)
                        } label: {
                            Text("Analyze and save")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(MacraFoodJournalTheme.accent)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Back") { viewModel.activeSheet = .scanFood }
                .foregroundColor(MacraFoodJournalTheme.textSoft)
            Spacer()
            Text("Confirm image")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Button("Use note") { viewModel.activeSheet = .mealNotePad }
                .foregroundColor(MacraFoodJournalTheme.accent2)
        }
    }

    private var preview: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.19, blue: 0.26),
                                Color(red: 0.08, green: 0.09, blue: 0.13)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 300)

                if let image = viewModel.draftMealImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundColor(MacraFoodJournalTheme.accent)
                        Text(viewModel.draftMealTitle.isEmpty ? "Meal photo" : viewModel.draftMealTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Go back and take a photo to replace this frame.")
                            .font(.caption)
                            .foregroundColor(MacraFoodJournalTheme.textMuted)
                    }
                }

                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(height: 300)
            }

            Text("Review the image before analysis")
                .font(.caption)
                .foregroundColor(MacraFoodJournalTheme.textMuted)
        }
        .padding(18)
        .background(foodJournalCardBackground)
    }

    private var fields: some View {
        VStack(spacing: 12) {
            DatePicker("Meal time", selection: $mealTime, displayedComponents: [.date, .hourAndMinute])
                .tint(MacraFoodJournalTheme.accent)
            TextField("Any extra context?", text: $note, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.roundedBorder)
        }
        .padding(18)
        .background(foodJournalCardBackground)
    }

    private var tips: some View {
        FoodJournalSection(title: "Confirmation tips", subtitle: "Give the analyzer a little more signal") {
            VStack(alignment: .leading, spacing: 8) {
                TipRow(text: "Mention oils, toppings, or sauces")
                TipRow(text: "Adjust the meal name if it's a repeat")
                TipRow(text: "You can relog it from history later")
            }
        }
    }
}

struct MacraFoodJournalFoodIdentifierView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    @State private var meal: MacraFoodJournalMeal?
    @State private var editedName: String = ""
    @State private var editedCaption: String = ""
    @State private var isEditingTitle = false

    init(viewModel: MacraFoodJournalViewModel, meal: MacraFoodJournalMeal?) {
        self.viewModel = viewModel
        _meal = State(initialValue: meal)
        _editedName = State(initialValue: meal?.name ?? "")
        _editedCaption = State(initialValue: meal?.caption ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MacraFoodJournalTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        analysisHero
                        macroCards
                        ingredientCards
                        insights
                        actions
                    }
                    .padding(20)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Done") { viewModel.activeSheet = nil }
                .foregroundColor(MacraFoodJournalTheme.textSoft)
            Spacer()
            Text("Food identifier")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Button(isEditingTitle ? "Lock" : "Edit") {
                isEditingTitle.toggle()
            }
            .foregroundColor(MacraFoodJournalTheme.accent)
        }
    }

    private var analysisHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let meal {
                if isEditingTitle {
                    TextField("Meal title", text: $editedName)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                } else {
                    Text(editedName.isEmpty ? meal.name : editedName)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                }
                TextField("Caption", text: $editedCaption, axis: .vertical)
                    .lineLimit(2...4)
                    .foregroundColor(MacraFoodJournalTheme.textSoft)
                Text(meal.shortSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            } else {
                Text("Meal analysis is loading.")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
        .padding(18)
        .background(foodJournalCardBackground)
    }

    private var macroCards: some View {
        HStack(spacing: 12) {
            macroCard(title: "Calories", value: meal.map { "\($0.calories)" } ?? "0", tint: MacraFoodJournalTheme.accent)
            macroCard(title: "Protein", value: meal.map { "\($0.protein)g" } ?? "0g", tint: MacraFoodJournalTheme.accent2)
            macroCard(title: "Carbs", value: meal.map { "\($0.carbs)g" } ?? "0g", tint: MacraFoodJournalTheme.accent3)
            macroCard(title: "Fat", value: meal.map { "\($0.fat)g" } ?? "0g", tint: MacraFoodJournalTheme.textMuted)
        }
    }

    private func macroCard(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(foodJournalCardBackground)
    }

    private var ingredientCards: some View {
        FoodJournalSection(title: "Ingredient breakdown", subtitle: "Inspired by the production ingredient cards") {
            VStack(alignment: .leading, spacing: 8) {
                if let meal, !meal.ingredients.isEmpty {
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
                } else {
                    Text("No ingredients were extracted for this meal yet.")
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                }
            }
        }
    }

    private var insights: some View {
        FoodJournalSection(title: "Day insight", subtitle: "What the journal thinks about this meal") {
            VStack(alignment: .leading, spacing: 8) {
                TipRow(text: "The highest leverage move is to keep the protein anchor.")
                TipRow(text: "If this is a repeat, use from-history logging next time.")
                TipRow(text: "Save the analysis to your meal details for later edits.")
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                guard var meal else { return }
                meal.name = editedName.isEmpty ? meal.name : editedName
                meal.caption = editedCaption
                meal.updatedAt = Date()
                self.meal = meal
                viewModel.updateMeal(meal)
                viewModel.activeSheet = .mealDetails(meal.id)
            } label: {
                Text("Save analysis")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(MacraFoodJournalTheme.accent)
                    .clipShape(Capsule())
            }

            if let meal {
                Button {
                    viewModel.activeSheet = .mealDetails(meal.id)
                } label: {
                    Text("Open meal details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(MacraFoodJournalTheme.accent2)
                }
            }
        }
    }
}

struct MacraFoodJournalMealNotePadView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    @State private var title: String = ""
    @State private var description: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case description
    }

    private var canAnalyze: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                ChromaticGlassTopBar(
                    onClose: { viewModel.activeSheet = nil },
                    trailing: {
                        ChromaticGlassPillButton(
                            label: "Voice",
                            systemImage: "waveform",
                            accent: ChromaticGlassPalette.primaryPurple
                        ) {
                            viewModel.activeSheet = .voiceEntry
                        }
                    }
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ChromaticGlassEyebrow(text: "MEAL NOTEPAD", accent: ChromaticGlassPalette.primaryGreen)

                        Text("Describe what you ate.")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .tracking(-0.5)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Macra's analyzer will turn your note into calories, macros, and a log entry.")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundColor(Color.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)

                        titleCard
                        descriptionCard
                        tipsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }

                if let errorMessage = viewModel.analysisError, !viewModel.isAnalyzing {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.55))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                MacraPrimaryButton(
                    title: viewModel.isAnalyzing ? "Analyzing…" : "Analyze note",
                    accent: ChromaticGlassPalette.primaryGreen,
                    isLoading: viewModel.isAnalyzing,
                    action: analyze
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .opacity(canAnalyze && !viewModel.isAnalyzing ? 1 : 0.4)
                .disabled(!canAnalyze || viewModel.isAnalyzing)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            title = viewModel.draftMealTitle
            description = viewModel.draftMealCaption
            viewModel.analysisError = nil
        }
    }

    private func analyze() {
        print("[Macra][MealNotePadView.analyze] tapped — title:'\(title)' descLen:\(description.count)")
        viewModel.draftMealTitle = title
        viewModel.draftMealCaption = description
        viewModel.analyzeAndSaveMealFromDraft(entryMethod: .text)
    }

    private var titleCard: some View {
        ChromaticGlassFieldCard(
            label: "MEAL TITLE",
            optional: true,
            accent: ChromaticGlassPalette.primaryBlue
        ) {
            TextField("", text: $title, prompt: ChromaticGlassPlaceholder("Optional title"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .description }
        }
    }

    private var descriptionCard: some View {
        ChromaticGlassFieldCard(
            label: "DESCRIBE YOUR MEAL",
            optional: false,
            accent: ChromaticGlassPalette.primaryGreen
        ) {
            TextField(
                "",
                text: $description,
                prompt: ChromaticGlassPlaceholder("e.g. grilled chicken, 1 cup rice, broccoli with olive oil"),
                axis: .vertical
            )
            .font(.system(size: 15, weight: .regular, design: .default))
            .foregroundColor(.white)
            .lineLimit(5...10)
            .focused($focusedField, equals: .description)
        }
    }

    private var tipsCard: some View {
        ChromaticGlassTipsCard(
            label: "PROMPT TIPS",
            accent: ChromaticGlassPalette.primaryPurple,
            icon: "sparkles",
            tips: [
                "Include portion sizes when you know them",
                "Mention sauces, oils, and toppings",
                "Write naturally — the analyzer cleans it up"
            ]
        )
    }
}

struct MacraFoodJournalVoiceMealEntryView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel
    @State private var title: String = ""
    @State private var transcript: String = ""
    @State private var notes: String = ""
    @FocusState private var focusedField: VoiceField?

    private enum VoiceField: Hashable {
        case transcript
        case notes
    }

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                ChromaticGlassTopBar(
                    onClose: { viewModel.activeSheet = nil },
                    trailing: {
                        ChromaticGlassPillButton(
                            label: viewModel.isRecordingVoice ? "Stop" : "Record",
                            systemImage: viewModel.isRecordingVoice ? "stop.fill" : "mic.fill",
                            accent: viewModel.isRecordingVoice
                                ? ChromaticGlassPalette.secondaryRed
                                : ChromaticGlassPalette.primaryCyan
                        ) {
                            toggleRecording()
                        }
                    }
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ChromaticGlassEyebrow(text: "VOICE ENTRY", accent: ChromaticGlassPalette.primaryCyan)

                        Text("Talk through your meal.")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .tracking(-0.5)
                            .foregroundColor(.white)

                        Text("Speak naturally and Macra will transcribe, then analyze the entry.")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundColor(Color.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)

                        recorderCard
                        transcriptCard
                        notesCard
                        tipsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }

                if let errorMessage = viewModel.analysisError, !viewModel.isAnalyzing {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.55))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                MacraPrimaryButton(
                    title: viewModel.isAnalyzing ? "Analyzing…" : "Analyze voice entry",
                    accent: ChromaticGlassPalette.primaryGreen,
                    isLoading: viewModel.isAnalyzing
                ) {
                    let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("[Macra][VoiceMealEntryView.analyze] tapped — title:'\(title)' transcriptLen:\(trimmedTranscript.count)")
                    viewModel.draftMealTitle = title
                    viewModel.draftMealCaption = trimmedTranscript
                    viewModel.draftMealNotes = notes
                    viewModel.analyzeAndSaveMealFromDraft(entryMethod: .voice)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .opacity(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAnalyzing ? 0.4 : 1)
                .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAnalyzing)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            title = viewModel.draftMealTitle
            transcript = viewModel.voiceTranscript
            viewModel.analysisError = nil
        }
    }

    private func toggleRecording() {
        viewModel.isRecordingVoice.toggle()
        if viewModel.isRecordingVoice {
            viewModel.voiceTranscript = "Chicken bowl with rice, avocado, and salsa."
        } else {
            transcript = viewModel.voiceTranscript
        }
    }

    private var recorderCard: some View {
        MacraGlassCard(
            accent: ChromaticGlassPalette.primaryCyan,
            tint: ChromaticGlassPalette.primaryCyan,
            tintOpacity: 0.10
        ) {
            VStack(spacing: 14) {
                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        ChromaticGlassPalette.primaryCyan,
                                        ChromaticGlassPalette.primaryBlue
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 96, height: 96)
                            .shadow(color: ChromaticGlassPalette.primaryCyan.opacity(0.4), radius: 22, x: 0, y: 10)

                        Image(systemName: viewModel.isRecordingVoice ? "mic.fill" : "waveform")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .buttonStyle(.plain)

                Text(viewModel.isRecordingVoice ? "Listening…" : "Tap to transcribe your meal")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var transcriptCard: some View {
        ChromaticGlassFieldCard(
            label: "TRANSCRIPT",
            optional: false,
            accent: ChromaticGlassPalette.primaryBlue
        ) {
            TextField(
                "",
                text: $transcript,
                prompt: ChromaticGlassPlaceholder("Tap record to capture a spoken meal entry."),
                axis: .vertical
            )
            .font(.system(size: 15, weight: .regular, design: .default))
            .foregroundColor(.white)
            .lineLimit(4...10)
            .focused($focusedField, equals: .transcript)
        }
    }

    private var notesCard: some View {
        ChromaticGlassFieldCard(
            label: "NOTES",
            optional: true,
            accent: ChromaticGlassPalette.primaryGreen
        ) {
            TextField(
                "",
                text: $notes,
                prompt: ChromaticGlassPlaceholder("Anything to remember?"),
                axis: .vertical
            )
            .font(.system(size: 15, weight: .regular, design: .default))
            .foregroundColor(.white)
            .lineLimit(2...5)
            .focused($focusedField, equals: .notes)
        }
    }

    private var tipsCard: some View {
        ChromaticGlassTipsCard(
            label: "VOICE TIPS",
            accent: ChromaticGlassPalette.primaryPurple,
            icon: "sparkles",
            tips: [
                "List items in the order you ate them",
                "Call out brands or restaurant names",
                "Use the notes field to refine the transcript"
            ]
        )
    }
}

struct TipRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(MacraFoodJournalTheme.accent)
            Text(text)
                .foregroundColor(MacraFoodJournalTheme.textSoft)
                .font(.subheadline)
            Spacer()
        }
    }
}
