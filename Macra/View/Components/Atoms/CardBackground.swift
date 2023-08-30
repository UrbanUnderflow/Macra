import SwiftUI

struct CardBackground: View {
    var color: Color
    var body: some View {
        Rectangle()
            .fill(color)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray, lineWidth: 1) // Gray border
                )
            
    }
}

struct CardBackground_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            HStack {
                VStack(alignment: .leading) {
                    Text("Your Workout for Today is Ready!")
                        .bold()
                        .padding(.top, 24)
                        .padding(.leading, 20)
                        .padding(.trailing, 20)
                    Text("Fullbody Workout")
                        .padding(.top, 1)
                        .padding(.leading, 20)
                    Text("11 Exercises")
                        .font(.subheadline)
                        .frame(height: 25, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(CardBackground(color: .wind))
                        .padding(.leading, 20)
                    Spacer()
                        .frame(height: 30)
                }
                
                Spacer()
                HStack {
                    Spacer()
                    Image("fullbody1")
                    Spacer()
                }
            }
            HStack {
                Spacer()
                ConfirmationButton(title: "Start Workout", type: .primaryLargeConfirmation) {
                    //Action
                }
                ConfirmationButton(title: "Want a different workout?", type: .primaryLargeConfirmation) {
                    //Action
                }
                Spacer()
            }
        }
        .background(CardBackground(color: .secondaryWhite))
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
}
