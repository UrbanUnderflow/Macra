import SwiftUI

class PhaseScrollViewModel: ObservableObject {
    @Published var Names: [String] = []

    init?(Names: [String]) {
        self.Names = Names
        
//        self.commands = commands.sorted { (command1, command2) -> Bool in
//            let progress1 = userCommands.first(where: { $0.command.id == command1.id })?.calculateProgress() ?? 0
//            let progress2 = userCommands.first(where: { $0.command.id == command2.id })?.calculateProgress() ?? 0
//
//            return progress1 > progress2
        return nil
        }
    }

struct PhaseScroll: View {
    @ObservedObject var viewModel: PhaseScrollViewModel
    var onCommandTap: (String) -> Void

    
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(viewModel.Names, id: \.self) { command in
                    CommandButtonView(Names: "Test String") { name in
                        print("here")
                    }
                }
            }
        }
    }
}

struct CommandButtonView: View {
    var Names: String
    var action: (String) -> Void


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Names)  // Just display the name for simplicity
                .font(.title)
                .foregroundColor(.white)
            Text(Names)
                .font(.subheadline)
                .foregroundColor(.white)
                .bold()
        }
        .onTapGesture {
            action(Names)
        }
    }
}


struct PhaseScroll_Previews: PreviewProvider {
    static var previews: some View {
        PhaseScroll(viewModel: PhaseScrollViewModel(Names: ["Sit", "Stay", "Fetch"])!) { name in
            // Dummy action for the preview.
            print("Tapped on command: \(name)")
        }
    }
}

