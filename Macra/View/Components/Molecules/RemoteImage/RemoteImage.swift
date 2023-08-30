import Foundation
import SwiftUI
import Combine

struct RemoteImage: View {
    let url: String
    @State private var imageData: Data? = nil
    @State private var isImageLoading = false
    @State private var loadingError: Error? = nil

    var body: some View {
        Group {
            if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
            } else if isImageLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
            }
        }
        .onAppear(perform: loadImage)
    }

    func loadImage() {
        guard let imageURL = URL(string: url) else {
            print("Invalid URL.")
            return
        }

        isImageLoading = true

        let task = URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                self.isImageLoading = false
                if let error = error {
                    self.loadingError = error
                    print("Error loading image: \(error.localizedDescription)")
                    return
                }
                self.imageData = data
            }
        }
        task.resume()
    }
}
