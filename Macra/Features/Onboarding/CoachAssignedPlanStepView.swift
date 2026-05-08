//
//  CoachAssignedPlanStepView.swift
//  Macra
//
//  Coach-aware welcome that fires during onboarding when the current
//  user has an active Pulse 1-on-1 trainer who has attached a meal
//  plan. Shown in place of the analyze/predict/planReady wizard for
//  these users — the coach already did the work, Macra just needs
//  consent to adopt + a hint that Nora is still around for questions.
//
//  Auto-advances past itself when no coach plan is found (mirrors
//  `FWPMacrosHandoffStepView`'s checking → unavailable → advance flow).
//

import SwiftUI

struct CoachAssignedPlanStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    private let accent = Color.primaryGreen

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                topBar

                switch coordinator.coachPlanState {
                case .checking, .unavailable:
                    checkingState
                case .available(let plan):
                    coachContent(plan: plan)
                case .adopted:
                    checkingState
                }
            }
        }
        .onAppear {
            if case .checking = coordinator.coachPlanState {
                coordinator.loadCoachPlanHandoff()
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            if coordinator.canGoBack {
                Button(action: coordinator.back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - Loading state

    private var checkingState: some View {
        VStack {
            Spacer()
            ProgressView().tint(.white)
            Text("Checking for a coach-assigned plan…")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .padding(.top, 12)
            Spacer()
        }
    }

    // MARK: - Coach content

    @ViewBuilder
    private func coachContent(plan: CoachMealPlan) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header(plan: plan)
                planSummaryCard(plan: plan)
                noraReassurance
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }

        VStack(spacing: 10) {
            MacraPrimaryButton(
                title: "Use \(handleFor(plan))'s plan",
                accent: accent,
                isLoading: false
            ) {
                coordinator.acceptCoachPlan(plan)
            }

            Button(action: coordinator.declineCoachPlan) {
                Text("Build my own instead")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func header(plan: CoachMealPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR COACH")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(accent)

            Text("\(handleFor(plan)) assigned a meal plan for you.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("We'll use it as your daily target in Macra — every meal you log tracks against this plan.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func planSummaryCard(plan: CoachMealPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(plan.planName.isEmpty ? "Coach-assigned plan" : plan.planName)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                Text("\(plan.mealCount) meal\(plan.mealCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(displayCalories(plan))")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(accent)
                Text("kcal/day")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }

            HStack(spacing: 18) {
                macroPill(label: "P", value: plan.totals.protein)
                macroPill(label: "C", value: plan.totals.carbs)
                macroPill(label: "F", value: plan.totals.fat)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
    }

    private func macroPill(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
            Text("\(value)g")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noraReassurance: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(accent.opacity(0.14)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Nora is still here to help.")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                Text("Ask questions about ingredients, portions, or substitutions any time — Nora has your full plan and can break down each meal.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Helpers

    private func handleFor(_ plan: CoachMealPlan) -> String {
        let trimmed = plan.hostUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your coach" : "@\(trimmed)"
    }

    private func displayCalories(_ plan: CoachMealPlan) -> String {
        let value = plan.totals.calories > 0 ? plan.totals.calories : plan.dailyCalorieTarget
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
