//
//  Loader.swift
//  FoodJournal
//
//  Created by Tremaine Grant on 8/29/23.
//

import SwiftUI

struct Loader: View {
    var loader: some View {
        Group {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.gray.opacity(0.5))
            .frame(width: 150, height: 150)
            .overlay(
                VStack {
                    LottieView(animationName: "loader")
                        .frame(width: 80, height: 80)
                    
                    Text("Thinking...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            )
        }
    }
    
    var body: some View {
        loader
    }
}

struct Loader_Previews: PreviewProvider {
    static var previews: some View {
        Loader()
    }
}
