//
//  HeaderView.swift
//  PuppySchool
//
//  Created by Tremaine Grant on 8/19/23.
//

import SwiftUI

class HeaderViewModel: ObservableObject {
    enum HeaderType {
        case close
        case back
    }
    
    enum ThemeType {
        case light
        case dark
    }
    
    @Published var headerTitle: String
    @Published var theme: ThemeType
    @Published var type: HeaderType
    
    var closeModal: (() -> Void)? // Make this optional
    var actionCallBack: () -> Void

    init(headerTitle: String, theme: ThemeType = .light, type: HeaderType = .close, closeModal: (() -> Void)? = nil, actionCallBack: @escaping () -> Void) {
        self.headerTitle = headerTitle
        self.theme = theme
        self.type = type
        self.closeModal = closeModal
        self.actionCallBack = actionCallBack
    }
}

struct HeaderView: View {
    @ObservedObject var viewModel: HeaderViewModel
    
    
    var body: some View {
        VStack {
            HStack {
                if let closeAction = viewModel.closeModal { //
                    if viewModel.type == .back {
                        BackButton().onTapGesture {
                            closeAction()
                        }
                        .padding(.leading, 20)
                    } else {
                        CloseButtonView {
                            closeAction()
                        }
                        .padding(.leading, 20)
                    }
                } else {
                    Spacer()
                        .frame(width: 24, height: 24)
                        .padding(.leading, 20)
                }

                Spacer()
                Text(viewModel.headerTitle)
                    .foregroundColor(viewModel.theme == .dark ? .secondaryWhite : .black)
                    .font(.headline)
                    .padding()
                Spacer()
            }
        }
    }
}

struct HeaderView_Previews: PreviewProvider {
    static var previews: some View {
        HeaderView(viewModel: HeaderViewModel(headerTitle: "Test", closeModal: {
            print("close")
        }, actionCallBack: {
            print("action")
        }))
    }
}
