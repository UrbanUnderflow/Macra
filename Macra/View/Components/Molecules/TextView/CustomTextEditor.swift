import Foundation
import SwiftUI

class CustomTextEditorViewModel: ObservableObject {
    @Published var placeholderColor: Color
    @Published var placeholderText: String = ""
    
    init(placeholderColor: Color, placeholderText: String) {
        self.placeholderColor = placeholderColor
        self.placeholderText = placeholderText
    }
    
}

struct CustomTextEditor: View {
    @ObservedObject var viewModel: CustomTextEditorViewModel
    @FocusState private var isTextEditorFocused: Bool
    @State var text: String = ""
    
    let characterLimit: Int

    var characterCount: Int {
        text.count
    }
    
    var onTextChanged: (String) -> Void

    var body: some View {
        ZStack {
            Color.black
            VStack {
                TextEditor(text: Binding(
                    get: { text },
                    set: {
                        if $0.count <= characterLimit {
                            text = $0
                            onTextChanged($0)
                        }
                    })
                )
                .frame(maxHeight: .infinity)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .semibold))
                .focused($isTextEditorFocused)
                .overlay(
                    CircularProgressBarView(progress: Double(characterCount), maxProgress: Double(characterLimit), colors: (start: .blue, end: .blue))
                        .frame(width: 20, height: 20)
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 16)),
                    alignment: .bottomTrailing
                )
            }
            .background(Color.clear)
            
            if text.isEmpty && !isTextEditorFocused {
                VStack(alignment: .leading) {
                    HStack {
                        Text(viewModel.placeholderText)
                            .foregroundColor(viewModel.placeholderColor)
                            .opacity(0.7)
                            .onTapGesture {
                                isTextEditorFocused = true
                            }
                        Spacer() // Pushes the text to the leading edge
                    }
                    Spacer()
                }
            }
        }
    }
}

struct CustomTextEditor_Previews: PreviewProvider {
    static var previews: some View {
        CustomTextEditor(viewModel: CustomTextEditorViewModel(placeholderColor: .white, placeholderText: "This is test placeholder.."), characterLimit: 100) { text in
            print(text)
        }
        .previewLayout(.sizeThatFits)
    }
}
