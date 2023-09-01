import SwiftUI

class RegistrationModalViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator
    @Published var birthday: String = ""
    @Published var birthdate: Date = Date()

    @Published var puppyName = ""

    @Published var imageUrl = ""
        
    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }
    
}

struct RegistrationModal: View {
    @ObservedObject var viewModel: RegistrationModalViewModel
    @State private var selectedPage = 0
    @State var selectedImage: UIImage? = nil
    @State private var isDatePickerShown = false
    
    func nextButtonPressed() {
        guard let u = UserService.sharedInstance.user else {
            print("Something went wrong with getting the user during auth")
            return
        }
        
        var updatedUser = u
        
//        if selectedPage == 0 {
//            updatedUser.dogName = viewModel.puppyName.lowercased()
//            UserService.sharedInstance.updateUser(user: updatedUser)
//        }
//
//        if selectedPage == 1 {
//            updatedUser.dogStage = viewModel.selectedStage
//            UserService.sharedInstance.updateUser(user: updatedUser)
//        }
        
        if selectedPage == 1 {
            updatedUser.profileImageURL = viewModel.imageUrl
            UserService.sharedInstance.updateUser(user: updatedUser)
        }
        
        if selectedPage == 2 {
            updatedUser.birthdate = viewModel.birthdate
            UserService.sharedInstance.updateUser(user: updatedUser)
        }
        
        if selectedPage <= 3 {
            withAnimation {
                selectedPage += 1
            }
        }
        
        //once everything is selected we can create a workout for the user
        if selectedPage > 4 {
            viewModel.appCoordinator.closeModals()
        }
    }

    var titleGroup: some View {
        VStack {
            if selectedPage == 4 {
                HStack {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(viewModel.puppyName.isEmpty ? "Prepare to me a new dog parent!" : viewModel.puppyName)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.secondaryWhite)
                            .font(.system(size: 44))
                            .bold()
                        Text("Here's some information about your dog at this stage.")
                            .multilineTextAlignment(.leading)
                            .font(.headline)
                            .foregroundColor(.secondaryWhite)
                    }
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
                .padding(.leading, 20)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("We have a few questions")
                            .multilineTextAlignment(.leading)
                            .font(.largeTitle)
                            .bold()
                            .foregroundColor(.secondaryWhite)
                        Text("Tell us about your dog.")
                            .multilineTextAlignment(.leading)
                            .font(.headline)
                            .foregroundColor(.secondaryWhite)
                    }
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.bottom, 20)
                .padding(.leading, 20)
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("\(selectedPage + 1)/4")
                            .foregroundColor(Color.secondaryWhite)
                            .font(.subheadline)
                            .padding(.leading, 20)
                        Spacer()
                    }
                    ProgressView(value: Double(selectedPage + 1), total: 5)
                        .padding()
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(UIColor(red: 0.35, green: 0.38, blue: 1, alpha: 1)),
                                    Color(UIColor(red: 0.85, green: 0.34, blue: 1, alpha: 1))
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .mask(
                                ProgressView(value: Double(selectedPage + 1), total: 5)
                                    .padding()
                            )
                        )
                }
            }
        }
    }
    
    var puppyName: some View {
        VStack(alignment: .leading) {
            Text("What is your puppy's name?")
                .bold()
                .padding(.leading, 20)
                .foregroundColor(.secondaryWhite)
            
            ZStack {
                TextFieldWithIcon(text: $viewModel.puppyName, placeholder: "", icon: .sfSymbol(.camera, color: .white), isSecure: false)
            }
            .background(RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray, lineWidth: 1))
            .padding()
            Spacer()
            
        }
    }
    
    var puppyAge: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading) {
                Text("Choose the age of your puppy.")
                    .bold()
                    .padding(.leading, 20)
                    .padding(.bottom, 12)
                    .foregroundColor(.secondaryWhite)
                StageSelectionView(viewModel: StageSelectionViewModel(), onSubmittedAnswer: { selectedOption in
                    print("Selected option: \(selectedOption)")
//                    viewModel.selectedStage = selectedOption.stage
//                    viewModel.selectedDogStageDescription = selectedOption
                })
                Spacer()
                    .frame(height: 60)
            }
        }
    }
    
    var puppyBirthday: some View {
        VStack(alignment: .leading) {
            Text("If you know your puppy's birthday, choose the date")
                .bold()
                .padding(.leading, 20)
                .foregroundColor(.secondaryWhite)

            ZStack {
                Color.primaryPurple
                if !isDatePickerShown {
                   HStack {
                       IconImage(.sfSymbol(.lock, color: .secondaryWhite))
                           .padding(.trailing, 10)
                      
                       Text(viewModel.birthday.isEmpty ? "Choose Date" : viewModel.birthday)
                           .foregroundColor(.secondaryWhite)
                       Spacer()
                   }
                   .onTapGesture {
                       isDatePickerShown.toggle()
                   }
                   .padding()
               }
                
                if isDatePickerShown {
                    VStack {
                        DatePicker("", selection: $viewModel.birthdate, displayedComponents: .date)
                            .background(Color.white)
                            .datePickerStyle(WheelDatePickerStyle())
                            .onDisappear {
                                viewModel.birthday = viewModel.birthdate.dayMonthYearFormat
                            }
                            .padding(.top, 100)
                        
                        Button {
                            isDatePickerShown.toggle()
                            viewModel.birthday = viewModel.birthdate.dayMonthYearFormat
                        } label: {
                            Text("Done")
                                .foregroundColor(.secondaryWhite)
                                .padding(.vertical)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondaryWhite, lineWidth: isDatePickerShown ? 0 : 1)
            )
            .frame(height: 30)
            .padding()
            Spacer()

        }
    }
    
    var uploadPhoto: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Let's get your puppy's cutest photo!")
                    .bold()
                    .padding(.bottom, 12)
                    .foregroundColor(.secondaryWhite)
                
                HStack {
                    Spacer()
                    UploadImageView(viewModel: UploadImageViewModel(serviceManager: viewModel.appCoordinator.serviceManager, onImageUploaded: { image in
                        self.selectedImage = image
                    })) {
                        VStack(alignment: .center, spacing:20) {
                            if let image = selectedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 150, height: 150)
                                    .cornerRadius(75, corners: .all)
                            } else {
                                VStack {
                                    IconImage(.sfSymbol(.camera, color: .secondaryWhite), width: 36 , height: 36)
                                    
                                    Text("Upload a photo")
                                        .foregroundColor(.secondaryWhite)
                                        .font(.title3)
                                        .bold()
                                        .padding(.bottom, 5)
                                }
                                .frame(height: 150)
                            }
                            
                        }
                    }
                    Spacer()
                }
                .padding(50)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            Color.blueGray,
                            lineWidth: 2
                        )
                )
                ConfirmationButton(title: "Skip", type: .primaryLargeConfirmation) {
                    nextButtonPressed()
                }
                Spacer()
                
            }
            .padding(.horizontal, 20)
            Spacer()
        }
    }
    
    var puppyTips: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading) {
                HStack {
                    Spacer()
//                    IconImage(.sfSymbol(.heart, color: .secondaryWhite)
//                        .padding(30)
//                              width: Spacer()
                }
                .padding()
                
                Text(viewModel.puppyName)
                    .foregroundColor(.secondaryWhite)
                    .padding(.bottom)
                
                Text("Tips for your dog at this stage")
                    .bold()
                    .font(.title3)
                    .foregroundColor(.secondaryWhite)
                    .padding(.bottom)
                
                ForEach(Array(viewModel.puppyName), id: \.self) { character in
                    VStack(alignment: .leading) {
                        Text(String(character))
                            .bold()
                            .foregroundColor(.secondaryWhite)
                            .padding(.bottom, 2)
                    }
                }
                
                Spacer()
                    .frame(height: 50)
            }
            .padding(.horizontal, 20)
            Spacer()
        }
    }

    
    var body: some View {
        VStack {
            titleGroup
            
            ZStack {
                Color.primaryPurple
                
                TabView(selection: $selectedPage) {
                    puppyName
                        .background(Color.primaryPurple)
                    .tag(0)
                    
                    puppyAge
                        .background(Color.primaryPurple)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(1)
                    
                    puppyBirthday
                        .background(Color.primaryPurple)
                        .tag(2)
                    
                    uploadPhoto
                        .background(Color.primaryPurple)
                    .tag(3)
                    
                    puppyTips
                        .background(Color.primaryPurple)
                    .tag(4)
                }.background(.clear)
                
                VStack {
                    Spacer()
                    ConfirmationButton(title: selectedPage == 4 ? "Complete" : "Next", type: .primaryLargeConfirmation) {
                        nextButtonPressed()
                    }
                    .padding()
                }
                
            }
        }
        .background(Color.primaryPurple, ignoresSafeAreaEdges: .all)
    }
}

struct RegistrationModal_Previews: PreviewProvider {
    static var previews: some View {
        RegistrationModal(viewModel: RegistrationModalViewModel(appCoordinator: AppCoordinator(serviceManager: ServiceManager())))
    }
}


struct WhiteDatePicker: UIViewRepresentable {
    @Binding var date: Date
    var onDone: () -> Void

    func makeUIView(context: Context) -> UIDatePicker {
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .date
        datePicker.setValue(UIColor.white, forKey: "textColor")
        return datePicker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        uiView.date = date
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: WhiteDatePicker

        init(_ parent: WhiteDatePicker) {
            self.parent = parent
        }

        @objc func done() {
            parent.onDone()
        }
    }
}
