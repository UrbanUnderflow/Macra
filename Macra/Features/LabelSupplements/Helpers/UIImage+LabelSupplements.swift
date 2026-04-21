import UIKit

extension UIImage {
    func toBase64(compressionQuality: CGFloat = 0.85) -> String? {
        guard let data = jpegData(compressionQuality: compressionQuality) else {
            return nil
        }
        return data.base64EncodedString()
    }
}

