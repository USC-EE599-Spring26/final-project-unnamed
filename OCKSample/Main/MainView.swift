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
import ParseSwift
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    @StateObject private var loginViewModel = LoginViewModel()
    @State private var storeCoordinator = OCKStoreCoordinator()
	@State private var isLoggedIn: Bool?
    @State private var userType: UserType = .patient

    var body: some View {
		Group {
			if let isLoggedIn {
				if isLoggedIn {
					if isSyncingWithRemote {
                        if userType == .clinician {
                            ClinicianTabView(loginViewModel: loginViewModel)
                                .navigationBarHidden(true)
                        } else {
                            MainTabView(loginViewModel: loginViewModel)
                                .navigationBarHidden(true)
                        }
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
            await fetchUserType()
		}
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if appDelegate.detectionSessionActive {
                    DetectionTrackingBanner {
                        Task { await appDelegate.exerciseDetector?.dismissActiveSession() }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let message = appDelegate.detectionToast {
                    DetectionToastView(message: message) {
                        appDelegate.detectionToast = nil
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .animation(.easeInOut(duration: 0.25), value: appDelegate.detectionToast)
        .animation(.easeInOut(duration: 0.25), value: appDelegate.detectionSessionActive)
        .environment(\.careStore, storeCoordinator)
		.onReceive(appDelegate.$storeCoordinator) { newStoreCoordinator in
			guard storeCoordinator !== newStoreCoordinator else { return }
			storeCoordinator = newStoreCoordinator
		}
        .onReceive(loginViewModel.isLoggedIn.publisher) { currentStatus in
            isLoggedIn = currentStatus
            if currentStatus == true {
                Task { await fetchUserType() }
            }
        }
    }

    @MainActor
    private func fetchUserType() async {
        guard let user = try? await User.current(),
              let typeString = user.lastTypeSelected,
              let type = UserType(rawValue: typeString) else {
            userType = .patient  // safe default
            return
        }
        userType = type
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

/// Persistent banner shown while a detected-exercise session is being tracked.
/// User can tap Dismiss to abort (mark the detection as a false positive).
private struct DetectionTrackingBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.headline)
            Text(String(localized: "DETECTED_EXERCISE_TRACKING_BANNER"))
                .font(.subheadline.weight(.medium))
            Spacer()
            Button(action: onDismiss) {
                Text(String(localized: "DETECTED_EXERCISE_TRACKING_BANNER_DISMISS"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.25))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 4, y: 2)
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
