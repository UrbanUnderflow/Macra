//
//  NotificationPanel.swift
//  PuppySchool
//
//  Created by Tremaine Grant on 8/26/23.
//

import SwiftUI

class NotificationPanelViewModel: ObservableObject {
	let appCoordinator: AppCoordinator

	init(appCoordinator: AppCoordinator) {
		self.appCoordinator = appCoordinator
	}

}

struct NotificationPanelView: View {
	@ObservedObject var viewModel: NotificationPanelViewModel

    var message: some View {
        VStack {
            VStack {
                HStack {
                    Text("Handling Sensitization")
                        .font(.headline)
                        .foregroundColor(.secondaryWhite)
                    Spacer()
                }
                
                HStack {
                    VStack {
                        IconImage(Icon.custom(.oval))
                            .frame(width: 160, height: 160)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                    Text("Gently handle your puppy's paws, ears, and mouth regularly. This will make them more comfortable with being handled and will make future grooming and veterinary visits easier.")
                        .foregroundColor(.secondaryWhite)
                        .font(.subheadline)
                    }
                    .padding(.leading)
                }
                .padding(.bottom, 10)
                
                HStack {
                    Spacer()
                    Text("8 weeks")
                        .foregroundColor(.teal)
                        .font(.subheadline)
                        .bold()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(CardBackground(color: .primaryPurple))
            .padding(.horizontal, 20)
        }
    }
    
    var body: some View {
      VStack {
          HeaderView(viewModel: HeaderViewModel(headerTitle: "Alerts", theme: .dark, type: .close, closeModal: {
              viewModel.appCoordinator.closeModals()
              
          }, actionCallBack: {
              //
          }))
//          Divider(color: .white.opacity(0.2), height: 2)
              .padding(.bottom, 20)
          VStack(spacing: 12) {
              message
              message
          }
         Spacer()
          
      }
      .background(Color.primaryPurple)
    }
}

struct NotificationPanelView_Previews: PreviewProvider {
    static var previews: some View {
	NotificationPanelView(viewModel: NotificationPanelViewModel(appCoordinator: AppCoordinator(serviceManager: ServiceManager())))
    }
}
