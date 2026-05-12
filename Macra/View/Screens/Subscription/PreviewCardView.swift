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
                        Text("Start with your calorie and macro targets")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                }
                HStack {
                    VStack(alignment:.leading) {
                        Text("Daily Insights")
                            .font(.headline)
                        Text("See how each meal changes your day")
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
                        Text("Nora adjusts around your real food logs")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                    
                }
                HStack {
                    VStack(alignment:.leading) {
                        Text("Timely Alerts")
                            .font(.headline)
                        Text("Get nudges before your day gets away from you")
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
                        Text("Hit your macros without doing food math")
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
