import SwiftUI

enum MealPlanEditorMode: Identifiable {
    case create
    case createFromDate(Date)
    case rename(planId: String, currentName: String)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .createFromDate(let date):
            return "create-\(Int(date.timeIntervalSince1970))"
        case .rename(let planId, _):
            return "rename-\(planId)"
        }
    }
}

struct MealPlanEditorView: View {
    let mode: MealPlanEditorMode
    var onSave: (MealPlanEditorResult) -> Void
    var onCancel: () -> Void

    @State private var planName = ""
    @State private var sourceDate = Date()
    @State private var useSourceDate = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.secondaryCharcoal.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        header
                        nameField
                        if case .createFromDate = mode {
                            dateField
                        }
                        if case .create = mode {
                            createOptions
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(.secondaryWhite)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { commit() }
                        .fontWeight(.semibold)
                        .foregroundColor(.primaryGreen)
                }
            }
            .onAppear {
                configureDefaults()
            }
        }
    }

    private var title: String {
        switch mode {
        case .create, .createFromDate:
            return "New meal plan"
        case .rename:
            return "Rename plan"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.secondaryWhite)

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondaryWhite.opacity(0.68))
        }
        .padding(18)
        .background(MealPlanningCardBackground())
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan name")
                .font(.headline)
                .foregroundColor(.secondaryWhite)

            TextField("e.g. High Protein Weekday", text: $planName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundColor(.secondaryWhite)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondaryWhite.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.secondaryWhite.opacity(0.12), lineWidth: 1)
                        )
                )
        }
        .padding(18)
        .background(MealPlanningCardBackground())
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Seed date")
                .font(.headline)
                .foregroundColor(.secondaryWhite)

            DatePicker("Seed from", selection: $sourceDate, displayedComponents: [.date])
                .datePickerStyle(.compact)
                .labelsHidden()
                .colorScheme(.dark)

            Text("This will create a plan from the meals you logged on that date.")
                .font(.caption)
                .foregroundColor(.secondaryWhite.opacity(0.56))
        }
        .padding(18)
        .background(MealPlanningCardBackground())
    }

    private var createOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $useSourceDate) {
                Text("Create from a day of meals")
                    .foregroundColor(.secondaryWhite)
            }
            .tint(.primaryGreen)

            if useSourceDate {
                Text("If enabled, the plan will start with your meals from the selected date.")
                    .font(.caption)
                    .foregroundColor(.secondaryWhite.opacity(0.56))
            } else {
                Text("Leave it off to create an empty reusable plan.")
                    .font(.caption)
                    .foregroundColor(.secondaryWhite.opacity(0.56))
            }
        }
        .padding(18)
        .background(MealPlanningCardBackground())
    }

    private var description: String {
        switch mode {
        case .create:
            return "Start with a blank plan or seed it from a day of meal logs."
        case .createFromDate:
            return "Pull meals from one day of your journal into a reusable plan."
        case .rename:
            return "Rename the plan without changing its meals."
        }
    }

    private func configureDefaults() {
        switch mode {
        case .create:
            planName = ""
            sourceDate = Date()
            useSourceDate = false
        case .createFromDate(let date):
            planName = "\(MealPlanningDates.longDateFormatter.string(from: date)) Plan"
            sourceDate = date
            useSourceDate = true
        case .rename(_, let currentName):
            planName = currentName
            useSourceDate = false
        }
    }

    private func commit() {
        let trimmedName = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "My Meal Plan" : trimmedName

        switch mode {
        case .create:
            if useSourceDate {
                onSave(.createFromDate(sourceDate, finalName))
            } else {
                onSave(.createEmpty(finalName))
            }
        case .createFromDate:
            onSave(.createFromDate(sourceDate, finalName))
        case .rename(let planId, _):
            onSave(.rename(planId: planId, newName: finalName))
        }
    }
}

enum MealPlanEditorResult {
    case createEmpty(String)
    case createFromDate(Date, String)
    case rename(planId: String, newName: String)
}
