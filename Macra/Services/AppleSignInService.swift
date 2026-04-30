import Foundation
import AuthenticationServices
import UIKit

final class AppleSignInService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    static let sharedInstance = AppleSignInService()

    var onSignIn: ((Result<String, Error>) -> Void)?

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return window
        }
        return ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let idTokenData = appleIDCredential.identityToken,
              let idTokenString = String(data: idTokenData, encoding: .utf8) else {
            onSignIn?(.failure(NSError(
                domain: "AppleSignInService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get Apple ID token."]
            )))
            return
        }

        onSignIn?(.success(idTokenString))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onSignIn?(.failure(error))
    }
}
