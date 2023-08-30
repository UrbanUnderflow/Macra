import SwiftUI
import AVKit
import Combine

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var presentationMode: Bool  // Modify this line to use a Bool binding
    @Binding var showErrorAlert: Bool
    @Binding var errorText: String
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = context.coordinator
        return imagePicker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, presentationMode: $presentationMode, showErrorAlert: $showErrorAlert, errorText: $errorText)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: ImagePicker
        @Binding var presentationMode: Bool  // Modify this line to use a Bool binding
        @Binding var showErrorAlert: Bool
        @Binding var errorText: String
        
        init(_ parent: ImagePicker, presentationMode: Binding<Bool>, showErrorAlert: Binding<Bool>, errorText: Binding<String>) {
            self.parent = parent
            self._presentationMode = presentationMode
            self._showErrorAlert = showErrorAlert
            self._errorText = errorText
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            
            presentationMode = false  // Modify this line to dismiss the picker
        }
    }
}


class UploadImageViewModel: ObservableObject {
    @Published var serviceManager: ServiceManager
    
    @Published var showErrorAlert = false
    @Published var errorText = ""
    @Published var fetchedImage: UIImage? = nil
    @Published var selectedImage: UIImage? {
        didSet {
            if let image = selectedImage {
                uploadImage(image)
            }
        }
    }
    
    @Published var showingImagePicker = false
    @Published var imageUrl: String? {
        didSet {
            self.fetchImage()
        }
    }
    
    var onImageUploaded: ((UIImage?) -> Void)?
    var onImageFetched: ((UIImage?) -> Void)?

    init(serviceManager: ServiceManager, onImageUploaded: @escaping (UIImage?) -> Void) {
        self.serviceManager = serviceManager
        self.onImageUploaded = onImageUploaded
        self.imageUrl = UserService.sharedInstance.user?.profileImageURL
    }
    
    func uploadImage(_ image: UIImage) {
        serviceManager.firebaseService.uploadImage(image) { [weak self] result in
            switch result {
            case .success(let urlString):
                print("Image uploaded successfully: \(urlString)")
                self?.imageUrl = urlString // Update imageUrl with the new URL.
                if let user = UserService.sharedInstance.user {
                    var updatedUser = user
                    updatedUser.profileImageURL = urlString
                    UserService.sharedInstance.updateUser(user: updatedUser)
                }
                self?.onImageUploaded?(image)

            case .failure(let error):
                print("Failed to upload image: \(error)")
                self?.showErrorAlert = true
                self?.errorText = error.localizedDescription
            }
        }
    }
    
    func fetchImage() {
        guard let urlString = self.imageUrl, let url = URL(string: urlString) else {
            self.fetchedImage = nil
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                return
            }
            DispatchQueue.main.async {
                self.fetchedImage = image
            }
        }
        task.resume()
    }
}

struct UploadImageView<Content: View>: View {
    @ObservedObject var viewModel: UploadImageViewModel
    let content: Content
    @State private var isPickerPresented: Bool = false  // Add this state variable

    init(viewModel: UploadImageViewModel, @ViewBuilder content: () -> Content) {
        self.viewModel = viewModel
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 16) {
            Button(action: {
                isPickerPresented = true  // Modify this line
            }) {
                content
            }
            .sheet(isPresented: $isPickerPresented, content: {
                ImagePicker(selectedImage: $viewModel.selectedImage, presentationMode: $isPickerPresented, showErrorAlert: $viewModel.showErrorAlert, errorText: $viewModel.errorText)
            })
            
            if viewModel.showErrorAlert {
                Text(viewModel.errorText)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}

struct UploadImageView_Previews: PreviewProvider {
    static var previews: some View {
        UploadImageView(viewModel: UploadImageViewModel(serviceManager: ServiceManager(), onImageUploaded: { image in
            print(image)
        })) {
            VStack {
                Image(systemName: "camera")
                    .font(.largeTitle)
                Text("Tap to upload image")
                    .font(.title)
            }
        }
    }
}
