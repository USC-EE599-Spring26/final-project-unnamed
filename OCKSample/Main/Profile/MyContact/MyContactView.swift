//
//  MyContactView.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/2.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import SwiftUI
import UIKit
import CareKit
import CareKitStore
import os.log
#if os(ios)
struct MyContactView: UIViewControllerRepresentable {
    @Environment(\.careStore) var careStore

    func makeUIViewController(context: Context) -> some UIViewController {
        let viewController = createViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        return navigationController

    }

    func updateUIViewController(
        _ uiViewController: UIViewControllerType,
        context: Context
    ) {}

    func createViewController() -> UIViewController {
        let viewController = MyContactViewController(store: careStore)
        return viewController
    }
}

struct MyContactView_Previews: PreviewProvider {

    static var previews: some View {
        MyContactView()
            .environment(\.careStore, Utility.createPreviewStore())
            .accentColor(Color.accentColor)
    }
}

#else
struct MyContactView: View {
    var body: some View {
        Text("MyContact are not available on this platform.")
            .foregroundStyle(.secondary)
    }
}

struct MyContactView_Previews: PreviewProvider {
    static var previews: some View {
        MyContactView()
    }
}
#endif
