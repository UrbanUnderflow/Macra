import PhotosUI
import SwiftUI

enum MacroTargetEditorMode: Identifiable {
    case new
    case assess
    case edit(MacroRecommendation)

    var id: String {
        switch self {
        case .new: return "new"
        case .assess: return "assess"
        case .edit(let recommendation): return "edit-\(recommendation.id)"
        }
    }
}

struct MacroTargetsView: View {
    @ObservedObject var viewModel: MacroTargetsViewModel
    @State private var editorMode: MacroTargetEditorMode?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(Color(hex: "E0FE10"))
                        .padding(.vertical, 36)
                    Spacer()
                }
            } else {
                if let status = viewModel.statusMessage {
                    MacroTargetsStatusPill(text: status)
                }

                currentTargetSection

                actionButtons

                historySection
            }
        }
        .sheet(item: $editorMode) { mode in
            MacroTargetEditorView(viewModel: viewModel, mode: mode)
        }
        .alert("Macro targets", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MACRO TARGETS")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(Color(hex: "E0FE10"))

            Text("Daily fuel plan")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .foregroundColor(.white)

            Text("Assess a new target, edit values manually, or pull one from your recommendation history.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var currentTargetSection: some View {
        if let current = viewModel.currentRecommendation {
            MacroRecommendationCard(
                title: "Current target",
                recommendation: current,
                highlight: true,
                onEdit: nil
            )
        } else {
            MacroTargetsEmptyCard {
                editorMode = .assess
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            MacroTargetsPrimaryButton(title: "Assess macros", systemImage: "sparkles") {
                editorMode = .assess
            }
            MacroTargetsSecondaryButton(title: "Edit manually", systemImage: "slider.horizontal.3") {
                editorMode = viewModel.currentRecommendation.map { .edit($0) } ?? .new
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        let history = viewModel.deduplicatedRecommendations
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("RECENT RECOMMENDATIONS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(Color(hex: "8B5CF6"))
                    Spacer()
                    Text("\(history.count)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }

                LazyVStack(spacing: 10) {
                    ForEach(history) { recommendation in
                        MacroRecommendationCard(
                            title: recommendation.dayOfWeek.map { "\($0.uppercased()) target" } ?? "Global target",
                            recommendation: recommendation,
                            highlight: false
                        ) {
                            editorMode = .edit(recommendation)
                        }
                    }
                }
            }
        }
    }
}

private struct MacroTargetsStatusPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundColor(Color(hex: "E0FE10"))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color(hex: "E0FE10").opacity(0.10)))
        .overlay(Capsule().strokeBorder(Color(hex: "E0FE10").opacity(0.34), lineWidth: 1))
    }
}

private struct MacroTargetsEmptyCard: View {
    let onAssess: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "E0FE10").opacity(0.14))
                    .frame(width: 68, height: 68)
                Image(systemName: "target")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(Color(hex: "E0FE10"))
            }

            Text("No macro target yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Generate a recommendation or enter one manually to start tracking against a daily target.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAssess) {
                Text("Assess macros")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct MacroTargetsPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(Color(hex: "E0FE10"))
            )
            .shadow(color: Color(hex: "E0FE10").opacity(0.45), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct MacroTargetsSecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MacroRecommendationCard: View {
    let title: String
    let recommendation: MacroRecommendation
    var highlight: Bool
    var onEdit: (() -> Void)? = nil

    private var accent: Color {
        highlight ? Color(hex: "E0FE10") : Color(hex: "8B5CF6")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            macroTileRow

            HStack(spacing: 6) {
                Image(systemName: highlight ? "sparkles" : "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Text("Saved \(MealPlanningDates.longDateTimeFormatter.string(from: recommendation.updatedAt))")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(accent.opacity(highlight ? 0.10 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), .clear, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accent.opacity(highlight ? 0.55 : 0.34), accent.opacity(0.16), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: accent.opacity(highlight ? 0.22 : 0.12), radius: highlight ? 22 : 14, x: 0, y: 10)
                .shadow(color: Color.black.opacity(0.22), radius: 22, x: 0, y: 14)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, accent.opacity(highlight ? 0.75 : 0.45), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(recommendation.dayOfWeek?.uppercased() ?? "ALL DAYS")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(accent)
            }

            Spacer()

            if let onEdit {
                Button(action: onEdit) {
                    Text("Edit")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(accent.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(accent.opacity(0.32), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var macroTileRow: some View {
        HStack(spacing: 10) {
            MacroTargetTile(label: "Cal", value: "\(recommendation.calories)", color: Color(hex: "E0FE10"), isEmphasized: highlight)
            MacroTargetTile(label: "P", value: "\(recommendation.protein)g", color: Color(hex: "FAFAFA"), isEmphasized: false)
            MacroTargetTile(label: "C", value: "\(recommendation.carbs)g", color: Color(hex: "3B82F6"), isEmphasized: false)
            MacroTargetTile(label: "F", value: "\(recommendation.fat)g", color: Color(hex: "FFB454"), isEmphasized: false)
        }
    }
}

private struct MacroTargetTile: View {
    let label: String
    let value: String
    let color: Color
    let isEmphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(color.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(isEmphasized ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(isEmphasized ? 0.42 : 0.22), lineWidth: 1)
        )
    }
}

struct MacroTargetEditorView: View {
    @ObservedObject var viewModel: MacroTargetsViewModel
    let mode: MacroTargetEditorMode

    @Environment(\.dismiss) private var dismiss

    // Editor-local state is kept in sync with the view model so Nora's
    // results can write to the shared state and show up here immediately.
    @State private var scope: MacroTargetScope = .global
    @State private var goal: MacroTargetGoal = .maintain
    @State private var activity: MacroActivityLevel = .moderate
    @State private var bodyWeightLbs: Double = 180
    @State private var calories: Int = 2400
    @State private var protein: Int = 180
    @State private var carbs: Int = 240
    @State private var fat: Int = 70

    @State private var manualInputsExpanded: Bool = false
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var noraPromptDraft: String = ""

    private static let macraYellow = Color(hex: "E0FE10")
    private static let noraPurple = Color(hex: "8B5CF6")

    init(viewModel: MacroTargetsViewModel, mode: MacroTargetEditorMode) {
        self.viewModel = viewModel
        self.mode = mode
    }

    var body: some View {
        NavigationStack {
            editorContent
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { editorToolbar }
                .onAppear { configureInitialState() }
                .onChange(of: photoSelections) { newValue in loadSelectedImages(newValue) }
                .onChange(of: viewModel.calories) { newValue in calories = newValue }
                .onChange(of: viewModel.protein) { newValue in protein = newValue }
                .onChange(of: viewModel.carbs) { newValue in carbs = newValue }
                .onChange(of: viewModel.fat) { newValue in fat = newValue }
                .sheet(item: noraResultSheetBinding, content: noraResultSheet)
        }
    }

    private var editorContent: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0A0B0F"), Color(hex: "111318")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    hero
                    noraCard
                    scopeCard
                    manualCard
                    targetValuesCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
                .foregroundColor(.white)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Save") { commit() }
                .fontWeight(.semibold)
                .foregroundColor(Self.macraYellow)
        }
    }

    private var noraResultSheetBinding: Binding<NoraResultWrapper?> {
        Binding(
            get: { viewModel.noraResult.map { NoraResultWrapper(result: $0) } },
            set: { if $0 == nil { viewModel.noraResult = nil } }
        )
    }

    private func noraResultSheet(for wrapper: NoraResultWrapper) -> some View {
        NoraAssessResultSheet(
            viewModel: viewModel,
            result: wrapper.result,
            onDone: { alsoCloseEditor in
                viewModel.noraResult = nil
                if alsoCloseEditor { dismiss() }
            }
        )
    }

    private var title: String {
        switch mode {
        case .new: return "New target"
        case .assess: return "Assess macros"
        case .edit: return "Edit target"
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ASSESS MACROS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(Self.macraYellow)

            Text("Let Nora build a plan")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Self.noraPurple.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .tracking(-0.5)

            Text("Paste a goal, drop in a screenshot of a meal plan, or both — Nora will turn it into daily macros and a ready-to-go meal plan.")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Self.noraPurple.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Self.noraPurple.opacity(0.55),
                                    Self.macraYellow.opacity(0.18),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Nora input card

    private var noraCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Self.noraPurple)
                Text("NORA")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(Self.noraPurple)
                Spacer()
                if viewModel.isGeneratingWithNora {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(Self.noraPurple)
                            .scaleEffect(0.8)
                        Text("Thinking…")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(Self.noraPurple)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What do you want?")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))

                ZStack(alignment: .topLeading) {
                    if noraPromptDraft.isEmpty {
                        Text("e.g. I want to lean out for a trip in 6 weeks, 180 lb, train 4×/wk. Keep protein high and carbs around my workouts.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $noraPromptDraft)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(minHeight: 110)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }

            noraImagesRow

            Button(action: runNora) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isGeneratingWithNora ? "hourglass" : "sparkles")
                        .font(.system(size: 14, weight: .bold))
                    Text(viewModel.isGeneratingWithNora ? "Generating…" : "Ask Nora")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Self.noraPurple, Self.noraPurple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Self.noraPurple.opacity(0.45), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGeneratingWithNora || (noraPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.noraImages.isEmpty))
            .opacity(
                (viewModel.isGeneratingWithNora || (noraPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.noraImages.isEmpty))
                    ? 0.5 : 1.0
            )
        }
        .padding(18)
        .background(editorCardBackground(accent: Self.noraPurple))
    }

    private var noraImagesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Attachments")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                PhotosPicker(
                    selection: $photoSelections,
                    maxSelectionCount: 4,
                    matching: .images
                ) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text(viewModel.noraImages.isEmpty ? "Add image" : "Add more")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Self.noraPurple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Self.noraPurple.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Self.noraPurple.opacity(0.4), lineWidth: 1))
                }
            }

            if viewModel.noraImages.isEmpty {
                Text("Drop a screenshot of a meal plan, a coach's whiteboard, a menu photo… Nora will read it.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(viewModel.noraImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                    )

                                Button {
                                    viewModel.noraImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.black.opacity(0.65)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Scope / manual / target cards

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCOPE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.45))

            HStack {
                Text("Apply to")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Picker("Scope", selection: $scope) {
                    ForEach(MacroTargetScope.allCases) { option in
                        Text(option.dayLabel).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(Self.macraYellow)
            }
        }
        .padding(18)
        .background(editorCardBackground(accent: Self.macraYellow.opacity(0.4)))
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    manualInputsExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MANUAL INPUTS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundColor(.white.opacity(0.45))
                        Text("Formula-based recommendation")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Image(systemName: manualInputsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .buttonStyle(.plain)

            if manualInputsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Goal", selection: $goal) {
                        ForEach(MacroTargetGoal.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Activity", selection: $activity) {
                        ForEach(MacroActivityLevel.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Body weight")
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(Int(bodyWeightLbs)) lb")
                                .foregroundColor(.white.opacity(0.68))
                        }
                        Slider(value: $bodyWeightLbs, in: 100...320, step: 1)
                            .tint(Self.macraYellow)
                    }

                    Button(action: generateRecommendation) {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 13, weight: .bold))
                            Text("Generate from formula")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Self.macraYellow))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(editorCardBackground(accent: Self.macraYellow.opacity(0.25)))
    }

    private var targetValuesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TARGET VALUES")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.45))

            macroField(title: "Calories", value: $calories, step: 25, range: 1200...4500, tint: Self.macraYellow)
            macroField(title: "Protein", value: $protein, step: 5, range: 60...350, tint: Color(hex: "FAFAFA"))
            macroField(title: "Carbs", value: $carbs, step: 5, range: 40...500, tint: Color(hex: "3B82F6"))
            macroField(title: "Fat", value: $fat, step: 2, range: 30...180, tint: Color(hex: "FFB454"))
        }
        .padding(18)
        .background(editorCardBackground(accent: Self.macraYellow.opacity(0.25)))
    }

    @ViewBuilder
    private func macroField(title: String, value: Binding<Int>, step: Int, range: ClosedRange<Int>, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Text("\(value.wrappedValue)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .contentTransition(.numericText())
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .tint(tint)
        }
    }

    // MARK: - Card chrome

    private func editorCardBackground(accent: Color) -> some View {
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
                            colors: [accent.opacity(0.45), accent.opacity(0.08), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Image loading

    /// When the user picks images via `PhotosPicker`, load each as a
    /// downsampled `UIImage` and stash them on the view model. Kept
    /// contained in the editor so the view model only sees concrete images.
    private func loadSelectedImages(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoSelections = [] // reset the picker so repeated picks keep working
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        viewModel.noraImages.append(image)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func runNora() {
        viewModel.noraPrompt = noraPromptDraft
        viewModel.goal = goal
        viewModel.activity = activity
        viewModel.bodyWeightLbs = bodyWeightLbs
        viewModel.scope = scope
        viewModel.analyzeWithNora()
    }

    private func configureInitialState() {
        noraPromptDraft = viewModel.noraPrompt
        switch mode {
        case .new:
            scope = .global
            goal = .maintain
            activity = .moderate
            bodyWeightLbs = 180
            calories = 2400
            protein = 180
            carbs = 240
            fat = 70
        case .assess:
            scope = .global
            goal = .maintain
            activity = .moderate
            bodyWeightLbs = 180
            calories = viewModel.currentRecommendation?.calories ?? 2400
            protein = viewModel.currentRecommendation?.protein ?? 180
            carbs = viewModel.currentRecommendation?.carbs ?? 240
            fat = viewModel.currentRecommendation?.fat ?? 70
        case .edit(let recommendation):
            scope = MacroTargetScope.allCases.first(where: { $0.firestoreValue == recommendation.dayOfWeek }) ?? .global
            calories = recommendation.calories
            protein = recommendation.protein
            carbs = recommendation.carbs
            fat = recommendation.fat
        }
    }

    private func generateRecommendation() {
        let baseCalories = bodyWeightLbs * activity.calorieMultiplier
        let adjustedCalories: Double

        switch goal {
        case .lose:
            adjustedCalories = baseCalories - 275
        case .maintain:
            adjustedCalories = baseCalories
        case .gain:
            adjustedCalories = baseCalories + 225
        }

        let suggestedProtein: Double
        switch goal {
        case .lose:
            suggestedProtein = bodyWeightLbs * 1.05
        case .maintain:
            suggestedProtein = bodyWeightLbs * 0.9
        case .gain:
            suggestedProtein = bodyWeightLbs * 1.0
        }

        let proteinCalories = suggestedProtein * 4
        let suggestedFatCalories = max(450, adjustedCalories * 0.28)
        let suggestedFat = max(35, suggestedFatCalories / 9.0)
        let carbCalories = max(0, adjustedCalories - proteinCalories - (suggestedFat * 9))
        let suggestedCarbs = carbCalories / 4.0

        calories = max(1200, Int(adjustedCalories.rounded()))
        protein = max(60, Int(suggestedProtein.rounded()))
        carbs = max(40, Int(suggestedCarbs.rounded()))
        fat = max(35, Int(suggestedFat.rounded()))
    }

    private func commit() {
        viewModel.scope = scope
        viewModel.goal = goal
        viewModel.activity = activity
        viewModel.bodyWeightLbs = bodyWeightLbs
        viewModel.calories = calories
        viewModel.protein = protein
        viewModel.carbs = carbs
        viewModel.fat = fat
        viewModel.saveRecommendation()
        dismiss()
    }
}

private struct NoraResultWrapper: Identifiable {
    let id = UUID()
    let result: GPTService.NoraMacroAnalysis
}

// MARK: - Nora result confirmation sheet

/// Presents Nora's generated macros + meal plan and guides the user
/// through the two-step confirmation flow the product spec asked for:
///
/// 1. Primary ask: "Want Nora's meal plan too?" (yes → save macros + replace
///    active meal plan; dismisses the editor).
/// 2. If they pass on the plan, a secondary ask: "Save just the macros?"
///    (yes → save macros only; no → discard everything, the editor stays
///    open so they can keep tweaking).
struct NoraAssessResultSheet: View {
    @ObservedObject var viewModel: MacroTargetsViewModel
    let result: GPTService.NoraMacroAnalysis
    /// Called when the sheet is ready to dismiss. `alsoCloseEditor` tells
    /// the caller whether the parent Assess Macros editor should close too —
    /// true for the accept paths, false when the user discarded.
    let onDone: (_ alsoCloseEditor: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var showMacroOnlyPrompt = false

    private static let noraPurple = Color(hex: "8B5CF6")
    private static let macraYellow = Color(hex: "E0FE10")

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "0A0B0F"), Color(hex: "111318")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        macrosCard
                        planCard
                        actionStack
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }

                if isSaving {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView().tint(Self.macraYellow).scaleEffect(1.2)
                        Text("Saving…")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                        onDone(false)
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .confirmationDialog(
            "Save these macro targets?",
            isPresented: $showMacroOnlyPrompt,
            titleVisibility: .visible
        ) {
            Button("Save macros", role: .none) {
                viewModel.applyNoraMacrosOnly(from: result)
                dismiss()
                onDone(true)
            }
            Button("Discard", role: .destructive) {
                dismiss()
                onDone(false)
            }
        } message: {
            Text("You passed on the meal plan. Want to save just the macro targets (\(result.macros.calories) kcal · \(result.macros.protein)P · \(result.macros.carbs)C · \(result.macros.fat)F)?")
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                Text("NORA")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                Spacer()
                Text("\(result.meals.count) meals")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }
            .foregroundColor(Self.noraPurple)

            Text("Here's what I put together")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .tracking(-0.4)

            if !result.summary.isEmpty {
                Text(result.summary)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Self.noraPurple.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Self.noraPurple.opacity(0.55), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: Macros card

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DAILY MACROS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(Self.macraYellow)

            HStack(spacing: 10) {
                macroTile(label: "Cal", value: "\(result.macros.calories)", tint: Self.macraYellow, emphasize: true)
                macroTile(label: "P", value: "\(result.macros.protein)g", tint: Color(hex: "FAFAFA"), emphasize: false)
                macroTile(label: "C", value: "\(result.macros.carbs)g", tint: Color(hex: "3B82F6"), emphasize: false)
                macroTile(label: "F", value: "\(result.macros.fat)g", tint: Color(hex: "FFB454"), emphasize: false)
            }

            if !result.macros.rationale.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                    Text(result.macros.rationale)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .background(cardBackground(accent: Self.macraYellow))
    }

    private func macroTile(label: String, value: String, tint: Color, emphasize: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(tint.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(emphasize ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(emphasize ? 0.42 : 0.22), lineWidth: 1)
        )
    }

    // MARK: Meal plan preview

    @ViewBuilder
    private var planCard: some View {
        if !result.meals.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MEAL PLAN")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundColor(Self.noraPurple)
                        Text(result.planName)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    planTotalBadge
                }

                VStack(spacing: 10) {
                    ForEach(Array(result.meals.enumerated()), id: \.offset) { _, meal in
                        mealRow(meal)
                    }
                }
            }
            .padding(18)
            .background(cardBackground(accent: Self.noraPurple))
        }
    }

    private var planTotalBadge: some View {
        let totalCal = result.meals.reduce(0) { $0 + $1.totalCalories }
        return Text("\(totalCal) kcal total")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(Self.noraPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Self.noraPurple.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Self.noraPurple.opacity(0.4), lineWidth: 1))
    }

    private func mealRow(_ meal: GPTService.NoraMacroAnalysis.PlanMeal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(meal.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(meal.totalCalories) kcal")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Self.macraYellow)
            }

            HStack(spacing: 6) {
                macroChip("\(meal.totalProtein)P", tint: Color(hex: "FAFAFA"))
                macroChip("\(meal.totalCarbs)C", tint: Color(hex: "3B82F6"))
                macroChip("\(meal.totalFat)F", tint: Color(hex: "FFB454"))
            }

            if !meal.items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(meal.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•")
                                .foregroundColor(.white.opacity(0.35))
                            Text(item.quantity.isEmpty ? item.name : "\(item.quantity) · \(item.name)")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.72))
                            Spacer()
                            Text("\(item.calories)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
            }

            if let notes = meal.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func macroChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }

    // MARK: Actions

    private var actionStack: some View {
        VStack(spacing: 10) {
            // Primary: the product spec's first question — "Want this as
            // your new meal plan?" Yes saves macros + replaces the plan.
            Button {
                isSaving = true
                viewModel.applyNoraResult(result) {
                    isSaving = false
                    dismiss()
                    onDone(true)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(result.meals.isEmpty ? "Save macro targets" : "Use plan + macros")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Self.macraYellow, Color(hex: "C5EA17")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Self.macraYellow.opacity(0.4), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            // Secondary / tertiary actions — shown side by side.
            HStack(spacing: 10) {
                Button {
                    // "No" to the plan — ask about macros next.
                    showMacroOnlyPrompt = true
                } label: {
                    Text("No thanks")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isSaving || result.meals.isEmpty)
                .opacity(result.meals.isEmpty ? 0 : 1) // collapse when no plan was suggested

                Button {
                    dismiss()
                    onDone(false)
                } label: {
                    Text("Discard")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "FF6B6B").opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color(hex: "FF6B6B").opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color(hex: "FF6B6B").opacity(0.24), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
    }

    // MARK: Chrome

    private func cardBackground(accent: Color) -> some View {
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
                            colors: [accent.opacity(0.45), accent.opacity(0.08), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}
