import SwiftUI

struct ProgressBar: View {
    let progress: CGFloat
    let color: Color
    
    init(progress: CGFloat, color: Color) {
        self.progress = progress
        self.color = color
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.3))
                
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
                    .frame(width: progress * geometry.size.width) // Use the available width multiplied by progress
                    .animation(.linear(duration: 1))
            }
        }
        .cornerRadius(10)
    }
}

//struct ProgressBar_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
//            ZStack {
//                Color.secondaryCharcoal
//                ProgressBar(progress: <#T##CGFloat#>, color: <#T##Color#>)
//                ProgressBar(progress: 0.3, color: Color.primaryPurple)
//                    .frame(height: 20)
//                    .padding()
//            }
//
//            GeometryReader { geometry in
//                ProgressBar(progress: 0.7)
//                    .frame(height: 20)
//                    .padding()
//            }
//            .previewLayout(.fixed(width: 300, height: 50))
//        }
//    }
//}
