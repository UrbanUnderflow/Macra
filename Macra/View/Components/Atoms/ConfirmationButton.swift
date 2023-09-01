import SwiftUI

enum ButtonType {
    case primaryLargeConfirmation
    case animatedCircleButton(icon: Icon)
    case loading
}

struct ConfirmationButton: View {
    var title: String
    var type: ButtonType
    var foregroundColor: Color? = .white
    var backgroundColor: Color? = .clear
    var backgroundOpacity: Double? = 0.2
    @State var isLoading: Bool = false

    var action: () -> ()
    
    @State private var isExpanded: Bool = false


    var body: some View {
        switch type {
        case .primaryLargeConfirmation:
            Button(action: action) {
                Text(title)
                    .font(.title3)
                    .bold()
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.primaryPurple)
                    .cornerRadius(18)
            }
        case .animatedCircleButton(let icon):
            Button(action: {
                            if isExpanded {
                                // if button is already expanded, execute the action immediately
                                action()
                            } else {
                                // if button is not expanded, animate the expansion and wait for next tap
                                withAnimation(.spring()) {
                                    isExpanded = true
                                }
                                // set a timer to collapse the button if it's not tapped within 30 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                                    withAnimation(.spring()) {
                                        isExpanded = false
                                    }
                                }
                            }
            }) {
                ZStack {
                    if !isExpanded {
                        IconImage(icon)
                            .frame(width: 56, height: 56)
                            .background(Color.secondaryWhite)
                            .cornerRadius(28)
                            .opacity(isExpanded ? 0 : 1)
                    }
                    
                    if isExpanded {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(Color.secondaryCharcoal)
                            .padding(.horizontal, 60)
                            .padding(.vertical, 20)
                            .background(Color.secondaryWhite)
                            .cornerRadius(50)
                            .frame(minWidth: 56, maxWidth: .infinity)
                            .opacity(isExpanded ? 1 : 0)
                            .transition(.scale)
                            .onAppear {
                                // when the expanded button appears, cancel the previous timer and set a new one
                                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                                    withAnimation(.spring()) {
                                        isExpanded = false
                                    }
                                }
                            }
                            .onDisappear {
                                // when the expanded button disappears (i.e., the action is executed), reset the timer
                                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                                    withAnimation(.spring()) {
                                        isExpanded = false
                                    }
                                }
                            }
                    }
                }
            }
                                
    
        case .loading:
            ZStack {
                Circle()
                    .fill(Color.secondaryWhite)
                
                if isLoading {
                    // When loading, show the spinning loading icon
                    LottieView(animationName: "loading", loopMode: .loop)
                        .frame(width: 30, height: 30)
                        .padding()
                } else {
                    // When loading is finished, show the check icon
                    IconImage(.sfSymbol(.check, color: .green))
                        .scaledToFit()
                        .padding()
                        .frame(width: 40, height: 40)
                        .animation(.default)
                }
            }
            .frame(width: 60, height: 60)
            .onAppear {
                // Animate the button to a spinning loading state
                withAnimation(.default) {
                    self.isLoading = true
                }
                
                // When loading is complete, change the icon to a check and animate to green
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.default) {
                        self.isLoading = false
                    }
                    
                    // Add another delay of 1 second before animating back to the original state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        withAnimation(.default) {
                            self.isLoading = false
                        }
                    }
                }
            }
            .onDisappear {
                self.isLoading = false
            }

        }
    }
}

struct ConfirmationButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ConfirmationButton(title: "test", type: .primaryLargeConfirmation) {
                print("aciton")
            }
            ConfirmationButton(title: "test", type: .primaryLargeConfirmation) {
                print("aciton")
            }
            ConfirmationButton(title: "test", type: .primaryLargeConfirmation) {
                print("aciton")
            }
            ConfirmationButton(title: "test", type: .primaryLargeConfirmation) {
                print("action 2")
            }
            ConfirmationButton(title: "test", type: .primaryLargeConfirmation) {
                print("action 2")
            }
            .padding()
            
            VStack {
                Text("How was the workout?")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.secondaryWhite)
                
                ConfirmationButton(title: "test", type: .animatedCircleButton(icon: .sfSymbol(.upload, color: .secondaryCharcoal)), foregroundColor: .secondaryCharcoal) {
                    print("action 2")
                }
                Spacer()
            }
            .background(Color.secondaryCharcoal)
        }
    }
}
