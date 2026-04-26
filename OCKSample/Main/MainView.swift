//
//  MainView.swift
//  OCKSample
//
//  Created by Corey Baker on 11/25/20.
//  Copyright © 2020 Network Reconnaissance Lab. All rights reserved.

import CareKit
import CareKitEssentials
import CareKitStore
import CareKitUI
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    @StateObject private var loginViewModel = LoginViewModel()
    @State private var storeCoordinator = OCKStoreCoordinator()
	@State private var isLoggedIn: Bool?

    var body: some View {
		Group {
			if let isLoggedIn {
				if isLoggedIn {
					if isSyncingWithRemote {
						MainTabView(loginViewModel: loginViewModel)
							.navigationBarHidden(true)
					} else {
						CareView()
							.navigationBarHidden(true)
					}
				} else {
					LoginView(viewModel: loginViewModel)
				}
			} else {
				SplashScreenView()
			}
		}
		.task {
			await loginViewModel.checkStatus()
		}
        .overlay(alignment: .top) {
            if let message = appDelegate.detectionToast {
                DetectionToastView(message: message) {
                    appDelegate.detectionToast = nil
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appDelegate.detectionToast)
        .environment(\.careStore, storeCoordinator)
		.onReceive(appDelegate.$storeCoordinator) { newStoreCoordinator in
			guard storeCoordinator !== newStoreCoordinator else { return }
			storeCoordinator = newStoreCoordinator
		}
		.onReceive(loginViewModel.isLoggedIn.publisher) { currentStatus in
			isLoggedIn = currentStatus
        }
    }
}

/// Transient banner shown when the user taps the detected-exercise
/// notification's Log action. Auto-dismisses after a short delay.
private struct DetectionToastView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(radius: 4, y: 2)
            .onTapGesture { onDismiss() }
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                onDismiss()
            }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
            .environment(\.appDelegate, AppDelegate())
            .environment(\.careStore, Utility.createPreviewStore())
			.careKitStyle(Styler())
    }
}
