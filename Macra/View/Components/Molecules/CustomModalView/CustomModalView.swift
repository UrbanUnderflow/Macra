import SwiftUI

enum ModalType: Equatable {
    case confirmation
    case notification
    case field
    case log

    static func ==(lhs: ModalType, rhs: ModalType) -> Bool {
        switch (lhs, rhs) {
        case (.confirmation, .confirmation),
             (.notification, .notification),
             (.field, .field):
            return true
        default:
            return false
        }
    }
}


class CustomModalViewModel: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var title: String
    @Published var message: String
    @Published var primaryButtonTitle: String
    @Published var secondaryButtonTitle: String
    
    @Published var textFieldValue: String = ""
    @Published var fieldSubtitle: String = ""

    var modalType: ModalType
    var primaryAction: (String) -> Void
    var secondaryAction: () -> Void

    var showSecondaryButton: Bool {
        modalType == .confirmation || modalType == .field
    }
    
    var showTextField: Bool {
        modalType == .field
    }
    
    init(type: ModalType, title: String, textFieldValue: String = "", message: String, primaryButtonTitle: String, secondaryButtonTitle: String = "", fieldSubtitle: String = "", primaryAction: @escaping (String) -> Void = {_ in }, secondaryAction: @escaping () -> Void = {}) {
        self.modalType = type
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
        self.fieldSubtitle = fieldSubtitle
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.textFieldValue = textFieldValue

    }
}


struct CustomModalView: View {
    @ObservedObject var viewModel: CustomModalViewModel
    
//    var logModal: some View  {
//        AddLogModal(viewModel: AddLogModalViewModel(title: "Choose an Event", subtitle: "What time did you complete the event?", action: {
//            viewModel.primaryAction("success")
//        }, close: {
//            viewModel.secondaryAction()
//        }))
//    }
        
    var modernModals: some View {
        VStack {
            // Modal Title
            Text(viewModel.title)
                .foregroundColor(.secondaryWhite)
                .font(.title)
                .padding()
            
            // Modal message
            Text(viewModel.message)
                .foregroundColor(.secondaryWhite)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()
            
            
            // Buttons
            VStack {
                Button(action: {
                    viewModel.primaryAction(viewModel.textFieldValue)
                    
                }, label: {
                    Text(viewModel.primaryButtonTitle)
                        .foregroundColor(.secondaryCharcoal)
                        .bold()
                        .padding()
                        .background(Color.primaryPurple)
                        .cornerRadius(10)
                })
                
                if viewModel.showSecondaryButton {
                    Button(action: {
                        viewModel.secondaryAction()
                    }, label: {
                        Text(viewModel.secondaryButtonTitle)
                            .foregroundColor(.white)
                            .padding()
                            .cornerRadius(10)
                    })
                }
            }
            .padding()
        }
    }

    
    var body: some View {
        VStack {
            if viewModel.modalType != .log {
//                logModal
//            } else {
                modernModals
            }
        }
        .background(Color.secondaryWhite)
        .cornerRadius(10)
        .padding()
    }
}

struct CustomModalView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = CustomModalViewModel(
            type: .field,
            title: "Modal Title",
            message: "This is the message inside the modal.",
            primaryButtonTitle: "Primary",
            secondaryButtonTitle: "Secondary",
            primaryAction: { message in
                print(message)
            },
            secondaryAction: { print("Secondary button tapped") }
        )
        
//        CustomModalView(viewModel: viewModel)
//            .previewLayout(.sizeThatFits)
//            .padding()
        
        CustomModalView(viewModel: CustomModalViewModel(type: .log, title: "Choose and Event", message: "", primaryButtonTitle: "Log", fieldSubtitle:"What time did you complete the event?"))
    }
}
