//import SwiftUI
//
//struct SnapScrollView: View {
//    let cardWidth: CGFloat = 320
//    let cardHeight: CGFloat = 400
//    let cardSpacing: CGFloat = 20
//    let horizontalPadding: CGFloat = 20
//
//    @State private var currentIndex = 0
//
//    var body: some View {
//        SnapScroll(itemCount: 3, currentIndex: $currentIndex) {
//            HStack(spacing: cardSpacing) {
//                ForEach(0..<3, id: \.self) { index in
//                    RoundedRectangle(cornerRadius: 20)
//                        .fill(Color.secondaryWhite)
//                        .frame(width: cardWidth, height: cardHeight)
//                        .padding(.horizontal, 5)
//                        .id(index) // Assign an ID to each card
//                        .onAppear {
//                            if index == currentIndex {
//                                // Automatically scroll to the card with the current index
//                                scrollToCard(index)
//                            }
//                        }
//                }
//            }
//            .padding(.horizontal, horizontalPadding)
//        }
//        .frame(height: cardHeight)
//        .onAppear {
//            currentIndex = 0 // Set the initial index
//        }
//        .onChange(of: currentIndex) { newValue in
//            scrollToCard(newValue)
//        }
//    }
//
//    func scrollToCard(_ index: Int) {
//        // Calculate the position to scroll to
//        let position = CGFloat(index) * (cardWidth + cardSpacing) - horizontalPadding
//        // Scroll to the calculated position
//        scrollView.scrollTo(position)
//    }
//
//    // ScrollViewReader instance
//    private let scrollView = ScrollViewReader<<#Content: View#>>()
//}
//
//struct SnapScrollView_Previews: PreviewProvider {
//    static var previews: some View {
//        SnapScrollView(itemCount: 3, currentIndex: .constant(0)) {
//            Color.red
//                .frame(width: 300, height: 200)
//            Color.green
//                .frame(width: 300, height: 200)
//            Color.blue
//                .frame(width: 300, height: 200)
//        }
//        .frame(height: 200)
//    }
//}
