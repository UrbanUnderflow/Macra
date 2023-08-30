import SwiftUI

class ToastViewModel: ObservableObject {
    @Published var message: String
    @Published var backgroundColor: Color
    @Published var textColor: Color
    
    init(message: String, backgroundColor: Color, textColor: Color) {
        self.message = message
        self.backgroundColor = backgroundColor
        self.textColor = textColor
    }
}

struct ToastView: View {
    @ObservedObject var viewModel: ToastViewModel

    var body: some View {
        HStack {
            Text(viewModel.message)
                .padding()
                .background(viewModel.backgroundColor)
                .foregroundColor(viewModel.textColor)
                .cornerRadius(8)
        }
    }
}


struct ToastView_Previews: PreviewProvider {
    static var previews: some View {
        ToastView(viewModel: ToastViewModel(message: "Hello", backgroundColor: .secondaryCharcoal, textColor: .secondaryWhite))
    }
}
