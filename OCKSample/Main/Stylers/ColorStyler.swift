//
//  ColorStyler.swift
//  OCKSample
//
//  Created by Corey Baker on 10/16/21.
//  Copyright © 2021 Network Reconnaissance Lab. All rights reserved.
//

import CareKitUI
import SwiftUI
import UIKit

struct ColorStyler: OCKColorStyler {
    #if os(iOS) || os(visionOS)
    var label: UIColor {
        FontColorKey.defaultValue
    }

    // Change small labels color to darkGray
    var secondaryLabel: UIColor { .darkGray }

    // Change separator color to indigo
    var separator: UIColor { .systemIndigo }

    // Change tertiary label to brown
    var tertiaryLabel: UIColor {
        .brown
    }

    #endif
}
