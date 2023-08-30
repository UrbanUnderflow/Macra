//
//  EntryPanelView.swift
//  FoodJournal
//
//  Created by Tremaine Grant on 8/29/23.
//

import SwiftUI

class EntryPanelViewModel: ObservableObject {
    let serviceManager: ServiceManager
    @Published var answer: String = ""
    @Published var isLoading: Bool

    init(serviceManager: ServiceManager, isLoading: Bool) {
        self.serviceManager = serviceManager
        self.isLoading = isLoading
    }
}

struct EntryPanelView: View {
    @ObservedObject var viewModel: EntryPanelViewModel
    let onSubmittedAnswer: (String) -> Void
    @State private var characterCount = 0
    var characterLimit: Int = 1000

    @FocusState private var isTextEditorFocused: Bool
    
    var body: some View {
        ZStack {
            Color.primaryPurple
            VStack(alignment: .leading, spacing: 16)
            {
                Text("What did you eat today?")
                    .foregroundColor(Color.secondaryWhite)
                    .font(.system(size: 24, weight: .bold))
                    .bold()
                    .padding(.top, 56)
                    .padding(.leading, 16)
                    .lineLimit(nil)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(
                        get: { viewModel.answer },
                        set: {
                            if $0.count <= characterLimit && !viewModel.isLoading { // Check isLoading value
                                viewModel.answer = $0
                                characterCount = $0.count
                            }
                        })
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal)
                    .focused($isTextEditorFocused)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .foregroundColor(.secondaryWhite)
                    .disabled(viewModel.isLoading) // Disable the text field based on isLoading value

                    if viewModel.answer.isEmpty && !isTextEditorFocused {
                        Text("Write your answer here...")
                            .foregroundColor(.white)
                            .padding(.horizontal)
                            .padding(.top, 10)
                            .onTapGesture {
                                isTextEditorFocused = true
                            }
                    }
                }
                .overlay(
                    CircularProgressBarView(progress: Double(characterCount), maxProgress: Double(characterLimit), colors: (start: .blue, end: .blue))
                        .frame(width: 20, height: 20)
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 16)),
                    alignment: .bottomTrailing
                )

                ConfirmationButton(title: "Submit", type: ButtonType.primaryLargeConfirmation, action: {
                    self.onSubmittedAnswer(viewModel.answer)
                    characterCount = 0
                })
                .padding(.horizontal)
                .padding(.bottom, 16)
                .disabled(viewModel.isLoading) // Disable the submit button based on isLoading value
            }
//            .keyboardPadding()
        }
    }
}




struct EntryPanelView_Previews: PreviewProvider {
    static var previews: some View {
        EntryPanelView(viewModel: EntryPanelViewModel(serviceManager: ServiceManager(), isLoading: false), onSubmittedAnswer: { _ in })
            .previewLayout(.sizeThatFits)
    }
}

