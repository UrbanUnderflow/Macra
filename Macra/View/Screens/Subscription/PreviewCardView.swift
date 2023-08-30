import SwiftUI

struct PreviewCardView: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text("How it works")
                    .font(.title3)
                    .foregroundColor(.secondaryWhite)
                    .bold()
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                Spacer()
            }
            
            Group {
                HStack {
                    Circle()
                        .frame(width: 100, height: 100)
                    VStack(alignment:.leading) {
                        Text("Foundation First")
                            .font(.headline)
                        Text("Begin with essential puppy commands")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                }
                HStack {
                    VStack(alignment:.leading) {
                        Text("Daily Insights")
                            .font(.headline)
                        Text("Monitor everyday growth and behaviors")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                    Circle()
                        .frame(width: 100, height: 100)
                }
                HStack {
                    Circle()
                        .frame(width: 100, height: 100)
                    VStack(alignment:.leading) {
                        Text("Growth & Learning")
                            .font(.headline)
                        Text("As your puppy evolves, so does the training")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                    
                }
                HStack {
                    VStack(alignment:.leading) {
                        Text("Timely Alerts")
                            .font(.headline)
                        Text("Receive crucial updates at pivotal moments.")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                    Circle()
                        .frame(width: 100, height: 100)
                }
                
                HStack {
                    Circle()
                        .frame(width: 100, height: 100)
                    VStack(alignment:.leading) {
                        Text("Mastery")
                            .font(.headline)
                        Text("Master each comand at the right time")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                    
                }
            }
            .foregroundColor(.secondaryWhite)
            
            Spacer()
        }
        .padding()
        .background(CardBackground(color: Color.secondaryCharcoal))
        .frame(width: 360)
    }
}

struct PreviewCardView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewCardView()
    }
}
