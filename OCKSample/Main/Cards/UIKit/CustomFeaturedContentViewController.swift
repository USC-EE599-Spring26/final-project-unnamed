//
//  CustomFeaturedContentViewController.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/29.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

#if os(iOS)

import UIKit
import CareKit
import CareKitUI

/// A simple subclass to take control of what CareKit already gives us.
class CustomFeaturedContentViewController: OCKFeaturedContentView {
    var url: URL?

    override init(
        imageOverlayStyle: UIUserInterfaceStyle = .unspecified
    ) {
        super.init(imageOverlayStyle: imageOverlayStyle)
        self.delegate = self
    }

    convenience init(
        url: String,
        image: UIImage?,
        text: String,
        textColor: UIColor = .white,
        imageOverlayStyle: UIUserInterfaceStyle = .unspecified
    ) {
        self.init(imageOverlayStyle: imageOverlayStyle)
        self.url = URL(string: url)
        self.imageView.image = image
        self.label.text = text
        self.label.textColor = textColor
    }
}

/// Need to conform to delegate in order to be delegated to.
extension CustomFeaturedContentViewController: @MainActor OCKFeaturedContentViewDelegate {

    func didTapView(_ view: OCKFeaturedContentView) {
        // When tapped open a URL.
        guard let url = url else {
            return
        }
        UIApplication.shared.open(url)
    }
}

#endif
