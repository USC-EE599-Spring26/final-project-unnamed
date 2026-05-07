//
//  ClinicianTabView.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import CareKitUI
import SwiftUI

struct ClinicianTabView: View {
    @ObservedObject var loginViewModel: LoginViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CarePlanManagementView()
                .tabItem {
                    if selectedTab == 0 {
                        Image(systemName: "chart.line.text.clipboard")
                            .renderingMode(.template)
                    } else {
                        Image(systemName: "chart.line.text.clipboard.fill")
                            .renderingMode(.template)
                    }
                }
                .tag(0)

            PatientManagementView()
                .tabItem {
                    if selectedTab == 1 {
                        Image(systemName: "person.3.fill")
                            .renderingMode(.template)
                    } else {
                        Image(systemName: "person.3")
                            .renderingMode(.template)
                    }
                }
                .tag(1)

            ContactView()
                .tabItem {
                    if selectedTab == 2 {
                        Image(systemName: "phone.bubble.fill")
                            .renderingMode(.template)
                    } else {
                        Image(systemName: "phone.bubble")
                            .renderingMode(.template)
                    }
                }
                .tag(2)

            ProfileView(loginViewModel: loginViewModel)
                .tabItem {
                    if selectedTab == 3 {
                        Image(systemName: "person.circle.fill")
                            .renderingMode(.template)
                    } else {
                        Image(systemName: "person.circle")
                            .renderingMode(.template)
                    }
                }
                .tag(3)
        }
    }
}
