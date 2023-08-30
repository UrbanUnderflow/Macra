import SwiftUI

struct BadgeBackground: View {
    var color: Color
    var cornerRadius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(color)
    }
}

struct BadgeBackground_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            VStack {
                HStack {
                    Spacer()
                    Text("Best Value")
                    Spacer()
                }
                .padding()
            }
            .background(BadgeBackground(color: .blueGray, cornerRadius: 40))
            .frame(width: 200)
            
            VStack {
                Text("Best Value")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .background(BadgeBackground(color: .blueGray, cornerRadius: 40))
            
        }
    }
}
