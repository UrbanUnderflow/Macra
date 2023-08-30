import SwiftUI

struct CustomTextField: View {
    @Binding var text: String
    var placeholder: String
    var placeholderColor: Color
    var foregroundColor: Color
    var isSecure: Bool
    var showSecureText: Bool
    @State private var isEditing: Bool = false

    // Note that the Binding parameters should be passed in from the parent view
    init(text: Binding<String>, placeholder: String, placeholderColor: Color, foregroundColor: Color, isSecure: Bool = false, showSecureText: Bool = false) {
        self._text = text
        self.placeholder = placeholder
        self.placeholderColor = placeholderColor
        self.foregroundColor = foregroundColor
        self.isSecure = isSecure
        self.showSecureText = showSecureText
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty && !isEditing {
                Text(placeholder)
                    .foregroundColor(placeholderColor)
            }
            Group {
                if isSecure {
                    if showSecureText {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text, onCommit: {
                            self.isEditing = false
                        })
                    }
                } else {
                    TextField("", text: $text)
                }
            }
            .foregroundColor(foregroundColor)
            .onTapGesture {
                self.isEditing = true
            }
            .onChange(of: text) { newValue in
                if newValue.isEmpty {
                    isEditing = false
                }
            }
        }
    }
}
