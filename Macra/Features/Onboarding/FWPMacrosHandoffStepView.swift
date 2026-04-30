//
//  FWPMacrosHandoffStepView.swift
//  Macra
//
//  First-run handoff: if the user already set personal macros in Fit
//  With Pulse, offer to import them instead of walking through the full
//  biometric flow again. Auto-advances past itself when no FWP macros
//  are found.
//

import SwiftUI

struct FWPMacrosHandoffStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    private let accent = Color.primaryGreen

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                topBar

                switch coordinator.fwpHandoffState {
                case .checking, .unavailable:
                    checkingState
                case .available(let macros):
                    handoffContent(macros: macros)
                case .accepted, .reassessing:
                    checkingState
                }
            }
        }
        .onAppear {
            if case .checking = coordinator.fwpHandoffState {
                coordinator.loadFWPHandoff()
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

    // MARK: - Checking / transitioning state

    private var checkingState: some View {
        VStack {
            Spacer()
            ProgressView().tint(.white)
            Text("Checking for your Fit With Pulse macros…")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .padding(.top, 12)
            Spacer()
        }
    }

    // MARK: - Handoff content

    @ViewBuilder
    private func handoffContent(macros: MacroRecommendations) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("FIT WITH PULSE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(accent)

                    Text("We found your macros.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("You already set personal targets in Fit With Pulse. Use them here, or walk through Macra's plan to recalculate.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                macrosCard(macros: macros)

                Spacer(minLength: 12)

                VStack(spacing: 12) {
                    MacraPrimaryButton(
                        title: "Use these macros",
                        accent: accent,
                        isLoading: false,
                        action: { coordinator.acceptFWPMacros(macros) }
                    )

                    Button(action: coordinator.reassessAfterHandoff) {
                        Text("Reassess with Macra")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.78))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 999)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
    }

    // MARK: - Macros card

    private func macrosCard(macros: MacroRecommendations) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(macros.calories)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("kcal / day")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }

            HStack(spacing: 10) {
                macroPill(label: "Protein", grams: macros.protein)
                macroPill(label: "Carbs",   grams: macros.carbs)
                macroPill(label: "Fat",     grams: macros.fat)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func macroPill(label: String, grams: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(1.3)
                .foregroundColor(.white.opacity(0.45))
            Text("\(grams)g")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }
}
