import SwiftUI
import AVKit

struct PlayerView: UIViewRepresentable {
    var url: URL
    
    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<PlayerView>) {
    }
    
    func makeUIView(context: Context) -> UIView {
        return PlayerUIView(url: self.url)
    }
}
