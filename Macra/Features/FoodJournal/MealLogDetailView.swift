import SwiftUI
import FirebaseAuth

struct MealLogDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let logDate: Date
    var onUpdated: (Meal) -> Void
    var onDeleted: (() -> Void)?

    @State private var meal: Meal
    @State private var isEditingTime = false
    @State private var draftTime: Date
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var isLoggingAgain = false
    @State private var errorMessage: String?
    @State private var eatAgainErrorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var showEatAgainTimePicker = false
    @State private var eatAgainTime = Date()

    @State private var showPhotoSourceSheet = false
    @State private var showPhotoPicker = false
    @State private var photoPickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pickedImage: UIImage?
    @State private var isUploadingImage = false
    @State private var imageUploadError: String?

    init(meal: Meal, onUpdated: @escaping (Meal) -> Void, onDeleted: (() -> Void)? = nil) {
        self.logDate = meal.createdAt
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        _meal = State(initialValue: meal)
        _draftTime = State(initialValue: meal.createdAt)
    }

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    timeCard
                    totalsCard
                    ingredientsSection
                    eatAgainButton
                    deleteButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 40)
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondaryCharcoal)
                            .frame(width: 32, height: 32)
                            .background(Color.secondaryWhite)
                            .clipShape(Circle())
                    }
                    .padding(.leading, 20)
                    Spacer()
                    Text("Meal details")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                    Color.clear.frame(width: 32, height: 32).padding(.trailing, 20)
                }
                .padding(.top, 12)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isEditingTime) {
            timeEditorSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEatAgainTimePicker) {
            eatAgainSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete this meal?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: performDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \(meal.name.isEmpty ? "this entry" : "\"\(meal.name)\"") from your journal.")
        }
        .confirmationDialog("Add a photo", isPresented: $showPhotoSourceSheet, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    photoPickerSource = .camera
                    showPhotoPicker = true
                }
            }
            Button("Choose from Library") {
                photoPickerSource = .photoLibrary
                showPhotoPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showPhotoPicker) {
            MealLogPhotoPicker(sourceType: photoPickerSource, selectedImage: $pickedImage)
                .ignoresSafeArea()
        }
        .onChange(of: pickedImage) { newImage in
            if let newImage {
                uploadPickedImage(newImage)
            }
        }
        .alert("Upload failed", isPresented: Binding(
            get: { imageUploadError != nil },
            set: { if !$0 { imageUploadError = nil } }
        )) {
            Button("OK", role: .cancel) { imageUploadError = nil }
        } message: {
            Text(imageUploadError ?? "")
        }
    }

    private var background: some View {
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

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text("LOGGED MEAL")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(.primaryGreen)
                Text(meal.name.isEmpty ? "Meal" : meal.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !meal.caption.isEmpty {
                    Text(meal.caption)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        Button {
            guard !isUploadingImage else { return }
            showPhotoSourceSheet = true
        } label: {
            thumbnailContent
        }
        .buttonStyle(.plain)
        .disabled(isUploadingImage)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if !meal.image.isEmpty, let url = URL(string: meal.image) {
            ZStack {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        thumbnailPlaceholder
                    }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()

                uploadOverlay

                if !isUploadingImage {
                    replaceBadge
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        } else {
            ZStack {
                thumbnailPlaceholder
                addPhotoHint
                uploadOverlay
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color.primaryGreen.opacity(0.12)
            Image(systemName: "fork.knife")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(.primaryGreen.opacity(0.85))
        }
    }

    private var addPhotoHint: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add photo")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.secondaryCharcoal)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.primaryGreen))
                .overlay(Capsule().strokeBorder(Color.primaryGreen.opacity(0.4), lineWidth: 1))
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private var replaceBadge: some View {
        VStack {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Replace")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.secondaryCharcoal)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.primaryGreen.opacity(0.9)))
                .overlay(Capsule().strokeBorder(Color.primaryGreen.opacity(0.4), lineWidth: 1))
                .padding(.leading, 12)
                .padding(.top, 12)
                Spacer()
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var uploadOverlay: some View {
        if isUploadingImage {
            ZStack {
                Color.black.opacity(0.45)
                VStack(spacing: 10) {
                    ProgressView().tint(.primaryGreen)
                    Text("Uploading photo...")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
    }

    private var timeCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primaryBlue)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.primaryBlue.opacity(0.16)))

            VStack(alignment: .leading, spacing: 3) {
                Text("LOGGED AT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.55))
                Text(MealLogDetailView.timeFormatter.string(from: meal.createdAt))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()

            Button {
                draftTime = meal.createdAt
                isEditingTime = true
            } label: {
                Text("Change")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primaryGreen)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.primaryGreen.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Color.primaryGreen.opacity(0.32), lineWidth: 1))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NUTRITION TOTAL")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(Color(hex: "E0FE10"))

            HStack(alignment: .firstTextBaseline) {
                Text("\(meal.calories)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("kcal")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }

            HStack(spacing: 10) {
                MacroPill(label: "P", value: meal.protein, color: Color(hex: "60A5FA"))
                MacroPill(label: "C", value: meal.carbs, color: Color.primaryGreen)
                MacroPill(label: "F", value: meal.fat, color: Color(hex: "FBBF24"))
            }

            if meal.hasNetCarbAdjustment {
                netCarbsBreakdown
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.primaryGreen.opacity(0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primaryGreen.opacity(0.2), lineWidth: 1)
        )
    }

    private var netCarbsBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("NET CARBS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundColor(Color.primaryGreen.opacity(0.9))
                Spacer()
                Text("\(meal.netCarbs)g")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(Color.primaryGreen)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 4) {
                netCarbsLine(label: "Total carbs", value: meal.carbs, sign: "")
                if let fiber = meal.fiber, fiber > 0 {
                    netCarbsLine(label: "Fiber", value: fiber, sign: "−")
                }
                if let sugarAlcohols = meal.sugarAlcohols, sugarAlcohols > 0 {
                    netCarbsLine(label: "Sugar alcohols", value: sugarAlcohols, sign: "−")
                }
            }
        }
        .padding(.top, 4)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primaryGreen.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primaryGreen.opacity(0.24), lineWidth: 1)
        )
    }

    private func netCarbsLine(label: String, value: Int, sign: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text("\(sign)\(value)g")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var ingredientsSection: some View {
        if meal.hasDetailedIngredients, let detailed = meal.detailedIngredients {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(label: "PER FOOD BREAKDOWN", count: detailed.count, accent: Color(hex: "8B5CF6"))
                VStack(spacing: 10) {
                    ForEach(detailed) { ingredient in
                        IngredientDetailCard(ingredient: ingredient)
                    }
                }
            }
        } else if !meal.ingredients.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(label: "INGREDIENTS", count: meal.ingredients.count, accent: Color(hex: "8B5CF6"))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(meal.ingredients, id: \.self) { ingredient in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.primaryGreen.opacity(0.6))
                                .frame(width: 5, height: 5)
                            Text(ingredient)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
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

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                if isDeleting {
                    ProgressView().tint(Color(hex: "EF4444"))
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(isDeleting ? "Deleting..." : "Delete meal")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(Color(hex: "EF4444"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(Color(hex: "EF4444").opacity(0.10)))
            .overlay(Capsule().strokeBorder(Color(hex: "EF4444").opacity(0.32), lineWidth: 1))
        }
        .disabled(isDeleting)
        .padding(.top, 4)
    }

    private var eatAgainButton: some View {
        Button {
            eatAgainTime = Date()
            eatAgainErrorMessage = nil
            showEatAgainTimePicker = true
        } label: {
            HStack(spacing: 8) {
                if isLoggingAgain {
                    ProgressView().tint(.secondaryCharcoal)
                } else {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isLoggingAgain ? "Logging..." : "Eat again")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(.secondaryCharcoal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Capsule().fill(Color.primaryGreen))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .disabled(isSaving || isDeleting || isLoggingAgain)
        .padding(.top, 2)
    }

    private var timeEditorSheet: some View {
        ZStack {
            Color.secondaryCharcoal.ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Change log time")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Adjust when you ate this meal.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 20)

                DatePicker(
                    "",
                    selection: $draftTime,
                    in: Calendar.current.startOfDay(for: logDate)...endOfDay(logDate),
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "EF4444"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                HStack(spacing: 10) {
                    Button {
                        isEditingTime = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .disabled(isSaving)

                    Button {
                        persistTimeChange()
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving { ProgressView().tint(.black) }
                            Text(isSaving ? "Saving..." : "Update time")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.primaryGreen))
                    }
                    .disabled(isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            }
        }
    }

    private var eatAgainSheet: some View {
        ZStack {
            Color.secondaryCharcoal.ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Eat again")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Choose when to add this meal to your journal.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 20)

                DatePicker(
                    "",
                    selection: $eatAgainTime,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)

                if let eatAgainErrorMessage {
                    Text(eatAgainErrorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "EF4444"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                HStack(spacing: 10) {
                    Button {
                        showEatAgainTimePicker = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .disabled(isLoggingAgain)

                    Button {
                        performEatAgain()
                    } label: {
                        HStack(spacing: 6) {
                            if isLoggingAgain { ProgressView().tint(.black) }
                            Text(isLoggingAgain ? "Logging..." : "Add meal")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.primaryGreen))
                    }
                    .disabled(isLoggingAgain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a · EEE, MMM d"
        return f
    }()

    private func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
    }

    private func persistTimeChange() {
        guard !isSaving else { return }
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: logDate)
        let time = calendar.dateComponents([.hour, .minute], from: draftTime)
        var combined = DateComponents()
        combined.year = day.year
        combined.month = day.month
        combined.day = day.day
        combined.hour = time.hour
        combined.minute = time.minute
        guard let newDate = calendar.date(from: combined) else {
            errorMessage = "Couldn't build that time."
            return
        }

        var updated = meal
        updated.createdAt = newDate
        updated.updatedAt = Date()

        isSaving = true
        errorMessage = nil
        let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid
        let originalDate = meal.createdAt
        MealService.sharedInstance.updateMeal(updated, from: originalDate, to: newDate, userId: userId) { result in
            DispatchQueue.main.async {
                isSaving = false
                switch result {
                case .success(let saved):
                    meal = saved
                    onUpdated(saved)
                    isEditingTime = false
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func uploadPickedImage(_ image: UIImage) {
        guard !isUploadingImage else { return }
        isUploadingImage = true

        FirebaseService.sharedInstance.uploadMealImage(image, mealId: meal.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let downloadURL):
                    var updated = meal
                    updated.image = downloadURL
                    updated.updatedAt = Date()

                    let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid
                    MealService.sharedInstance.updateMeal(updated, for: meal.createdAt, userId: userId) { saveResult in
                        DispatchQueue.main.async {
                            isUploadingImage = false
                            pickedImage = nil
                            switch saveResult {
                            case .success(let saved):
                                meal = saved
                                onUpdated(saved)
                            case .failure(let error):
                                imageUploadError = error.localizedDescription
                            }
                        }
                    }
                case .failure(let error):
                    isUploadingImage = false
                    pickedImage = nil
                    imageUploadError = error.localizedDescription
                }
            }
        }
    }

    private func performEatAgain() {
        guard !isLoggingAgain else { return }

        var copy = meal
        copy.id = MealPlanningIDs.make(prefix: "meal")
        copy.createdAt = eatAgainTime
        copy.updatedAt = Date()

        isLoggingAgain = true
        eatAgainErrorMessage = nil

        let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid
        MealService.sharedInstance.saveMeal(copy, for: eatAgainTime, userId: userId) { result in
            DispatchQueue.main.async {
                isLoggingAgain = false
                switch result {
                case .success(let saved):
                    showEatAgainTimePicker = false
                    onUpdated(saved)
                    dismiss()
                case .failure(let error):
                    eatAgainErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performDelete() {
        guard !isDeleting else { return }
        isDeleting = true
        let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid
        MealService.sharedInstance.deleteMeal(meal, for: meal.createdAt, userId: userId) { result in
            DispatchQueue.main.async {
                isDeleting = false
                switch result {
                case .success:
                    onDeleted?()
                    dismiss()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct MacroPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(color.opacity(0.7))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(color)
                Text("g")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(color.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct IngredientDetailCard: View {
    let ingredient: MealIngredientDetail

    private var hasMacros: Bool {
        ingredient.protein > 0 || ingredient.carbs > 0 || ingredient.fat > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ingredient.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if !ingredient.quantity.isEmpty {
                        Text(ingredient.quantity)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                Spacer(minLength: 8)
                if ingredient.calories > 0 {
                    Text("\(ingredient.calories) kcal")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "E0FE10"))
                        .monospacedDigit()
                }
            }

            if hasMacros {
                HStack(spacing: 6) {
                    IngredientMacroChip(label: "P", value: ingredient.protein, color: Color(hex: "60A5FA"))
                    IngredientMacroChip(label: "C", value: ingredient.carbs, color: Color.primaryGreen)
                    IngredientMacroChip(label: "F", value: ingredient.fat, color: Color(hex: "FBBF24"))
                }

                if ingredient.hasNetCarbAdjustment {
                    HStack(spacing: 6) {
                        Text("Net C")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryGreen.opacity(0.8))
                        Text("\(ingredient.netCarbs)g")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color.primaryGreen)
                            .monospacedDigit()
                        if let fiber = ingredient.fiber, fiber > 0 {
                            Text("· fiber \(fiber)g")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        if let sa = ingredient.sugarAlcohols, sa > 0 {
                            Text("· sugar alc. \(sa)g")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct IngredientMacroChip: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.65))
            Text("\(value)g")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(color.opacity(0.24), lineWidth: 1))
    }
}

fileprivate struct MealLogPhotoPicker: UIViewControllerRepresentable {
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
        let parent: MealLogPhotoPicker

        init(_ parent: MealLogPhotoPicker) {
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
