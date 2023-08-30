import SwiftUI

struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 3.0
        let space: CGFloat = 3.0
        var start: CGFloat = 0
        
        while start < rect.height {
            path.move(to: CGPoint(x: rect.midX, y: start))
            path.addLine(to: CGPoint(x: rect.midX, y: start + length))
            start += length + space
        }
        
        return path
    }
}

struct DottedLineView: View {
    let color: Color
    let dashes: CGFloat
    
    var body: some View {
        DottedLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [dashes]))
            .foregroundColor(color)
    }
}

struct DottedLineView_Previews: PreviewProvider {
    static var previews: some View {
        DottedLineView(color: Color.secondaryCharcoal, dashes: 10)
    }
}
