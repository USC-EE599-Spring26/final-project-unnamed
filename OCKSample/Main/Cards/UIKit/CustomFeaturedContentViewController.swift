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

    // Need to override so we can become delegate when the user taps on card
    override init(
        imageOverlayStyle: UIUserInterfaceStyle = .unspecified
    ) {
        // See that this always calls the super
        super.init(imageOverlayStyle: imageOverlayStyle)

        // TODOx: 1 - Need to become a "delegate" so we know when view is tapped.
    }

    /*
     TODOx: 4 - Modify this init to take: UIImage, a text string , and text color.
     The initialize should set all of the respective properties.
     */
    // A convenience initializer to make it easier to use our custom featured content
    convenience init(
        url: String,
        imageOverlayStyle: UIUserInterfaceStyle = .unspecified
    ) {
        self.init(imageOverlayStyle: imageOverlayStyle)
        // TODOx: 2 - Need to call the designated initializer

        // TODOx: 3 - Need to turn the url string into a real URL using URL(string: String)
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
