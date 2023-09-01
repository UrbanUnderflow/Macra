import SwiftUI

struct BackButton: View {
    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.clear)
                .frame(width: 46, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.secondaryWhite, lineWidth: 1)
                )
            
            
            IconImage(.sfSymbol(.chevLeft, color: .secondaryWhite))
                .frame(width: 24, height: 24)
            
        }
        .frame(width: 46, height: 46)
    }
}

struct BackButton_Previews: PreviewProvider {
    static var previews: some View {
        BackButton()
    }
}
